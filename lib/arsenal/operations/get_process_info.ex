defmodule Arsenal.Operations.GetProcessInfo do
  @moduledoc """
  Operation to get comprehensive process information.
  """

  use Arsenal.Operation

  @impl true
  def name(), do: :get_process_info

  @impl true
  def category(), do: :process

  @impl true
  def description() do
    "Get comprehensive information about a specific process"
  end

  @impl true
  def params_schema() do
    %{
      pid: [type: :pid, required: true],
      keys: [type: :list, default: :all]
    }
  end

  @impl true
  def rest_config do
    %{
      method: :get,
      path: "/api/v1/processes/:pid/info",
      summary: "Get comprehensive process information",
      parameters: [
        %{
          name: :pid,
          type: :string,
          required: true,
          description: "Process ID in string format",
          location: :path
        },
        %{
          name: :keys,
          type: :array,
          required: false,
          description: "Specific info keys to retrieve",
          location: :query
        }
      ],
      responses: %{
        200 => %{
          description: "Process information retrieved successfully",
          schema: %{
            type: :object,
            properties: %{
              data: %{
                type: :object,
                properties: %{
                  pid: %{type: :string},
                  memory: %{type: :integer},
                  message_queue_len: %{type: :integer},
                  links: %{type: :array},
                  monitors: %{type: :array},
                  status: %{type: :string}
                }
              }
            }
          }
        },
        404 => %{description: "Process not found"},
        400 => %{description: "Invalid PID format"}
      }
    }
  end

  @impl true
  def validate_params(%{pid: pid} = params) when is_pid(pid) do
    # Validate keys if provided
    case Map.get(params, :keys) do
      nil ->
        {:ok, Map.put(params, :keys, :all)}

      :all ->
        {:ok, params}

      keys when is_list(keys) ->
        case validate_process_info_keys(keys) do
          {:ok, atom_keys} -> {:ok, Map.put(params, :keys, atom_keys)}
          {:error, reason} -> {:error, %{keys: reason}}
        end

      _ ->
        {:error, %{keys: "must be a list of atoms or :all"}}
    end
  end

  @impl true
  def validate_params(%{"pid" => pid_string} = params) when is_binary(pid_string) do
    case parse_pid(pid_string) do
      {:ok, pid} ->
        validated_params = Map.put(params, "pid", pid)

        # Validate keys if provided
        case Map.get(params, "keys") do
          nil ->
            {:ok, validated_params}

          keys when is_list(keys) ->
            case validate_process_info_keys(keys) do
              {:ok, atom_keys} -> {:ok, Map.put(validated_params, "keys", atom_keys)}
              {:error, reason} -> {:error, {:invalid_parameter, :keys, reason}}
            end

          _ ->
            {:error, {:invalid_parameter, :keys, "must be an array"}}
        end

      {:error, reason} ->
        {:error, {:invalid_parameter, :pid, reason}}
    end
  rescue
    ArgumentError -> {:error, {:invalid_parameter, :keys, "invalid key name"}}
  end

  @impl true
  def validate_params(_params) do
    {:error, {:missing_parameter, :pid}}
  end

  @impl true
  def execute(%{pid: pid} = params) when is_pid(pid) do
    if Process.alive?(pid) do
      execute_with_pid(pid, params)
    else
      {:error, {:process_not_alive, pid}}
    end
  end

  @impl true
  def execute(%{"pid" => pid} = params) do
    # Handle case where validation might have failed to convert string to PID
    case ensure_pid(pid) do
      {:ok, actual_pid} ->
        if Process.alive?(actual_pid) do
          execute_with_pid(actual_pid, params)
        else
          {:error, {:process_not_alive, actual_pid}}
        end

      {:error, reason} ->
        {:error, {:invalid_parameter, :pid, reason}}
    end
  end

  defp ensure_pid(pid) when is_pid(pid), do: {:ok, pid}
  defp ensure_pid(pid_string) when is_binary(pid_string), do: parse_pid(pid_string)

  defp execute_with_pid(pid, params) do
    keys = Map.get(params, :keys, :all)

    case get_process_information(pid, keys) do
      {:ok, info} ->
        # Include the PID in the response
        info_with_pid = Map.put(info, :pid, pid)
        {:ok, info_with_pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def format_response({:ok, info}) do
    %{
      success: true,
      data: format_process_info(info)
    }
  end

  @impl true
  def format_response({:error, reason}) do
    %{
      success: false,
      error: reason
    }
  end

  @impl true
  def format_response(info) when is_map(info) do
    %{
      data: format_process_info(info)
    }
  end

  defp parse_pid(pid_string) when is_binary(pid_string) do
    try do
      # Handle both "<0.123.0>" and "0.123.0" formats
      cleaned = String.trim(pid_string, "<>")
      pid = :erlang.list_to_pid(~c"<#{cleaned}>")
      {:ok, pid}
    rescue
      _ -> {:error, "invalid PID format"}
    end
  end

  # List of valid process info keys
  @valid_process_info_keys [
    :status,
    :message_queue_len,
    :links,
    :monitors,
    :monitored_by,
    :trap_exit,
    :priority,
    :reductions,
    :binary,
    :memory,
    :garbage_collection,
    :group_leader,
    :total_heap_size,
    :heap_size,
    :stack_size,
    :current_function,
    :current_location,
    :current_stacktrace,
    :initial_call,
    :dictionary,
    :error_handler,
    :suspending,
    :min_heap_size,
    :min_bin_vheap_size,
    :max_heap_size,
    :registered_name
  ]

  defp validate_process_info_keys(keys) do
    try do
      atom_keys =
        Enum.map(keys, fn
          key when is_binary(key) -> String.to_existing_atom(key)
          key when is_atom(key) -> key
          _ -> throw({:invalid_key_type})
        end)

      # Check if all keys are valid process info keys
      invalid_keys = Enum.reject(atom_keys, &(&1 in @valid_process_info_keys))

      case invalid_keys do
        [] -> {:ok, atom_keys}
        [key | _] -> {:error, "invalid process info key: #{key}"}
      end
    rescue
      ArgumentError -> {:error, "invalid key name"}
    catch
      {:invalid_key_type} -> {:error, "keys must be strings or atoms"}
    end
  end

  defp get_process_information(pid, :all) do
    # Get all info plus memory specifically
    case Process.info(pid) do
      nil ->
        {:error, :process_not_found}

      info ->
        # Convert keyword list to map
        info_map = Enum.into(info, %{})

        # Ensure memory is included (it's not in the default Process.info/1)
        info_with_memory =
          case Process.info(pid, :memory) do
            {:memory, memory} -> Map.put(info_map, :memory, memory)
            _ -> info_map
          end

        {:ok, info_with_memory}
    end
  end

  defp get_process_information(pid, keys) when is_list(keys) do
    try do
      info =
        keys
        |> Enum.map(fn key ->
          case Process.info(pid, key) do
            {^key, value} -> {key, value}
            nil -> {key, nil}
          end
        end)
        |> Enum.into(%{})

      {:ok, info}
    rescue
      _ -> {:error, :invalid_info_keys}
    end
  end

  defp format_process_info(info) do
    info
    |> Enum.map(fn {key, value} -> {key, format_info_value(value)} end)
    |> Enum.into(%{})
  end

  defp format_info_value(pid) when is_pid(pid), do: inspect(pid)

  defp format_info_value(list) when is_list(list) do
    Enum.map(list, &format_info_value/1)
  end

  defp format_info_value(value), do: value
end
