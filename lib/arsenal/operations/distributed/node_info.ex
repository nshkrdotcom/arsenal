defmodule Arsenal.Operations.Distributed.NodeInfo do
  @moduledoc """
  Arsenal operation for detailed node inspection and information.

  This operation provides comprehensive information about a specific node
  including processes, resource usage, and health metrics.
  """

  use Arsenal.Operation, compat: true

  def rest_config do
    %{
      method: :get,
      path: "/api/v1/cluster/nodes/:node/info",
      summary: "Get detailed information about a specific cluster node",
      parameters: [
        %{
          name: :node,
          type: :string,
          required: true,
          location: :path,
          description: "Node name to inspect"
        },
        %{
          name: :include_processes,
          type: :boolean,
          required: false,
          location: :query,
          description: "Include detailed process information"
        },
        %{
          name: :process_limit,
          type: :integer,
          required: false,
          location: :query,
          description: "Maximum number of processes to return (default: 50)"
        }
      ],
      responses: %{
        200 => %{description: "Detailed node information"},
        404 => %{description: "Node not found"}
      }
    }
  end

  def validate_params(params) do
    # Validate node parameter
    case params["node"] do
      nil ->
        {:error, {:missing_parameter, :node}}

      node_str when is_binary(node_str) ->
        if String.contains?(node_str, "@") do
          try do
            node_atom = String.to_atom(node_str)

            validated_params =
              params
              |> Map.put("node", node_atom)
              |> convert_boolean_param("include_processes", false)
              |> validate_process_limit()

            {:ok, validated_params}
          rescue
            _ -> {:error, {:invalid_parameter, :node, "Invalid node name format"}}
          end
        else
          {:error,
           {:invalid_parameter, :node, "Node name must include hostname (e.g., node@host)"}}
        end

      _ ->
        {:error, {:invalid_parameter, :node, "Node name must be a string"}}
    end
  end

  def execute(_params) do
    # TODO: Implement node info functionality when clustering is available
    {:error, :cluster_not_available}
  end

  def format_response(node_info) do
    %{
      data: node_info,
      timestamp: DateTime.utc_now(),
      success: true,
      metadata: %{
        operation: "NodeInfo",
        node: node_info.name,
        status: node_info.status
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

  defp validate_process_limit(params) do
    case params["process_limit"] do
      nil ->
        Map.put(params, "process_limit", 50)

      limit_str when is_binary(limit_str) ->
        case Integer.parse(limit_str) do
          {limit, ""} when limit > 0 and limit <= 500 ->
            Map.put(params, "process_limit", limit)

          _ ->
            Map.put(params, "process_limit", 50)
        end

      limit when is_integer(limit) and limit > 0 and limit <= 500 ->
        Map.put(params, "process_limit", limit)

      _ ->
        Map.put(params, "process_limit", 50)
    end
  end
end
