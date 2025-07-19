defmodule Arsenal.Operations.DestroySandbox do
  @moduledoc """
  Operation to destroy/terminate a sandbox environment.
  """

  use Arsenal.Operation

  def rest_config do
    %{
      method: :delete,
      path: "/api/v1/sandboxes/:sandbox_id",
      summary: "Destroy a sandbox environment",
      parameters: [
        %{
          name: :sandbox_id,
          type: :string,
          required: true,
          description: "Unique identifier of the sandbox to destroy",
          location: :path
        },
        %{
          name: :force,
          type: :boolean,
          required: false,
          description: "Force destruction even if sandbox has running processes",
          location: :query
        }
      ],
      responses: %{
        200 => %{
          description: "Sandbox destroyed successfully",
          schema: %{
            type: :object,
            properties: %{
              data: %{
                type: :object,
                properties: %{
                  sandbox_id: %{type: :string},
                  destroyed: %{type: :boolean},
                  destroyed_at: %{type: :string}
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
      "force" => Map.get(params, "force", false)
    }

    {:ok, validated_params}
  rescue
    error -> {:error, {:invalid_parameters, error}}
  end

  def validate_params(_params) do
    {:error, {:missing_parameter, "sandbox_id is required"}}
  end

  def execute(%{"sandbox_id" => sandbox_id, "force" => _force}) do
    case get_sandbox_info(sandbox_id) do
      {:error, :not_found} ->
        {:error, :sandbox_not_found}
    end
  end

  def format_response({sandbox_id, destroyed_at}) do
    %{
      data: %{
        sandbox_id: sandbox_id,
        destroyed: true,
        destroyed_at: DateTime.to_iso8601(destroyed_at)
      }
    }
  end

  defp validate_sandbox_id(sandbox_id) when is_binary(sandbox_id) and byte_size(sandbox_id) > 0 do
    sandbox_id
  end

  defp validate_sandbox_id(_), do: raise("sandbox_id must be a non-empty string")

  # TODO: Replace with Arsenal.SandboxManager when available
  defp get_sandbox_info(_sandbox_id) do
    {:error, :not_found}
  end
end
