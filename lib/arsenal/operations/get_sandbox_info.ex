defmodule Arsenal.Operations.GetSandboxInfo do
  @moduledoc """
  Operation to get detailed information about a specific sandbox.
  """

  use Arsenal.Operation

  def rest_config do
    %{
      method: :get,
      path: "/api/v1/sandboxes/:sandbox_id",
      summary: "Get detailed information about a sandbox",
      parameters: [
        %{
          name: :sandbox_id,
          type: :string,
          required: true,
          description: "Unique identifier of the sandbox",
          location: :path
        },
        %{
          name: :include_children,
          type: :boolean,
          required: false,
          description: "Include supervisor children information",
          location: :query
        },
        %{
          name: :include_stats,
          type: :boolean,
          required: false,
          description: "Include performance and health statistics",
          location: :query
        }
      ],
      responses: %{
        200 => %{
          description: "Sandbox information retrieved successfully",
          schema: %{
            type: :object,
            properties: %{
              data: %{
                type: :object,
                properties: %{
                  id: %{type: :string},
                  app_name: %{type: :string},
                  supervisor_module: %{type: :string},
                  app_pid: %{type: :string},
                  supervisor_pid: %{type: :string},
                  status: %{type: :string},
                  created_at: %{type: :integer},
                  restart_count: %{type: :integer},
                  uptime_seconds: %{type: :integer},
                  children: %{type: :array},
                  memory_usage: %{type: :object},
                  health_stats: %{type: :object}
                }
              }
            }
          }
        },
        404 => %{description: "Sandbox not found"},
        400 => %{description: "Invalid parameters"}
      }
    }
  end

  def validate_params(%{"sandbox_id" => sandbox_id} = params) do
    validated_params = %{
      "sandbox_id" => validate_sandbox_id(sandbox_id),
      "include_children" => parse_boolean(Map.get(params, "include_children", false)),
      "include_stats" => parse_boolean(Map.get(params, "include_stats", false))
    }

    {:ok, validated_params}
  rescue
    error -> {:error, {:invalid_parameters, error}}
  end

  def validate_params(_params) do
    {:error, {:missing_parameter, "sandbox_id is required"}}
  end

  def execute(%{
        "sandbox_id" => sandbox_id,
        "include_children" => include_children,
        "include_stats" => include_stats
      }) do
    # TODO: Replace with Arsenal.SandboxManager when available
    case get_sandbox_info_placeholder(sandbox_id) do
      {:error, :not_found} ->
        {:error, :sandbox_not_found}

      sandbox_info ->
        enriched_info = enrich_sandbox_info(sandbox_info, include_children, include_stats)
        {:ok, enriched_info}
    end
  end

  def format_response(sandbox_info) do
    %{
      data: sandbox_info
    }
  end

  # TODO: Replace with actual SandboxManager implementation
  defp get_sandbox_info_placeholder(sandbox_id) do
    # Simulate sandbox not found for IDs starting with "missing"
    if String.starts_with?(sandbox_id, "missing") do
      {:error, :not_found}
    else
      # Return mock data for testing until SandboxManager is implemented
      %{
        id: sandbox_id,
        app_name: :test_app,
        supervisor_module: TestSupervisor,
        app_pid: self(),
        supervisor_pid: self(),
        created_at: DateTime.utc_now(),
        restart_count: 0,
        opts: [strategy: :one_for_one, max_restarts: 5]
      }
    end
  end

  defp validate_sandbox_id(sandbox_id) when is_binary(sandbox_id) and byte_size(sandbox_id) > 0 do
    sandbox_id
  end

  defp validate_sandbox_id(_), do: raise("sandbox_id must be a non-empty string")

  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(_), do: false

  defp enrich_sandbox_info(sandbox_info, include_children, include_stats) do
    base_info = %{
      id: sandbox_info.id,
      app_name: sandbox_info.app_name,
      supervisor_module: format_module_name(sandbox_info.supervisor_module),
      app_pid: inspect(sandbox_info.app_pid),
      supervisor_pid: inspect(sandbox_info.supervisor_pid),
      status: get_sandbox_status(sandbox_info),
      created_at: sandbox_info.created_at,
      restart_count: sandbox_info.restart_count,
      uptime_seconds: calculate_uptime(sandbox_info.created_at),
      configuration: format_sandbox_config(sandbox_info.opts)
    }

    base_info
    |> maybe_add_children(sandbox_info, include_children)
    |> maybe_add_stats(sandbox_info, include_stats)
  end

  defp get_sandbox_status(sandbox_info) do
    if Process.alive?(sandbox_info.app_pid) do
      "running"
    else
      "stopped"
    end
  end

  defp calculate_uptime(created_at) do
    current_time = System.system_time(:millisecond)
    created_at_ms = DateTime.to_unix(created_at, :millisecond)
    div(current_time - created_at_ms, 1000)
  end

  defp maybe_add_children(info, sandbox_info, include_children)
       when include_children in [true, "true"] do
    children = get_supervisor_children(sandbox_info.supervisor_pid)
    Map.put(info, :children, children)
  end

  defp maybe_add_children(info, _sandbox_info, _), do: info

  defp maybe_add_stats(info, _sandbox_info, include_stats) when include_stats in [true, "true"] do
    # TODO: Implement actual stats collection when SandboxManager is available
    info
    |> Map.put(:memory_usage, %{total_bytes: 0, percentage: 0.0})
    |> Map.put(:health_stats, %{restarts_per_hour: 0.0, error_rate: 0.0, avg_memory_mb: 0.0})
  end

  defp maybe_add_stats(info, _sandbox_info, _), do: info

  defp get_supervisor_children(_supervisor_pid) do
    # TODO: Replace with actual supervisor inspection when SandboxManager is available
    [
      %{
        id: :worker_1,
        pid: "<0.999.0>",
        type: :worker,
        restart: :permanent,
        child_spec: "Worker.Spec"
      }
    ]
  end

  defp format_module_name(module), do: Atom.to_string(module)

  defp format_sandbox_config(opts) when is_list(opts) do
    # TODO: Implement actual config formatting when SandboxManager is available
    opts
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
    |> Enum.into(%{})
  end
end
