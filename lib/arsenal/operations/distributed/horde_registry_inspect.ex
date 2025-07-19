defmodule Arsenal.Operations.Distributed.HordeRegistryInspect do
  @moduledoc """
  Arsenal operation to inspect Horde registry state across the cluster.

  This operation provides information about processes registered in the Horde
  registry, including their location, metadata, and health status.
  """

  use Arsenal.Operation

  @impl true
  def name(), do: :horde_registry_inspect

  @impl true
  def category(), do: :distributed

  @impl true
  def description(), do: "Inspect Horde registry state"

  @impl true
  def params_schema(), do: %{}

  @impl true
  def rest_config do
    %{
      method: :get,
      path: "/api/v1/cluster/horde-registry",
      summary: "Inspect Horde registry state across the cluster",
      parameters: [
        %{
          name: :process_name,
          type: :string,
          required: false,
          location: :query,
          description: "Filter by specific process name"
        },
        %{
          name: :node,
          type: :string,
          required: false,
          location: :query,
          description: "Filter by specific node"
        },
        %{
          name: :include_metadata,
          type: :boolean,
          required: false,
          location: :query,
          description: "Include process metadata"
        }
      ],
      responses: %{
        200 => %{description: "Horde registry state retrieved successfully"},
        500 => %{description: "Failed to retrieve Horde registry state"}
      }
    }
  end

  @impl true
  def validate_params(params) do
    validated_params =
      params
      |> convert_boolean_param("include_metadata", false)

    {:ok, validated_params}
  end

  @impl true
  def execute(_params) do
    # TODO: Implement Horde registry inspection when clustering is available
    {:error, :cluster_not_available}
  end

  @impl true
  def format_response(result) do
    %{
      data: result,
      timestamp: DateTime.utc_now(),
      success: true,
      metadata: %{
        operation: "HordeRegistryInspect"
      }
    }
  end

  # Private helper functions

  defp convert_boolean_param(params, key, default) do
    case Map.get(params, key) do
      nil -> Map.put(params, key, default)
      "true" -> Map.put(params, key, true)
      "false" -> Map.put(params, key, false)
      true -> Map.put(params, key, true)
      false -> Map.put(params, key, false)
      _ -> Map.put(params, key, default)
    end
  end
end
