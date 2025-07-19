defmodule Arsenal.Operations.Distributed.ClusterSupervisionTrees do
  @moduledoc """
  Arsenal operation to get supervision trees across all cluster nodes.

  This operation provides comprehensive supervision tree information from all nodes
  in the cluster, including supervisor hierarchies, children relationships, and
  metadata for cluster-wide supervision tree analysis and visualization.
  """

  use Arsenal.Operation, compat: true

  def rest_config do
    %{
      method: :get,
      path: "/api/v1/cluster/supervision-trees",
      summary: "Get supervision trees across all cluster nodes",
      description:
        "Retrieves supervision tree hierarchies from all nodes in the cluster with detailed supervisor and children information",
      parameters: [
        %{
          name: :include_children,
          type: :boolean,
          required: false,
          default: true,
          description: "Include detailed children information for each supervisor",
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
          name: :include_process_details,
          type: :boolean,
          required: false,
          default: false,
          description: "Include detailed process information for children",
          location: :query
        },
        %{
          name: :max_depth,
          type: :integer,
          required: false,
          description: "Maximum tree depth to traverse (default: no limit)",
          location: :query
        }
      ],
      responses: %{
        200 => %{
          description: "Supervision trees retrieved successfully",
          schema: %{
            type: :object,
            properties: %{
              supervision_trees: %{
                type: :object,
                description: "Supervision trees grouped by node"
              },
              summary: %{
                type: :object,
                properties: %{
                  nodes_queried: %{type: :array, items: %{type: :string}},
                  total_supervisors: %{type: :integer},
                  total_nodes: %{type: :integer},
                  errors: %{type: :array}
                }
              },
              metadata: %{
                type: :object,
                properties: %{
                  timestamp: %{type: :string, format: "date-time"},
                  cluster_health: %{type: :string},
                  operation_duration_ms: %{type: :integer}
                }
              }
            }
          }
        },
        500 => %{description: "Failed to retrieve supervision trees"}
      }
    }
  end

  def validate_params(params) do
    validated_params =
      params
      |> convert_boolean_param("include_children", true)
      |> convert_boolean_param("include_process_details", false)
      |> validate_max_depth()

    {:ok, validated_params}
  end

  def execute(_params) do
    # TODO: Implement cluster supervision trees functionality when clustering is available
    {:error, :cluster_not_available}
  end

  # Private helper functions

  defp convert_boolean_param(params, key, default_value) do
    case Map.get(params, key) do
      nil -> Map.put(params, key, default_value)
      "true" -> Map.put(params, key, true)
      "false" -> Map.put(params, key, false)
      value when is_boolean(value) -> params
      _ -> Map.put(params, key, default_value)
    end
  end

  defp validate_max_depth(params) do
    case Map.get(params, "max_depth") do
      nil ->
        params

      value when is_binary(value) ->
        case Integer.parse(value) do
          {depth, ""} when depth > 0 -> Map.put(params, "max_depth", depth)
          _ -> Map.delete(params, "max_depth")
        end

      value when is_integer(value) and value > 0 ->
        params

      _ ->
        Map.delete(params, "max_depth")
    end
  end
end
