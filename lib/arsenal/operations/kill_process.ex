defmodule Arsenal.Operations.KillProcess do
  @moduledoc """
  Terminates a process with a specified reason.

  This operation allows killing processes by PID or registered name with
  various exit reasons. It provides detailed information about the termination
  including whether the process was successfully killed and its final state.
  """

  use Arsenal.Operation

  @impl true
  def name(), do: :kill_process

  @impl true
  def category(), do: :process

  @impl true
  def description(), do: "Terminate a process with specified reason"

  @impl true
  def params_schema() do
    %{
      pid: [type: :pid, required: false],
      name: [type: :atom, required: false],
      reason: [type: :atom, default: :killed],
      timeout: [type: :integer, default: 5000, min: 0, max: 60000]
    }
  end

  @impl true
  def metadata() do
    %{
      requires_authentication: true,
      minimum_role: :operator,
      idempotent: true,
      timeout: 10_000
    }
  end

  @impl true
  def rest_config() do
    %{
      method: :delete,
      path: "/api/v1/processes/:pid",
      summary: "Terminate a process",
      parameters: params_schema(),
      responses: %{
        200 => %{description: "Process terminated successfully"},
        404 => %{description: "Process not found"},
        400 => %{description: "Invalid parameters"}
      }
    }
  end

  @impl true
  def validate_params(params) do
    # Ensure we have either pid or name, but not both
    case {Map.has_key?(params, :pid), Map.has_key?(params, :name)} do
      {false, false} ->
        {:error, %{params: "Either 'pid' or 'name' must be provided"}}

      {true, true} ->
        {:error, %{params: "Cannot specify both 'pid' and 'name'"}}

      _ ->
        super(params)
    end
  end

  @impl true
  def execute(params) do
    with {:ok, pid} <- resolve_pid(params),
         {:ok, initial_info} <- get_process_info(pid),
         :ok <- kill_process(pid, params.reason),
         {:ok, terminated} <- verify_termination(pid, params.timeout) do
      {:ok,
       %{
         pid: pid,
         terminated: terminated,
         reason: params.reason,
         initial_info: initial_info,
         execution_time: DateTime.utc_now()
       }}
    end
  end

  # Private helpers

  defp resolve_pid(%{pid: pid}), do: {:ok, pid}

  defp resolve_pid(%{name: name}) do
    case Process.whereis(name) do
      nil -> {:error, "Process with name #{inspect(name)} not found"}
      pid -> {:ok, pid}
    end
  end

  defp get_process_info(pid) do
    case Process.info(pid) do
      nil ->
        {:error, "Process #{inspect(pid)} not found"}

      info ->
        {:ok,
         %{
           registered_name: Keyword.get(info, :registered_name),
           initial_call: format_mfa(Keyword.get(info, :initial_call)),
           memory: Keyword.get(info, :memory),
           message_queue_len: Keyword.get(info, :message_queue_len),
           status: Keyword.get(info, :status),
           reductions: Keyword.get(info, :reductions)
         }}
    end
  end

  defp kill_process(pid, reason) do
    try do
      # Special handling for :kill reason - use Process.exit
      if reason == :kill do
        Process.exit(pid, :kill)
      else
        # For other reasons, try to send exit signal
        Process.exit(pid, reason)
      end

      :ok
    rescue
      ArgumentError ->
        # Process might already be dead
        :ok
    end
  end

  defp verify_termination(pid, timeout) do
    # Monitor the process to ensure it's terminated
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:ok,
         %{
           confirmed: true,
           exit_reason: reason,
           terminated_at: DateTime.utc_now()
         }}
    after
      timeout ->
        Process.demonitor(ref, [:flush])

        # Check if process still exists
        case Process.info(pid) do
          nil ->
            {:ok,
             %{
               confirmed: true,
               exit_reason: :unknown,
               terminated_at: DateTime.utc_now()
             }}

          _info ->
            {:error, "Process failed to terminate within #{timeout}ms"}
        end
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
      data: %{
        pid: inspect(result.pid),
        terminated: result.terminated,
        reason: result.reason,
        initial_info: result.initial_info,
        execution_time: DateTime.to_iso8601(result.execution_time)
      }
    }
  end

  @impl true
  def format_response({:error, reason}) do
    %{
      success: false,
      error: %{
        message: to_string(reason),
        class: if(reason =~ "not found", do: :not_found, else: :execution)
      }
    }
  end
end
