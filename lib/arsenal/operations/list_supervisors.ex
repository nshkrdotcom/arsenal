defmodule Arsenal.Operations.ListSupervisors do
  @moduledoc """
  Operation to list all supervisors in the system.
  """

  use Arsenal.Operation

  @impl true
  def name(), do: :list_supervisors

  @impl true
  def category(), do: :supervisor

  @impl true
  def description(), do: "List all supervisors in the system"

  @impl true
  def params_schema() do
    %{
      include_children: [type: :boolean, default: false]
    }
  end

  @impl true
  def rest_config do
    %{
      method: :get,
      path: "/api/v1/supervisors",
      summary: "List all supervisors in the system",
      parameters: [
        %{
          name: :include_children,
          type: :boolean,
          required: false,
          description: "Include children information for each supervisor",
          location: :query
        },
        %{
          name: :filter_application,
          type: :string,
          required: false,
          description: "Filter supervisors by application name",
          location: :query
        },
        %{
          name: :page,
          type: :integer,
          required: false,
          description: "Page number for pagination (default: 1)",
          location: :query
        },
        %{
          name: :per_page,
          type: :integer,
          required: false,
          description: "Items per page (default: 50, max: 100)",
          location: :query
        }
      ],
      responses: %{
        200 => %{
          description: "Supervisors retrieved successfully",
          schema: %{
            type: :object,
            properties: %{
              data: %{
                type: :array,
                items: %{
                  type: :object,
                  properties: %{
                    name: %{type: :string},
                    pid: %{type: :string},
                    alive: %{type: :boolean},
                    child_count: %{type: :integer},
                    strategy: %{type: :string},
                    application: %{type: :string}
                  }
                }
              },
              meta: %{
                type: :object,
                properties: %{
                  total: %{type: :integer},
                  page: %{type: :integer},
                  per_page: %{type: :integer},
                  total_pages: %{type: :integer}
                }
              }
            }
          }
        }
      }
    }
  end

  @impl true
  def validate_params(params) do
    validated = %{
      "include_children" => parse_boolean(Map.get(params, "include_children", false)),
      "filter_application" => Map.get(params, "filter_application"),
      "page" => parse_positive_integer(Map.get(params, "page", "1"), 1),
      "per_page" => parse_per_page(Map.get(params, "per_page", "50"))
    }

    {:ok, validated}
  rescue
    error -> {:error, {:invalid_parameters, error}}
  end

  @impl true
  def execute(params) do
    try do
      supervisors = discover_supervisors()

      # Filter by application if specified
      filtered_supervisors =
        case params["filter_application"] do
          nil -> supervisors
          app_name -> filter_by_application(supervisors, app_name)
        end

      # Add children information if requested
      enriched_supervisors =
        case params["include_children"] do
          true -> add_children_info(filtered_supervisors)
          false -> filtered_supervisors
        end

      # Apply pagination
      {paginated_data, meta} = paginate(enriched_supervisors, params["page"], params["per_page"])

      {:ok, {paginated_data, meta}}
    rescue
      error -> {:error, {:discovery_failed, error}}
    end
  end

  @impl true
  def format_response({supervisors, meta}) do
    %{
      data: Enum.map(supervisors, &format_supervisor_info/1),
      meta: meta
    }
  end

  defp parse_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp parse_positive_integer(_, default), do: default

  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(_), do: false

  defp parse_per_page(value) do
    per_page = parse_positive_integer(value, 50)
    # Cap at 100
    min(per_page, 100)
  end

  defp discover_supervisors do
    Process.list()
    |> Enum.map(&build_supervisor_info_safely/1)
    # Filter out non-supervisors and processes that failed checks
    |> Enum.filter(&(&1 != nil))
  end

  defp build_supervisor_info_safely(pid) do
    # Multiple cheap checks before attempting supervisor calls
    with {:trap_exit, true} <- Process.info(pid, :trap_exit),
         {:initial_call, initial_call} <- Process.info(pid, :initial_call),
         true <- looks_like_supervisor?(initial_call) do
      # The process traps exits and has supervisor-like initial call
      # Now perform the potentially blocking supervisor check safely
      details = get_supervisor_details_safely(pid)

      if details.is_supervisor do
        %{
          name: get_process_name(pid),
          pid: pid,
          alive: true,
          child_count: details.child_count,
          # Alias for compatibility
          children_count: details.child_count,
          strategy: details.strategy,
          application: get_process_application_from_pid(pid)
        }
      else
        # Not a supervisor
        nil
      end
    else
      # Failed basic checks, not a supervisor
      _ -> nil
    end
  rescue
    # In case Process.info fails (e.g., process died mid-check)
    ArgumentError -> nil
  end

  # Check if the initial call looks like a supervisor
  defp looks_like_supervisor?({:supervisor, _, _}), do: true

  defp looks_like_supervisor?({module, _, _}) do
    # Check if module name contains "Supervisor" or "Sup"
    module_string = to_string(module)

    String.contains?(module_string, "Supervisor") or
      String.contains?(module_string, "Sup") or
      String.ends_with?(module_string, ".Supervisor")
  end

  defp looks_like_supervisor?(_), do: false

  defp get_supervisor_details_safely(pid) do
    # This task isolates the potentially blocking call in a separate process.
    task =
      Task.async(fn ->
        try do
          # Supervisor.which_children/1 is a reliable check. If it succeeds, it's a supervisor.
          children = Supervisor.which_children(pid)

          # If that works, also try to get the strategy.
          strategy =
            case :sys.get_state(pid) do
              %{strategy: s} -> s
              _ -> :unknown
            end

          %{is_supervisor: true, child_count: length(children), strategy: strategy}
        rescue
          _ -> %{is_supervisor: false}
        catch
          :exit, _ -> %{is_supervisor: false}
        end
      end)

    # Wait for a short period. A responsive supervisor will reply almost instantly.
    # Non-supervisors will cause a timeout here, which we handle gracefully.
    case Task.yield(task, 200) do
      {:ok, result} ->
        Task.shutdown(task)
        result

      _ ->
        # Task timed out or crashed.
        Task.shutdown(task, :brutal_kill)
        %{is_supervisor: false, child_count: 0, strategy: :unknown}
    end
  end

  defp get_process_name(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, name} when name != [] -> name
      # Fallback to the PID itself if it has no registered name
      _ -> pid
    end
  end

  defp get_process_application_from_pid(pid) do
    case :application.get_application(pid) do
      {:ok, app} -> app
      :undefined -> :system
    end
  end

  defp filter_by_application(supervisors, app_name) do
    app_atom = String.to_existing_atom(app_name)

    Enum.filter(supervisors, fn supervisor ->
      supervisor.application == app_atom
    end)
  rescue
    # Invalid application name
    ArgumentError -> []
  end

  defp add_children_info(supervisors) do
    Enum.map(supervisors, fn supervisor ->
      children_info = get_supervisor_children(supervisor.pid)
      Map.merge(supervisor, children_info)
    end)
  end

  defp get_supervisor_children(pid_string) when is_binary(pid_string) do
    try do
      pid = String.to_existing_atom(pid_string)
      pid = Process.whereis(pid)
      get_supervisor_children(pid)
    rescue
      _ ->
        %{
          child_count: 0,
          strategy: :unknown,
          children: []
        }
    end
  end

  defp get_supervisor_children(pid) when is_pid(pid) do
    try do
      children = Supervisor.which_children(pid)
      strategy = get_supervisor_strategy(pid)

      %{
        child_count: length(children),
        strategy: strategy,
        children: format_children(children)
      }
    rescue
      _ ->
        %{
          child_count: 0,
          strategy: :unknown,
          children: []
        }
    catch
      :exit, _ ->
        %{
          child_count: 0,
          strategy: :unknown,
          children: []
        }
    end
  end

  defp get_supervisor_children(_), do: %{child_count: 0, strategy: :unknown, children: []}

  defp get_supervisor_strategy(pid) do
    try do
      case :sys.get_state(pid) do
        %{strategy: strategy} -> strategy
        _ -> :unknown
      end
    rescue
      _ -> :unknown
    end
  end

  defp format_children(children) do
    Enum.map(children, fn {id, child_pid, type, modules} ->
      %{
        id: id,
        pid: if(is_pid(child_pid), do: inspect(child_pid), else: child_pid),
        type: type,
        modules: modules
      }
    end)
  end

  defp paginate(items, page, per_page) do
    total = length(items)
    total_pages = ceil(total / per_page)
    offset = (page - 1) * per_page

    paginated_items =
      items
      |> Enum.drop(offset)
      |> Enum.take(per_page)

    meta = %{
      total: total,
      page: page,
      per_page: per_page,
      total_pages: total_pages
    }

    {paginated_items, meta}
  end

  defp format_supervisor_info(supervisor) do
    %{
      name: format_name(supervisor.name),
      pid: inspect(supervisor.pid),
      alive: supervisor.alive,
      child_count: Map.get(supervisor, :child_count, 0),
      strategy: Map.get(supervisor, :strategy, :unknown),
      application: supervisor.application,
      children: Map.get(supervisor, :children, [])
    }
  end

  defp format_name(name) when is_atom(name), do: Atom.to_string(name)
  defp format_name(pid) when is_pid(pid), do: inspect(pid)
  defp format_name(name), do: inspect(name)
end
