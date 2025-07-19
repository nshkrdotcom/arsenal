defmodule Arsenal.Operations.HotReloadSandbox do
  @moduledoc """
  Operation to hot reload a sandbox with updated code.
  """

  use Arsenal.Operation, compat: true

  def rest_config do
    %{
      method: :post,
      path: "/api/v1/sandboxes/:sandbox_id/hot-reload",
      summary: "Hot reload a sandbox with updated code",
      parameters: [
        %{
          name: :sandbox_id,
          type: :string,
          required: true,
          description: "Unique identifier of the sandbox to reload",
          location: :path
        },
        %{
          name: :module,
          type: :string,
          required: false,
          description: "Specific module to reload (defaults to supervisor module)",
          location: :body
        }
      ],
      responses: %{
        200 => %{
          description: "Hot reload successful",
          schema: %{
            type: :object,
            properties: %{
              data: %{
                type: :object,
                properties: %{
                  sandbox_id: %{type: :string},
                  reloaded_module: %{type: :string},
                  previous_version: %{type: :integer},
                  new_version: %{type: :integer},
                  compilation_time_ms: %{type: :integer},
                  status: %{type: :string}
                }
              }
            }
          }
        },
        404 => %{description: "Sandbox not found"},
        400 => %{description: "Invalid parameters"},
        500 => %{description: "Hot reload failed"}
      }
    }
  end

  def validate_params(%{"sandbox_id" => sandbox_id} = params) do
    validated_params = %{
      "sandbox_id" => validate_sandbox_id(sandbox_id),
      "module" => Map.get(params, "module")
    }

    {:ok, validated_params}
  rescue
    error -> {:error, {:invalid_parameters, error}}
  end

  def validate_params(_params) do
    {:error, {:missing_parameter, "sandbox_id is required"}}
  end

  def execute(%{"sandbox_id" => sandbox_id, "module" => _module_name}) do
    # TODO: Replace with Arsenal.SandboxManager when available
    case get_sandbox_info_placeholder(sandbox_id) do
      {:error, :not_found} ->
        {:error, :sandbox_not_found}
    end
  end

  def format_response(result) do
    %{data: result}
  end

  defp validate_sandbox_id(sandbox_id) when is_binary(sandbox_id) and byte_size(sandbox_id) > 0 do
    sandbox_id
  end

  defp validate_sandbox_id(_), do: raise("sandbox_id must be a non-empty string")

  # TODO: Replace with actual implementations
  defp get_sandbox_info_placeholder(_sandbox_id), do: {:error, :not_found}
end
