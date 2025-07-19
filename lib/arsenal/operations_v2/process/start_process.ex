defmodule Arsenal.OperationsV2.Process.StartProcess do
  @moduledoc """
  Starts a new process with configurable options.

  This operation allows starting processes with various configurations including:
  - Named or anonymous processes
  - Linked or monitored processes
  - Custom spawn options
  - Initial function and arguments
  """

  use Arsenal.Operation

  @impl true
  def name(), do: :start_process

  @impl true
  def category(), do: :process

  @impl true
  def description(), do: "Start a new process with configurable options"

  @impl true
  def params_schema() do
    %{
      module: [type: :atom, required: true],
      function: [type: :atom, required: true],
      args: [type: :list, default: []],
      options: [type: :map, default: %{}],
      name: [type: :atom, required: false],
      link: [type: :boolean, default: false],
      monitor: [type: :boolean, default: false]
    }
  end

  @impl true
  def metadata() do
    %{
      requires_authentication: true,
      minimum_role: :operator,
      idempotent: false,
      timeout: 5_000
    }
  end

  @impl true
  def rest_config() do
    %{
      method: :post,
      path: "/api/v1/processes",
      summary: "Start a new process",
      parameters: params_schema(),
      responses: %{
        201 => %{description: "Process started successfully"},
        400 => %{description: "Invalid parameters"},
        409 => %{description: "Process with given name already exists"},
        500 => %{description: "Failed to start process"}
      }
    }
  end

  @impl true
  def execute(params) do
    module = params.module
    function = params.function
    args = Map.get(params, :args, [])
    link = Map.get(params, :link, false)
    monitor = Map.get(params, :monitor, false)

    # Validate module and function exist
    with :ok <- validate_mfa(module, function, length(args)),
         {:ok, pid} <- spawn_process(module, function, args, link, monitor),
         :ok <- maybe_register_process(pid, Map.get(params, :name)),
         info <- get_process_summary(pid) do
      result = %{
        pid: pid,
        info: info,
        linked: link,
        monitored: monitor
      }

      result =
        if Map.has_key?(params, :name) do
          Map.put(result, :registered_name, params.name)
        else
          result
        end

      {:ok, result}
    end
  end

  # Private helpers

  defp validate_mfa(module, function, arity) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, "Module #{inspect(module)} is not loaded"}

      not function_exported?(module, function, arity) ->
        {:error, "Function #{module}.#{function}/#{arity} is not exported"}

      true ->
        :ok
    end
  end

  defp spawn_process(module, function, args, link, monitor) do
    try do
      pid =
        case {link, monitor} do
          {true, true} ->
            pid = spawn_link(module, function, args)
            Process.monitor(pid)
            pid

          {true, false} ->
            spawn_link(module, function, args)

          {false, true} ->
            pid = spawn(module, function, args)
            Process.monitor(pid)
            pid

          {false, false} ->
            spawn(module, function, args)
        end

      {:ok, pid}
    rescue
      error ->
        {:error, "Failed to spawn process: #{inspect(error)}"}
    end
  end

  defp maybe_register_process(_pid, nil), do: :ok

  defp maybe_register_process(pid, name) do
    try do
      Process.register(pid, name)
      :ok
    rescue
      ArgumentError ->
        # Kill the process if we can't register it
        Process.exit(pid, :kill)
        {:error, "Name #{inspect(name)} is already registered"}
    end
  end

  defp get_process_summary(pid) do
    case Process.info(pid, [:registered_name, :initial_call, :status, :message_queue_len]) do
      nil ->
        %{status: :dead}

      info ->
        %{
          registered_name: Keyword.get(info, :registered_name),
          initial_call: format_mfa(Keyword.get(info, :initial_call)),
          status: Keyword.get(info, :status),
          message_queue_len: Keyword.get(info, :message_queue_len)
        }
    end
  end

  defp format_mfa({module, function, arity}) do
    "#{inspect(module)}.#{function}/#{arity}"
  end

  defp format_mfa(other), do: inspect(other)

  @impl true
  def format_response({:ok, result}) do
    %{
      success: true,
      data:
        %{
          pid: inspect(result.pid),
          linked: result.linked,
          monitored: result.monitored,
          info: result.info
        }
        |> maybe_add_name(result)
    }
  end

  def format_response({:error, reason}) do
    %{
      success: false,
      error: %{
        message: to_string(reason),
        class: :execution
      }
    }
  end

  defp maybe_add_name(data, result) do
    if Map.has_key?(result, :registered_name) do
      Map.put(data, :registered_name, result.registered_name)
    else
      data
    end
  end
end
