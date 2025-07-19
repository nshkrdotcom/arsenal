defmodule Arsenal.Operations.Distributed.ProcessList do
  @moduledoc """
  Arsenal operation to list all processes across the cluster with node information.

  This operation provides comprehensive process listing across all cluster nodes,
  with filtering capabilities and detailed process information.
  """

  use Arsenal.Operation, compat: true

  def rest_config do
    %{
      method: :get,
      path: "/api/v1/cluster/processes",
      summary: "List all processes across the cluster with node information",
      parameters: [
        %{
          name: :node,
          type: :string,
          required: false,
          location: :query,
          description: "Filter processes by specific node"
        },
        %{
          name: :type,
          type: :string,
          required: false,
          location: :query,
          description: "Filter processes by type (supervisor, gen_server, etc.)"
        },
        %{
          name: :application,
          type: :string,
          required: false,
          location: :query,
          description: "Filter processes by application"
        },
        %{
          name: :limit,
          type: :integer,
          required: false,
          location: :query,
          description: "Maximum number of processes to return (default: 100)"
        },
        %{
          name: :include_details,
          type: :boolean,
          required: false,
          location: :query,
          description: "Include detailed process information"
        }
      ],
      responses: %{
        200 => %{description: "List of processes across the cluster"}
      }
    }
  end

  def validate_params(params) do
    validated_params =
      params
      |> validate_node_param()
      |> validate_type_param()
      |> validate_limit_param()
      |> convert_boolean_param("include_details", false)

    {:ok, validated_params}
  end

  def execute(_params) do
    # TODO: Implement process list functionality when clustering is available
    {:error, :cluster_not_available}
  end

  def format_response(result) do
    %{
      data: result,
      timestamp: DateTime.utc_now(),
      success: true,
      metadata: %{
        operation: "DistributedProcessList",
        nodes_queried: length(result.nodes_queried),
        total_processes: result.total_count
      }
    }
  end

  # Private helper functions

  defp validate_node_param(params) do
    case params["node"] do
      nil ->
        params

      node_str when is_binary(node_str) ->
        # Validate node name format
        if String.contains?(node_str, "@") do
          params
        else
          # Invalid format, ignore
          Map.delete(params, "node")
        end

      _ ->
        Map.delete(params, "node")
    end
  end

  defp validate_type_param(params) do
    case params["type"] do
      nil -> params
      type when type in ["supervisor", "gen_server", "gen_event", "task", "process"] -> params
      # Invalid type, ignore
      _ -> Map.delete(params, "type")
    end
  end

  defp validate_limit_param(params) do
    # Get configuration values
    process_config = Application.get_env(:otp_supervisor, :process_listing, [])
    default_limit = Keyword.get(process_config, :default_limit, 1000)
    max_limit = Keyword.get(process_config, :max_limit, 10000)

    case params["limit"] do
      # Default limit
      nil ->
        Map.put(params, "limit", default_limit)

      limit_str when is_binary(limit_str) ->
        case Integer.parse(limit_str) do
          {limit, ""} when limit > 0 and limit <= max_limit ->
            Map.put(params, "limit", limit)

          _ ->
            # Invalid, use default
            Map.put(params, "limit", default_limit)
        end

      limit when is_integer(limit) and limit > 0 and limit <= max_limit ->
        Map.put(params, "limit", limit)

      _ ->
        # Invalid, use default
        Map.put(params, "limit", default_limit)
    end
  end

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
