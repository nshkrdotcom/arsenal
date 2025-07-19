defmodule Arsenal.Operations.RestartProcess do
  @moduledoc """
  Restarts a process by terminating it and letting its supervisor restart it.
  Only works for processes that are supervised.
  """

  use Arsenal.Operation

  @impl true
  def name(), do: :restart_process

  @impl true
  def category(), do: :process

  @impl true
  def description() do
    "Restart a supervised process by terminating it and letting its supervisor restart it"
  end

  @impl true
  def params_schema() do
    %{
      pid: [type: :pid, required: true],
      reason: [type: :atom, default: :restart],
      timeout: [type: :integer, default: 5000, min: 0, max: 60000]
    }
  end

  @impl true
  def execute(params) do
    pid = params.pid
    reason = params.reason
    timeout = params.timeout

    with {:alive, true} <- {:alive, Process.alive?(pid)},
         {:supervised, supervisor} when not is_nil(supervisor) <-
           {:supervised, find_supervisor(pid)},
         :ok <- terminate_process(pid, reason),
         new_pid when not is_nil(new_pid) <- wait_for_restart(supervisor, pid, timeout) do
      {:ok,
       %{
         old_pid: pid,
         new_pid: new_pid,
         supervisor: supervisor,
         restart_time: DateTime.utc_now()
       }}
    else
      {:alive, false} ->
        {:error, :process_not_alive}

      {:supervised, nil} ->
        {:error, :process_not_supervised}

      {:supervised, _} ->
        {:error, :process_not_supervised}

      {:error, :invalid_pid} ->
        {:error, :invalid_pid}

      nil ->
        {:error, :restart_timeout}

      error ->
        {:error, error}
    end
  end

  @impl true
  def metadata() do
    %{
      requires_authentication: true,
      minimum_role: :operator,
      idempotent: false,
      dangerous: true
    }
  end

  defp find_supervisor(pid) do
    # First check if process has a $ancestors key in its dictionary
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} ->
        case Keyword.get(dict, :"$ancestors") do
          [supervisor | _] when is_pid(supervisor) or is_atom(supervisor) ->
            supervisor

          _ ->
            # Try to find supervisor through links
            find_supervisor_through_links(pid)
        end

      _ ->
        nil
    end
  end

  defp find_supervisor_through_links(pid) do
    case Process.info(pid, :links) do
      {:links, links} ->
        # Try to find a supervisor among the linked processes
        Enum.find(links, fn linked_pid ->
          case Process.info(linked_pid, :dictionary) do
            {:dictionary, dict} ->
              # Check if it's a supervisor by looking for supervisor-specific keys
              Keyword.has_key?(dict, :"$initial_call") and
                case Keyword.get(dict, :"$initial_call") do
                  {:supervisor, _, _} -> true
                  _ -> false
                end

            _ ->
              false
          end
        end)

      _ ->
        nil
    end
  end

  defp terminate_process(pid, reason) do
    Process.exit(pid, reason)
    :ok
  rescue
    ArgumentError -> {:error, :invalid_pid}
  end

  defp wait_for_restart(supervisor, old_pid, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_for_restart_loop(supervisor, old_pid, deadline)
  end

  defp wait_for_restart_loop(supervisor, old_pid, deadline) do
    now = System.monotonic_time(:millisecond)

    if now > deadline do
      nil
    else
      # Get children of supervisor
      case get_supervisor_children(supervisor) do
        {:ok, children} ->
          # Look for a new process that replaced the old one
          new_pid = find_restarted_process(children, old_pid)

          if new_pid do
            new_pid
          else
            Process.sleep(100)
            wait_for_restart_loop(supervisor, old_pid, deadline)
          end

        {:error, _} ->
          nil
      end
    end
  end

  defp get_supervisor_children(supervisor) when is_pid(supervisor) do
    try do
      children = Supervisor.which_children(supervisor)
      {:ok, children}
    rescue
      _ -> {:error, :not_supervisor}
    end
  end

  defp get_supervisor_children(supervisor) when is_atom(supervisor) do
    case Process.whereis(supervisor) do
      nil -> {:error, :supervisor_not_found}
      pid -> get_supervisor_children(pid)
    end
  end

  defp find_restarted_process(children, old_pid) do
    # Look for a child process that's different from the old PID
    # This is a simplified approach - in reality, we'd need to match by child spec ID
    Enum.find_value(children, fn
      {_id, pid, _type, _modules} when is_pid(pid) and pid != old_pid ->
        pid

      _ ->
        nil
    end)
  end
end
