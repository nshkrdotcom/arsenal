defmodule Arsenal.Operations.ListProcesses do
  @moduledoc """
  Example operation that lists all processes in the system.

  This demonstrates a simple GET operation without parameters.
  """

  use Arsenal.Operation

  @impl true
  def name(), do: :list_processes_v1

  @impl true
  def category(), do: :process

  @impl true
  def description(), do: "List all processes in the system"

  @impl true
  def params_schema() do
    %{
      limit: [type: :integer, default: 100, min: 1, max: 1000],
      sort_by: [type: :atom, default: :memory, in: [:memory, :reductions, :message_queue_len]]
    }
  end

  @impl true
  def metadata(), do: %{}

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
  def execute(%{limit: limit, sort_by: sort_by}) do
    # PERFORMANCE: Process the list of PIDs concurrently to reduce execution time
    processes =
      Process.list()
      |> Task.async_stream(&get_process_info/1, 
           max_concurrency: System.schedulers_online() * 2, 
           ordered: false,
           timeout: 1000)
      |> Enum.flat_map(fn
        {:ok, nil} -> []
        {:ok, info} -> [info]
        {:exit, _reason} -> [] # Handle timeouts/crashes gracefully
      end)
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
