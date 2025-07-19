defmodule Arsenal.Control do
  @moduledoc """
  Arsenal.Control provides comprehensive process management and supervisor introspection capabilities.

  This module offers enhanced process control operations including supervisor tree analysis,
  process lifecycle management, and safety mechanisms to protect critical system processes.
  """

  require Logger

  # Critical system processes that should be protected from modification
  @protected_processes [
    :kernel_sup,
    :application_controller,
    :code_server,
    :init,
    :error_logger,
    :global_name_server,
    :rex,
    :user,
    :standard_error,
    :standard_error_sup,
    :file_server_2,
    :inet_db,
    :erl_prim_loader
  ]

  @type supervisor_tree :: %{
          pid: pid(),
          name: atom() | nil,
          strategy: atom(),
          children: [supervisor_tree() | process_info()],
          restart_intensity: non_neg_integer(),
          max_restart_period: non_neg_integer()
        }

  @type process_info :: %{
          pid: pid(),
          name: atom() | nil,
          status: atom(),
          memory: non_neg_integer(),
          message_queue_len: non_neg_integer(),
          links: [pid()],
          monitors: [pid()],
          monitored_by: [pid()],
          trap_exit: boolean(),
          priority: atom(),
          reductions: non_neg_integer(),
          current_function: {module(), atom(), arity()},
          initial_call: {module(), atom(), arity()},
          registered_name: atom() | nil,
          application: atom() | nil,
          supervisor: pid() | nil,
          restart_count: non_neg_integer(),
          last_restart: DateTime.t() | nil
        }

  @doc """
  Traverses and analyzes a supervision hierarchy starting from the given supervisor.

  Returns a comprehensive tree structure with supervisor information and all children.

  ## Examples

      iex> kernel_sup_pid = Process.whereis(:kernel_sup)
      iex> {:ok, tree} = Arsenal.Control.get_supervisor_tree(kernel_sup_pid)
      iex> is_map(tree)
      true
      iex> Map.has_key?(tree, :children)
      true
  """
  @spec get_supervisor_tree(pid() | atom()) :: {:ok, supervisor_tree()} | {:error, term()}
  def get_supervisor_tree(supervisor) when is_atom(supervisor) do
    case Process.whereis(supervisor) do
      nil -> {:error, {:supervisor_not_found, supervisor}}
      pid -> get_supervisor_tree(pid)
    end
  end

  def get_supervisor_tree(supervisor) when is_pid(supervisor) do
    if Process.alive?(supervisor) do
      case is_supervisor?(supervisor) do
        true -> build_supervisor_tree(supervisor)
        false -> {:error, {:not_a_supervisor, supervisor}}
      end
    else
      {:error, {:process_not_alive, supervisor}}
    end
  end

  @doc """
  Gets enhanced process information beyond basic Process.info/1.

  Includes additional metadata like application ownership, supervisor relationships,
  restart history, and performance metrics.

  ## Examples

      iex> {:ok, info} = Arsenal.Control.get_process_info(self())
      iex> is_map(info)
      true
      iex> Map.has_key?(info, :application)
      true
  """
  @spec get_process_info(pid()) :: {:ok, process_info()} | {:error, term()}
  def get_process_info(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      case gather_enhanced_process_info(pid) do
        {:ok, info} -> {:ok, info}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:process_not_alive, pid}}
    end
  end

  @doc """
  Restarts a child process under the given supervisor.

  Safely terminates and restarts the specified child, maintaining supervisor state.

  ## Examples

      iex> {:error, {:supervisor_not_found, :non_existent}} = Arsenal.Control.restart_child(:non_existent, :child)
      iex> true
      true
  """
  @spec restart_child(pid() | atom(), term()) :: {:ok, pid()} | {:error, term()}
  def restart_child(supervisor, child_id) when is_atom(supervisor) do
    case Process.whereis(supervisor) do
      nil -> {:error, {:supervisor_not_found, supervisor}}
      pid -> restart_child(pid, child_id)
    end
  end

  def restart_child(supervisor, child_id) when is_pid(supervisor) do
    if Process.alive?(supervisor) and is_supervisor?(supervisor) do
      case Supervisor.restart_child(supervisor, child_id) do
        {:ok, pid} ->
          Logger.info(
            "Successfully restarted child #{inspect(child_id)} under #{inspect(supervisor)}"
          )

          {:ok, pid}

        {:ok, pid, _info} ->
          Logger.info(
            "Successfully restarted child #{inspect(child_id)} under #{inspect(supervisor)}"
          )

          {:ok, pid}

        {:error, :not_found} ->
          {:error, {:child_not_found, child_id}}

        {:error, :running} ->
          {:error, {:child_already_running, child_id}}

        {:error, reason} ->
          {:error, {:restart_failed, reason}}
      end
    else
      {:error, {:invalid_supervisor, supervisor}}
    end
  end

  @doc """
  Safely terminates a process with protection mechanisms for critical system processes.

  Includes safety checks to prevent termination of essential system processes unless
  explicitly forced.

  ## Examples

      iex> {:ok, result} = Arsenal.Control.kill_process(spawn(fn -> :timer.sleep(1000) end), :normal)
      iex> result.terminated
      true
  """
  @spec kill_process(pid(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def kill_process(pid, reason \\ :killed, opts \\ []) when is_pid(pid) do
    force = Keyword.get(opts, :force, false)
    timeout = Keyword.get(opts, :timeout, 5000)

    cond do
      not Process.alive?(pid) ->
        {:error, {:process_not_alive, pid}}

      is_protected_process?(pid) and not force ->
        {:error, {:process_protected, pid}}

      true ->
        perform_safe_termination(pid, reason, timeout)
    end
  end

  @doc """
  Suspends a process, preventing it from being scheduled for execution.

  Note: This uses :erlang.suspend_process/1 which should be used carefully
  as it can cause deadlocks if not properly managed.

  ## Examples

      iex> pid = spawn(fn -> :timer.sleep(10000) end)
      iex> :ok = Arsenal.Control.suspend_process(pid)
      :ok
  """
  @spec suspend_process(pid()) :: :ok | {:error, term()}
  def suspend_process(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      if is_protected_process?(pid) do
        {:error, {:process_protected, pid}}
      else
        try do
          :erlang.suspend_process(pid)
          Logger.info("Suspended process #{inspect(pid)}")
          :ok
        rescue
          error -> {:error, {:suspend_failed, error}}
        end
      end
    else
      {:error, {:process_not_alive, pid}}
    end
  end

  @doc """
  Resumes a previously suspended process.

  ## Examples

      iex> pid = spawn(fn -> :timer.sleep(10000) end)
      iex> :ok = Arsenal.Control.suspend_process(pid)
      iex> :ok = Arsenal.Control.resume_process(pid)
      :ok
  """
  @spec resume_process(pid()) :: :ok | {:error, term()}
  def resume_process(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        :erlang.resume_process(pid)
        Logger.info("Resumed process #{inspect(pid)}")
        :ok
      rescue
        error -> {:error, {:resume_failed, error}}
      end
    else
      {:error, {:process_not_alive, pid}}
    end
  end

  @doc """
  Checks if a process is protected from modification.

  Protected processes include critical system processes that should not be
  terminated or modified during normal operations.
  """
  @spec is_protected_process?(pid()) :: boolean()
  def is_protected_process?(pid) when is_pid(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, name} when name in @protected_processes ->
        true

      _ ->
        is_critical_system_process?(pid)
    end
  end

  # Private helper functions

  defp is_supervisor?(pid) do
    # ROBUSTNESS: Use safe, non-blocking checks for supervisor detection
    # Start with cheapest check - supervisors must trap exits
    case Process.info(pid, :trap_exit) do
      {:trap_exit, true} ->
        # Process traps exits, could be a supervisor
        # Check initial call pattern first for quick wins
        case Process.info(pid, :initial_call) do
          {:initial_call, initial_call} ->
            if looks_like_supervisor?(initial_call) do
              # Definitely looks like a supervisor, confirm with safe check
              get_supervisor_details_safely(pid).is_supervisor
            else
              # Doesn't match supervisor patterns, but could still be one
              # (e.g., kernel_sup has {:proc_lib, :init_p, 5})
              # Use safe task-based check as fallback
              get_supervisor_details_safely(pid).is_supervisor
            end

          _ ->
            # No initial call info, use safe task-based check
            get_supervisor_details_safely(pid).is_supervisor
        end

      _ ->
        # Does not trap exits, cannot be a supervisor
        false
    end
  rescue
    ArgumentError -> false
  end

  # Check if the initial call looks like a supervisor
  defp looks_like_supervisor?({:supervisor, _, _}), do: true
  defp looks_like_supervisor?({Supervisor, :init, 1}), do: true

  defp looks_like_supervisor?({module, _, _}) do
    # Check if module name contains "Supervisor" or "Sup"
    module_string = to_string(module)

    String.contains?(module_string, "Supervisor") or
      String.contains?(module_string, "Sup") or
      String.ends_with?(module_string, ".Supervisor")
  end

  defp looks_like_supervisor?(_), do: false

  defp get_supervisor_details_safely(pid) do
    # This task isolates the potentially blocking call in a separate process
    task =
      Task.async(fn ->
        try do
          # Supervisor.which_children/1 is a reliable check. If it succeeds, it's a supervisor.
          children = Supervisor.which_children(pid)
          %{is_supervisor: true, child_count: length(children)}
        rescue
          _ -> %{is_supervisor: false}
        catch
          :exit, _ -> %{is_supervisor: false}
        end
      end)

    # Wait for a short period. A responsive supervisor will reply almost instantly.
    # Non-supervisors will cause a timeout here, which we handle gracefully.
    case Task.yield(task, 200) do
      {:ok, result} ->
        Task.shutdown(task)
        result

      _ ->
        # Task timed out or crashed.
        Task.shutdown(task, :brutal_kill)
        %{is_supervisor: false}
    end
  end

  defp build_supervisor_tree(supervisor_pid) do
    try do
      # Get supervisor information
      supervisor_info = get_supervisor_info(supervisor_pid)

      # Get children and build their trees
      children =
        case Supervisor.which_children(supervisor_pid) do
          children_list when is_list(children_list) ->
            Enum.map(children_list, &build_child_info/1)
        end

      tree = Map.put(supervisor_info, :children, children)
      {:ok, tree}
    rescue
      error -> {:error, {:tree_build_failed, error}}
    end
  end

  defp get_supervisor_info(pid) do
    basic_info = Process.info(pid) |> Enum.into(%{})

    # Get supervisor-specific information
    supervisor_state =
      try do
        case :sys.get_state(pid) do
          %{strategy: strategy, intensity: intensity, period: period} ->
            %{strategy: strategy, restart_intensity: intensity, max_restart_period: period}

          _ ->
            %{strategy: :unknown, restart_intensity: 0, max_restart_period: 0}
        end
      rescue
        _ -> %{strategy: :unknown, restart_intensity: 0, max_restart_period: 0}
      end

    %{
      pid: pid,
      name: Map.get(basic_info, :registered_name),
      strategy: supervisor_state.strategy,
      restart_intensity: supervisor_state.restart_intensity,
      max_restart_period: supervisor_state.max_restart_period,
      memory: Map.get(basic_info, :memory, 0),
      message_queue_len: Map.get(basic_info, :message_queue_len, 0)
    }
  end

  defp build_child_info({id, child_pid, type, _modules}) when is_pid(child_pid) do
    case type do
      :supervisor ->
        case build_supervisor_tree(child_pid) do
          {:ok, tree} -> tree
          {:error, _} -> build_process_info(child_pid, id)
        end

      _ ->
        build_process_info(child_pid, id)
    end
  end

  defp build_child_info({id, :undefined, _type, _modules}) do
    %{id: id, status: :not_started}
  end

  defp build_child_info({id, :restarting, _type, _modules}) do
    %{id: id, status: :restarting}
  end

  defp build_process_info(pid, id) do
    case gather_enhanced_process_info(pid) do
      {:ok, info} -> Map.put(info, :id, id)
      {:error, _} -> %{pid: pid, id: id, status: :error}
    end
  end

  defp gather_enhanced_process_info(pid) do
    try do
      # Get basic process information
      basic_info =
        case Process.info(pid) do
          nil -> {:error, :process_not_found}
          info -> {:ok, Enum.into(info, %{}) |> Map.put(:pid, pid)}
        end

      case basic_info do
        {:ok, info} ->
          # Enhance with additional information
          enhanced_info =
            info
            |> add_application_info(pid)
            |> add_supervisor_info(pid)
            |> add_restart_info(pid)
            |> normalize_process_info()

          {:ok, enhanced_info}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error -> {:error, {:info_gathering_failed, error}}
    end
  end

  defp add_application_info(info, pid) do
    application =
      case :application.get_application(pid) do
        {:ok, app} -> app
        :undefined -> nil
      end

    Map.put(info, :application, application)
  end

  defp add_supervisor_info(info, pid) do
    supervisor = find_supervisor(pid)
    Map.put(info, :supervisor, supervisor)
  end

  defp add_restart_info(info, _pid) do
    # In a real implementation, this would track restart history
    # For now, we'll provide default values
    info
    |> Map.put(:restart_count, 0)
    |> Map.put(:last_restart, nil)
  end

  defp normalize_process_info(info) do
    # Process.info doesn't include the pid in the result, so we need to get it from the original pid
    # The info map should have been enhanced with the pid during gathering
    pid =
      case Map.get(info, :pid) do
        nil ->
          # If pid is not in the map, we need to extract it from somewhere else
          # This shouldn't happen in normal flow, but let's handle it gracefully
          nil

        pid when is_pid(pid) ->
          pid
      end

    %{
      pid: pid,
      name: Map.get(info, :registered_name),
      status: Map.get(info, :status, :running),
      memory: Map.get(info, :memory, 0),
      message_queue_len: Map.get(info, :message_queue_len, 0),
      links: Map.get(info, :links, []),
      monitors: Map.get(info, :monitors, []),
      monitored_by: Map.get(info, :monitored_by, []),
      trap_exit: Map.get(info, :trap_exit, false),
      priority: Map.get(info, :priority, :normal),
      reductions: Map.get(info, :reductions, 0),
      current_function: Map.get(info, :current_function, {nil, nil, 0}),
      initial_call: Map.get(info, :initial_call, {nil, nil, 0}),
      registered_name: Map.get(info, :registered_name),
      application: Map.get(info, :application),
      supervisor: Map.get(info, :supervisor),
      restart_count: Map.get(info, :restart_count, 0),
      last_restart: Map.get(info, :last_restart)
    }
  end

  defp find_supervisor(pid) do
    # Try to find the supervisor by looking at ancestors
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} ->
        case Enum.find(dict, fn {key, _} -> key == :"$ancestors" end) do
          {:"$ancestors", [supervisor | _]} when is_pid(supervisor) -> supervisor
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp is_critical_system_process?(pid) do
    case Process.info(pid, [:registered_name, :initial_call]) do
      [{:registered_name, []}, {:initial_call, {module, _, _}}] ->
        # Check if it's a critical system module
        critical_modules = [:application_master, :kernel, :stdlib, :sasl]

        Enum.any?(critical_modules, fn mod ->
          module_string = Atom.to_string(module)
          mod_string = Atom.to_string(mod)
          String.starts_with?(module_string, mod_string)
        end)

      [{:registered_name, name}, _] when is_atom(name) ->
        name in @protected_processes

      _ ->
        false
    end
  end

  defp perform_safe_termination(pid, reason, timeout) do
    try do
      # Monitor the process to confirm termination
      ref = Process.monitor(pid)

      # Log the termination attempt
      Logger.info(
        "Attempting to terminate process #{inspect(pid)} with reason #{inspect(reason)}"
      )

      # Send the exit signal
      Process.exit(pid, reason)

      # Wait for confirmation of termination
      terminated = wait_for_termination(ref, pid, timeout)

      result = %{
        pid: pid,
        reason: reason,
        terminated: terminated,
        timestamp: DateTime.utc_now()
      }

      if terminated do
        Logger.info("Successfully terminated process #{inspect(pid)}")
      else
        Logger.warning("Process #{inspect(pid)} did not terminate within timeout")
      end

      {:ok, result}
    rescue
      error ->
        Logger.error("Failed to terminate process #{inspect(pid)}: #{inspect(error)}")
        {:error, {:termination_failed, error}}
    end
  end

  defp wait_for_termination(ref, pid, timeout) do
    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} ->
        true
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        not Process.alive?(pid)
    end
  end
end
