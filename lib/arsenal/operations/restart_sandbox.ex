defmodule Arsenal.Operations.RestartSandbox do
  @moduledoc """
  Operation to restart a sandbox environment.
  """

  use Arsenal.Operation

  @impl true
  def name(), do: :restart_sandbox

  @impl true
  def category(), do: :sandbox

  @impl true
  def description(), do: "Restart a sandbox environment"

  @impl true
  def params_schema(), do: %{}

  @impl true
  def rest_config do
    %{
      method: :post,
      path: "/api/v1/sandboxes/:sandbox_id/restart",
      summary: "Restart a sandbox environment",
      parameters: [
        %{
          name: :sandbox_id,
          type: :string,
          required: true,
          description: "Unique identifier of the sandbox to restart",
          location: :path
        }
      ],
      responses: %{
        200 => %{
          description: "Sandbox restarted successfully",
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
                  restart_count: %{type: :integer},
                  restarted_at: %{type: :string}
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

  @impl true
  def validate_params(%{"sandbox_id" => sandbox_id}) do
    validated_params = %{
      "sandbox_id" => validate_sandbox_id(sandbox_id)
    }

    {:ok, validated_params}
  rescue
    error -> {:error, {:invalid_parameters, error}}
  end

  @impl true
  def validate_params(_params) do
    {:error, {:missing_parameter, "sandbox_id is required"}}
  end

  @impl true
  def execute(%{"sandbox_id" => _sandbox_id}) do
    # TODO: Replace with Arsenal.SandboxManager when available
    {:error, :sandbox_not_found}
  end

  @impl true
  def format_response({sandbox_info, restarted_at}) do
    %{
      data: %{
        id: sandbox_info.id,
        app_name: sandbox_info.app_name,
        supervisor_module: format_module_name(sandbox_info.supervisor_module),
        app_pid: inspect(sandbox_info.app_pid),
        supervisor_pid: inspect(sandbox_info.supervisor_pid),
        status: "running",
        restart_count: sandbox_info.restart_count,
        restarted_at: DateTime.to_iso8601(restarted_at),
        opts: sandbox_info.opts
      }
    }
  end

  defp validate_sandbox_id(sandbox_id) when is_binary(sandbox_id) and byte_size(sandbox_id) > 0 do
    sandbox_id
  end

  defp validate_sandbox_id(_), do: raise("sandbox_id must be a non-empty string")

  defp format_module_name(module) when is_atom(module), do: Atom.to_string(module)
  defp format_module_name(module), do: inspect(module)
end
