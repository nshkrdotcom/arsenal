defmodule Examples.ProcessManagement.ProcessController do
  @moduledoc """
  High-level process management and control system.
  
  This module demonstrates:
  - Safe process lifecycle management
  - Batch process operations
  - Process health monitoring and recovery
  - Automated process management policies
  - Process resource limiting and throttling
  """
  
  use GenServer
  require Logger
  
  defmodule ProcessPolicy do
    @moduledoc "Policy structure for automated process management"
    
    defstruct [
      :name,
      :conditions,
      :actions,
      :cooldown_seconds,
      :max_actions_per_hour,
      :enabled
    ]
  end
  
  @doc """
  Start the process controller.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Start multiple processes with validation and monitoring.
  """
  def start_processes(process_specs) do
    GenServer.call(__MODULE__, {:start_processes, process_specs})
  end
  
  @doc """
  Gracefully stop multiple processes.
  """
  def stop_processes(pids, timeout \\ 5000) do
    GenServer.call(__MODULE__, {:stop_processes, pids, timeout})
  end
  
  @doc """
  Restart processes that match certain criteria.
  """
  def restart_matching_processes(criteria) do
    GenServer.call(__MODULE__, {:restart_matching_processes, criteria})
  end
  
  @doc """
  Kill processes that are consuming too many resources.
  """
  def kill_resource_hogs(thresholds \\ %{}) do
    GenServer.call(__MODULE__, {:kill_resource_hogs, thresholds})
  end
  
  @doc """
  Set up automated process management policies.
  """
  def configure_policies(policies) do
    GenServer.call(__MODULE__, {:configure_policies, policies})
  end
  
  @doc """
  Get process management statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Perform health check on all managed processes.
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    # Schedule periodic health checks
    schedule_health_check()
    schedule_policy_check()
    
    state = %{
      managed_processes: %{},
      policies: default_policies(),
      stats: initialize_stats(),
      policy_actions: %{},
      last_health_check: nil
    }
    
    Logger.info("ProcessController started")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:start_processes, process_specs}, _from, state) do
    results = Enum.map(process_specs, &start_single_process/1)
    
    successful = Enum.filter(results, &match?({:ok, _}, &1))
    failed = Enum.filter(results, &match?({:error, _}, &1))
    
    # Add successful processes to managed list
    managed_processes = Enum.reduce(successful, state.managed_processes, fn {:ok, {pid, spec}}, acc ->
      Map.put(acc, pid, %{
        spec: spec,
        started_at: DateTime.utc_now(),
        restarts: 0,
        last_health_check: nil
      })
    end)
    
    stats = update_stats(state.stats, :processes_started, length(successful))
    
    Logger.info("Started #{length(successful)} processes, #{length(failed)} failed")
    
    response = %{
      successful: successful,
      failed: failed,
      total_started: length(successful),
      total_failed: length(failed)
    }
    
    {:reply, {:ok, response}, %{state | managed_processes: managed_processes, stats: stats}}
  end
  
  @impl true
  def handle_call({:stop_processes, pids, timeout}, _from, state) do
    results = Enum.map(pids, &stop_single_process(&1, timeout))
    
    successful = Enum.filter(results, &match?(:ok, &1))
    failed = Enum.filter(results, &match?({:error, _}, &1))
    
    # Remove stopped processes from managed list
    managed_processes = Enum.reduce(pids, state.managed_processes, fn pid, acc ->
      Map.delete(acc, pid)
    end)
    
    stats = update_stats(state.stats, :processes_stopped, length(successful))
    
    Logger.info("Stopped #{length(successful)} processes, #{length(failed)} failed")
    
    response = %{
      successful_stops: length(successful),
      failed_stops: length(failed),
      results: results
    }
    
    {:reply, {:ok, response}, %{state | managed_processes: managed_processes, stats: stats}}
  end
  
  @impl true
  def handle_call({:restart_matching_processes, criteria}, _from, state) do
    case Examples.ProcessManagement.ProcessInspector.find_processes(criteria) do
      {:ok, %{matches: matching_processes}} ->
        pids = Enum.map(matching_processes, & &1.pid)
        
        restart_results = Enum.map(pids, &restart_single_process/1)
        successful = Enum.count(restart_results, &match?({:ok, _}, &1))
        
        stats = update_stats(state.stats, :processes_restarted, successful)
        
        Logger.info("Restarted #{successful} processes matching criteria")
        
        {:reply, {:ok, %{restarted: successful, results: restart_results}}, 
         %{state | stats: stats}}
      
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:kill_resource_hogs, thresholds}, _from, state) do
    default_thresholds = %{
      memory_mb: 100,
      queue_length: 10000,
      reductions: 100_000_000
    }
    
    thresholds = Map.merge(default_thresholds, thresholds)
    
    criteria = [
      {:memory_greater_than, thresholds.memory_mb * 1024 * 1024},
      {:queue_length_greater_than, thresholds.queue_length},
      {:reductions_greater_than, thresholds.reductions}
    ]
    
    case Examples.ProcessManagement.ProcessInspector.find_processes(criteria) do
      {:ok, %{matches: resource_hogs}} ->
        kill_results = Enum.map(resource_hogs, fn process ->
          Logger.warn("Killing resource hog process", 
            pid: process.pid,
            memory_mb: div(process.memory, 1024 * 1024),
            queue_length: process.message_queue_length,
            reductions: process.reductions
          )
          
          kill_single_process(process.pid, :kill)
        end)
        
        successful = Enum.count(kill_results, &match?(:ok, &1))
        stats = update_stats(state.stats, :processes_killed, successful)
        
        Logger.info("Killed #{successful} resource hog processes")
        
        {:reply, {:ok, %{killed: successful, thresholds: thresholds}}, 
         %{state | stats: stats}}
      
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:configure_policies, policies}, _from, state) do
    Logger.info("Updated process management policies", policy_count: length(policies))
    {:reply, :ok, %{state | policies: policies}}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    current_stats = %{
      state.stats |
      managed_processes_count: map_size(state.managed_processes),
      active_policies_count: Enum.count(state.policies, & &1.enabled),
      last_health_check: state.last_health_check,
      uptime_seconds: get_uptime_seconds()
    }
    
    {:reply, current_stats, state}
  end
  
  @impl true
  def handle_call(:health_check, _from, state) do
    health_results = perform_health_check(state.managed_processes)
    
    unhealthy_count = Enum.count(health_results, fn {_pid, result} ->
      result.status != :healthy
    end)
    
    Logger.info("Health check completed", 
      total_processes: map_size(state.managed_processes),
      unhealthy_processes: unhealthy_count
    )
    
    {:reply, {:ok, health_results}, 
     %{state | last_health_check: DateTime.utc_now()}}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    health_results = perform_health_check(state.managed_processes)
    
    # Handle unhealthy processes based on policies
    new_state = handle_unhealthy_processes(health_results, state)
    
    schedule_health_check()
    {:noreply, %{new_state | last_health_check: DateTime.utc_now()}}
  end
  
  @impl true
  def handle_info(:policy_check, state) do
    new_state = apply_management_policies(state)
    schedule_policy_check()
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp start_single_process(spec) do
    case validate_process_spec(spec) do
      :ok ->
        case Arsenal.Operations.StartProcess.execute(spec) do
          {:ok, result} ->
            {:ok, {result.pid, spec}}
          
          error ->
            Logger.error("Failed to start process", spec: spec, error: error)
            {:error, {spec, error}}
        end
      
      {:error, reason} ->
        {:error, {spec, reason}}
    end
  end
  
  defp stop_single_process(pid, timeout) do
    case Arsenal.Operations.KillProcess.execute(%{pid: pid, reason: :normal, timeout: timeout}) do
      {:ok, _} -> :ok
      error -> error
    end
  end
  
  defp restart_single_process(pid) do
    # First try to get process info to understand what to restart
    case Arsenal.Operations.GetProcessInfo.execute(%{pid: pid}) do
      {:ok, process_info} ->
        # Try graceful restart first
        case Arsenal.Operations.RestartProcess.execute(%{pid: pid}) do
          {:ok, result} ->
            {:ok, result}
          
          {:error, _} ->
            # If restart fails, try kill and let supervisor restart
            case Arsenal.Operations.KillProcess.execute(%{pid: pid, reason: :restart}) do
              {:ok, _} -> {:ok, %{pid: pid, action: :killed_for_restart}}
              error -> error
            end
        end
      
      error ->
        error
    end
  end
  
  defp kill_single_process(pid, reason) do
    Arsenal.Operations.KillProcess.execute(%{pid: pid, reason: reason})
  end
  
  defp validate_process_spec(spec) do
    required_fields = [:module, :function]
    
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(spec, field)
    end)
    
    if length(missing_fields) > 0 do
      {:error, {:missing_fields, missing_fields}}
    else
      :ok
    end
  end
  
  defp perform_health_check(managed_processes) do
    Enum.map(managed_processes, fn {pid, process_data} ->
      health_result = check_process_health(pid, process_data)
      {pid, health_result}
    end)
  end
  
  defp check_process_health(pid, process_data) do
    case Arsenal.Operations.GetProcessInfo.execute(%{pid: pid}) do
      {:ok, process_info} ->
        health_status = assess_process_health(process_info, process_data)
        
        %{
          status: health_status,
          memory_mb: div(process_info.memory, 1024 * 1024),
          queue_length: process_info.message_queue_length,
          reductions: process_info.reductions,
          uptime_seconds: calculate_uptime(process_data.started_at),
          restart_count: process_data.restarts
        }
      
      {:error, reason} ->
        %{
          status: :dead,
          error: reason,
          last_seen: process_data.started_at
        }
    end
  end
  
  defp assess_process_health(process_info, _process_data) do
    cond do
      process_info.status != :running ->
        :unhealthy
      
      process_info.memory > 100 * 1024 * 1024 ->  # >100MB
        :memory_warning
      
      process_info.message_queue_length > 10000 ->
        :queue_warning
      
      process_info.reductions > 1_000_000_000 ->  # Very high CPU
        :cpu_warning
      
      true ->
        :healthy
    end
  end
  
  defp handle_unhealthy_processes(health_results, state) do
    unhealthy = Enum.filter(health_results, fn {_pid, result} ->
      result.status != :healthy
    end)
    
    Enum.reduce(unhealthy, state, fn {pid, health_result}, acc_state ->
      handle_unhealthy_process(pid, health_result, acc_state)
    end)
  end
  
  defp handle_unhealthy_process(pid, health_result, state) do
    case health_result.status do
      :dead ->
        # Remove from managed processes
        Logger.warn("Removing dead process from management", pid: pid)
        managed_processes = Map.delete(state.managed_processes, pid)
        stats = update_stats(state.stats, :dead_processes_detected, 1)
        %{state | managed_processes: managed_processes, stats: stats}
      
      :memory_warning ->
        Logger.warn("Process memory warning", 
          pid: pid, 
          memory_mb: health_result.memory_mb
        )
        # Could implement memory-based actions here
        state
      
      :queue_warning ->
        Logger.warn("Process queue warning", 
          pid: pid, 
          queue_length: health_result.queue_length
        )
        # Could implement queue-based actions here
        state
      
      :cpu_warning ->
        Logger.warn("Process CPU warning", 
          pid: pid, 
          reductions: health_result.reductions
        )
        # Could implement CPU-based actions here
        state
      
      _ ->
        state
    end
  end
  
  defp apply_management_policies(state) do
    Enum.reduce(state.policies, state, fn policy, acc_state ->
      if policy.enabled and should_apply_policy?(policy, acc_state) do
        apply_single_policy(policy, acc_state)
      else
        acc_state
      end
    end)
  end
  
  defp should_apply_policy?(policy, state) do
    # Check cooldown
    last_action = Map.get(state.policy_actions, policy.name)
    
    cooldown_ok = case last_action do
      nil -> true
      %{timestamp: timestamp} ->
        DateTime.diff(DateTime.utc_now(), timestamp, :second) >= policy.cooldown_seconds
    end
    
    # Check rate limiting
    hourly_limit_ok = check_hourly_action_limit(policy, state)
    
    cooldown_ok and hourly_limit_ok
  end
  
  defp apply_single_policy(policy, state) do
    Logger.info("Applying policy", policy_name: policy.name)
    
    # This would evaluate policy conditions and execute actions
    # For now, just log the policy application
    
    # Record policy action
    policy_actions = Map.put(state.policy_actions, policy.name, %{
      timestamp: DateTime.utc_now(),
      actions_applied: policy.actions
    })
    
    %{state | policy_actions: policy_actions}
  end
  
  defp check_hourly_action_limit(policy, state) do
    case Map.get(state.policy_actions, policy.name) do
      nil -> true
      action_data ->
        # Check how many times this policy was applied in the last hour
        hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)
        
        # In a real implementation, you'd track all action timestamps
        # For now, just check if last action was within an hour
        DateTime.compare(action_data.timestamp, hour_ago) == :lt
    end
  end
  
  defp default_policies do
    [
      %ProcessPolicy{
        name: "restart_dead_processes",
        conditions: [:process_dead],
        actions: [:restart],
        cooldown_seconds: 60,
        max_actions_per_hour: 10,
        enabled: true
      },
      %ProcessPolicy{
        name: "kill_memory_hogs",
        conditions: [{:memory_greater_than, 500 * 1024 * 1024}],
        actions: [:kill],
        cooldown_seconds: 300,
        max_actions_per_hour: 5,
        enabled: false  # Disabled by default for safety
      }
    ]
  end
  
  defp initialize_stats do
    %{
      processes_started: 0,
      processes_stopped: 0,
      processes_restarted: 0,
      processes_killed: 0,
      dead_processes_detected: 0,
      health_checks_performed: 0,
      policies_applied: 0,
      start_time: DateTime.utc_now()
    }
  end
  
  defp update_stats(stats, metric, increment) do
    Map.update(stats, metric, increment, &(&1 + increment))
  end
  
  defp get_uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end
  
  defp calculate_uptime(started_at) do
    DateTime.diff(DateTime.utc_now(), started_at, :second)
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, 30_000)  # Every 30 seconds
  end
  
  defp schedule_policy_check do
    Process.send_after(self(), :policy_check, 60_000)  # Every minute
  end
end