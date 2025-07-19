defmodule Arsenal.Operations.Distributed.ClusterTopology do
  @moduledoc """
  Arsenal operation to get real-time cluster topology and node information.

  This operation provides comprehensive cluster state including node health,
  connectivity, and process distribution across the cluster.
  """

  use Arsenal.Operation

  def rest_config do
    %{
      method: :get,
      path: "/api/v1/cluster/topology",
      summary: "Get real-time cluster topology and node information",
      parameters: [
        %{
          name: :include_processes,
          type: :boolean,
          required: false,
          location: :query,
          description: "Include process distribution information"
        },
        %{
          name: :include_health,
          type: :boolean,
          required: false,
          location: :query,
          description: "Include detailed node health metrics"
        }
      ],
      responses: %{
        200 => %{description: "Cluster topology information"}
      }
    }
  end

  def validate_params(params) do
    # Convert string boolean parameters
    validated_params =
      params
      |> convert_boolean_param("include_processes", false)
      |> convert_boolean_param("include_health", true)

    {:ok, validated_params}
  end

  def execute(_params) do
    # TODO: Implement cluster topology functionality when clustering is available
    {:error, :cluster_not_available}
  end

  def format_response(topology) do
    %{
      data: topology,
      timestamp: DateTime.utc_now(),
      success: true,
      metadata: %{
        operation: "ClusterTopology",
        cluster_size: topology.total_nodes,
        simulation_mode: Map.get(topology, :simulation_mode, false)
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
