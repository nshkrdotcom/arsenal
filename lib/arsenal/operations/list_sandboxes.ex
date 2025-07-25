defmodule Arsenal.Operations.ListSandboxes do
  @moduledoc """
  Operation to list all sandboxes in the system.
  """

  use Arsenal.Operation

  @impl true
  def name(), do: :list_sandboxes

  @impl true
  def category(), do: :sandbox

  @impl true
  def description(), do: "List all sandbox environments"

  @impl true
  def params_schema(), do: %{}

  @impl true
  def rest_config do
    %{
      method: :get,
      path: "/api/v1/sandboxes",
      summary: "List all sandboxes in the system",
      parameters: [
        %{
          name: :status,
          type: :string,
          required: false,
          description: "Filter sandboxes by status (running, stopped)",
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
          description: "Items per page (default: 20, max: 100)",
          location: :query
        }
      ],
      responses: %{
        200 => %{
          description: "Sandboxes retrieved successfully",
          schema: %{
            type: :object,
            properties: %{
              data: %{
                type: :array,
                items: %{
                  type: :object,
                  properties: %{
                    id: %{type: :string},
                    app_name: %{type: :string},
                    supervisor_module: %{type: :string},
                    app_pid: %{type: :string},
                    supervisor_pid: %{type: :string},
                    status: %{type: :string},
                    created_at: %{type: :integer},
                    restart_count: %{type: :integer}
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
    status_val = validate_status(Map.get(params, "status"))
    page_val = parse_positive_integer(Map.get(params, "page", "1"), 1)
    per_page_val = parse_per_page(Map.get(params, "per_page", "20"))

    validated = %{
      "status" => status_val,
      "page" => page_val,
      "per_page" => per_page_val
    }

    {:ok, validated}
  rescue
    error -> {:error, {:invalid_parameters, error}}
  end

  @impl true
  def execute(params) do
    try do
      # TODO: Replace with Arsenal.SandboxManager when available
      all_sandboxes = list_sandboxes_placeholder()

      # Filter by status if specified
      filtered_sandboxes =
        case params["status"] do
          nil -> all_sandboxes
          status -> filter_by_status(all_sandboxes, status)
        end

      # Apply pagination
      {paginated_data, meta} = paginate(filtered_sandboxes, params["page"], params["per_page"])

      {:ok, {paginated_data, meta}}
    rescue
      error -> {:error, {:sandbox_discovery_failed, error}}
    end
  end

  @impl true
  def format_response({sandboxes, meta}) do
    %{
      data: Enum.map(sandboxes, &format_sandbox_info/1),
      meta: meta
    }
  end

  # TODO: Replace with actual SandboxManager implementation
  defp list_sandboxes_placeholder, do: []

  defp validate_status(nil), do: nil
  defp validate_status(status) when status in ["running", "stopped"], do: status
  defp validate_status(_), do: raise("Invalid status filter")

  defp parse_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp parse_positive_integer(_, default), do: default

  defp parse_per_page(value) do
    per_page = parse_positive_integer(value, 20)
    # Cap at 100
    min(per_page, 100)
  end

  defp filter_by_status(sandboxes, status) do
    Enum.filter(sandboxes, fn sandbox ->
      sandbox_status = get_sandbox_status(sandbox)
      sandbox_status == status
    end)
  end

  defp get_sandbox_status(sandbox) do
    if Process.alive?(sandbox.app_pid) do
      "running"
    else
      "stopped"
    end
  end

  defp paginate(items, page, per_page) do
    # Ensure page and per_page are integers and at least 1
    safe_per_page =
      case per_page do
        n when is_number(n) -> max(Kernel.trunc(n), 1)
        _ -> 20
      end

    safe_page =
      case page do
        n when is_number(n) -> max(Kernel.trunc(n), 1)
        _ -> 1
      end

    total = length(items)
    total_pages = ceil(total / safe_per_page)
    offset = (safe_page - 1) * safe_per_page

    paginated_items =
      items
      |> Enum.drop(offset)
      |> Enum.take(safe_per_page)

    meta = %{
      total: total,
      page: safe_page,
      per_page: safe_per_page,
      total_pages: total_pages
    }

    {paginated_items, meta}
  end

  defp format_sandbox_info(sandbox) do
    %{
      id: sandbox.id,
      app_name: sandbox.app_name,
      supervisor_module: format_module_name(sandbox.supervisor_module),
      app_pid: inspect(sandbox.app_pid),
      supervisor_pid: inspect(sandbox.supervisor_pid),
      status: get_sandbox_status(sandbox),
      created_at: sandbox.created_at,
      restart_count: sandbox.restart_count,
      configuration: format_sandbox_config(sandbox.opts)
    }
  end

  defp format_module_name(module) when is_atom(module), do: Atom.to_string(module)
  defp format_module_name(module), do: inspect(module)

  defp format_sandbox_config(opts) when is_list(opts) do
    opts
    |> Enum.into(%{})
    |> Enum.map(fn
      # Convert compile_info to a JSON-serializable format
      {:compile_info, compile_info} ->
        {"compile_info", format_compile_info(compile_info)}

      # Convert atom keys to strings
      {key, value} when is_atom(key) ->
        {Atom.to_string(key), format_config_value(value)}

      # Keep string keys as-is
      {key, value} ->
        {key, format_config_value(value)}
    end)
    |> Enum.into(%{})
  end

  defp format_compile_info(compile_info) when is_map(compile_info) do
    %{
      "compilation_time_ms" => compile_info.compilation_time,
      "beam_files_count" => length(compile_info.beam_files),
      "output_summary" => String.slice(compile_info.output, 0, 100),
      "temp_dir" => compile_info.temp_dir
    }
  end

  defp format_config_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_config_value(value), do: value
end
