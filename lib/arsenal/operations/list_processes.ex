defmodule Arsenal.Operations.ListProcesses do
  @moduledoc """
  Example operation that lists all processes in the system.

  This demonstrates a simple GET operation without parameters.
  """

  use Arsenal.Operation

  @impl true
  def rest_config do
    %{
      method: :get,
      path: "/api/v1/processes",
      summary: "List all processes in the system",
      parameters: [
        %{
          name: :limit,
          type: :integer,
          location: :query,
          required: false,
          description: "Maximum number of processes to return (default: 100)"
        },
        %{
          name: :sort_by,
          type: :string,
          location: :query,
          required: false,
          description: "Sort processes by: memory, reductions, message_queue (default: memory)"
        }
      ],
      responses: %{
        200 => %{
          description: "List of processes retrieved successfully",
          schema: %{
            type: :object,
            properties: %{
              processes: %{
                type: :array,
                items: %{
                  type: :object,
                  properties: %{
                    pid: %{type: :string},
                    memory: %{type: :integer},
                    reductions: %{type: :integer},
                    message_queue_len: %{type: :integer}
                  }
                }
              },
              total: %{type: :integer},
              limit: %{type: :integer}
            }
          }
        }
      }
    }
  end

  @impl true
  def validate_params(params) do
    limit = get_integer_param(params, "limit", 100)
    sort_by = get_sort_by(params)

    {:ok, %{limit: limit, sort_by: sort_by}}
  end

  @impl true
  def execute(%{limit: limit, sort_by: sort_by}) do
    processes =
      Process.list()
      |> Enum.map(&get_process_info/1)
      |> Enum.filter(&(&1 != nil))
      |> sort_processes(sort_by)
      |> Enum.take(limit)

    {:ok, %{processes: processes, total: length(Process.list()), limit: limit}}
  end

  @impl true
  def format_response({:ok, data}) do
    %{
      status: "success",
      data: %{
        processes: Enum.map(data.processes, &format_process/1),
        total: data.total,
        limit: data.limit,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  # Private helpers

  defp get_integer_param(params, key, default) do
    case Map.get(params, key) do
      nil ->
        default

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> default
        end

      value when is_integer(value) ->
        value

      _ ->
        default
    end
  end

  defp get_sort_by(params) do
    case Map.get(params, "sort_by") do
      "memory" -> :memory
      "reductions" -> :reductions
      "message_queue" -> :message_queue_len
      _ -> :memory
    end
  end

  defp get_process_info(pid) do
    try do
      case Process.info(pid, [:memory, :reductions, :message_queue_len]) do
        nil ->
          nil

        info ->
          %{
            pid: pid,
            memory: Keyword.get(info, :memory),
            reductions: Keyword.get(info, :reductions),
            message_queue_len: Keyword.get(info, :message_queue_len)
          }
      end
    catch
      _, _ -> nil
    end
  end

  defp sort_processes(processes, sort_by) do
    Enum.sort_by(processes, &Map.get(&1, sort_by), :desc)
  end

  defp format_process(process) do
    %{
      pid: inspect(process.pid),
      memory: process.memory,
      reductions: process.reductions,
      message_queue_len: process.message_queue_len,
      memory_mb: Float.round(process.memory / 1_048_576, 2)
    }
  end
end
