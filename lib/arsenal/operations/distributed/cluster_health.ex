defmodule Arsenal.Operations.Distributed.ClusterHealth do
  @moduledoc """
  Arsenal operation for real-time cluster health monitoring.

  This operation provides comprehensive cluster health information including
  node status, resource usage, connectivity, and performance metrics.
  """

  use Arsenal.Operation, compat: true

  def rest_config do
    %{
      method: :get,
      path: "/api/v1/cluster/health",
      summary: "Get real-time cluster health and performance metrics",
      parameters: [
        %{
          name: :include_metrics,
          type: :boolean,
          required: false,
          location: :query,
          description: "Include detailed performance metrics"
        },
        %{
          name: :include_history,
          type: :boolean,
          required: false,
          location: :query,
          description: "Include recent health history"
        }
      ],
      responses: %{
        200 => %{description: "Cluster health information"}
      }
    }
  end

  def validate_params(params) do
    validated_params =
      params
      |> convert_boolean_param("include_metrics", true)
      |> convert_boolean_param("include_history", false)

    {:ok, validated_params}
  end

  def execute(_params) do
    # TODO: Replace with actual distributed cluster implementation
    {:error, :cluster_not_available}
  end

  def format_response(health_data) do
    %{
      data: health_data,
      timestamp: DateTime.utc_now(),
      success: true
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
