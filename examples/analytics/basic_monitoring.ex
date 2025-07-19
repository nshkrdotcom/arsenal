defmodule Examples.Analytics.BasicMonitoring do
  @moduledoc """
  Basic examples of using Arsenal.AnalyticsServer for system monitoring.
  
  This module demonstrates:
  - Setting up analytics monitoring
  - Subscribing to events
  - Getting system health metrics
  - Tracking restart events
  - Basic alerting patterns
  """
  
  use GenServer
  require Logger
  
  @doc """
  Start the basic monitoring example.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get a summary of current system health.
  """
  def get_health_summary do
    GenServer.call(__MODULE__, :get_health_summary)
  end
  
  @doc """
  Get performance metrics for the last hour.
  """
  def get_performance_summary do
    GenServer.call(__MODULE__, :get_performance_summary)
  end
  
  @doc """
  Get restart statistics for all supervisors.
  """
  def get_restart_summary do
    GenServer.call(__MODULE__, :get_restart_summary)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    # Subscribe to all analytics events
    :ok = Arsenal.AnalyticsServer.subscribe_to_events([:all])
    
    # Start periodic health checks
    schedule_health_check()
    
    state = %{
      health_alerts: [],
      performance_alerts: [],
      restart_events: [],
      last_health_check: nil
    }
    
    Logger.info("BasicMonitoring started and subscribed to Arsenal analytics")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_health_summary, _from, state) do
    case Arsenal.AnalyticsServer.get_system_health() do
      {:ok, health} ->
        summary = %{
          overall_status: health.overall_status,
          process_count: health.process_count,
          memory_usage_mb: div(health.memory_usage.total, 1024 * 1024),
          cpu_usage: health.cpu_usage,
          restart_rate: health.restart_rate,
          anomalies_count: length(health.anomalies),
          recommendations: health.recommendations,
          last_check: health.last_check,
          recent_alerts: Enum.take(state.health_alerts, 5)
        }
        {:reply, {:ok, summary}, state}
      
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call(:get_performance_summary, _from, state) do
    case Arsenal.AnalyticsServer.get_performance_metrics() do
      {:ok, metrics} ->
        summary = %{
          cpu_utilization: metrics.cpu.utilization,
          memory_total_mb: div(metrics.memory.total, 1024 * 1024),
          memory_used_mb: div(metrics.memory.used, 1024 * 1024),
          memory_utilization: (metrics.memory.used / metrics.memory.total * 100) |> Float.round(2),
          process_count: metrics.processes.count,
          process_limit: metrics.processes.limit,
          process_utilization: metrics.processes.utilization,
          gc_collections: metrics.gc.collections,
          timestamp: metrics.timestamp,
          recent_alerts: Enum.take(state.performance_alerts, 5)
        }
        {:reply, {:ok, summary}, state}
      
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call(:get_restart_summary, _from, state) do
    supervisors_result = Arsenal.Operations.ListSupervisors.execute(%{})
    
    restart_stats = case supervisors_result do
      {:ok, {supervisor_list, _meta}} ->
        Enum.map(supervisor_list, fn supervisor ->
          case Arsenal.AnalyticsServer.get_restart_statistics(supervisor.pid) do
            {:ok, stats} ->
              %{
                supervisor: supervisor.name || supervisor.pid,
                total_restarts: stats.total_restarts,
                restart_rate: stats.restart_rate,
                most_restarted: stats.most_restarted_child,
                last_restart: stats.last_restart
              }
            
            {:error, _} ->
              %{
                supervisor: supervisor.name || supervisor.pid,
                total_restarts: 0,
                restart_rate: 0.0,
                error: "Unable to get stats"
              }
          end
        end)
      
      {:error, reason} ->
        Logger.error("Failed to get supervisors: #{inspect(reason)}")
        []
    end
    
    summary = %{
      supervisors: restart_stats,
      recent_restart_events: Enum.take(state.restart_events, 10),
      total_supervisors: length(restart_stats)
    }
    
    {:reply, {:ok, summary}, state}
  end
  
  @impl true
  def handle_info({:arsenal_analytics_event, event_type, event_data}, state) do
    new_state = handle_analytics_event(event_type, event_data, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    case Arsenal.AnalyticsServer.get_system_health() do
      {:ok, health} ->
        new_state = %{state | last_health_check: DateTime.utc_now()}
        
        # Check for critical conditions
        if health.overall_status == :critical do
          Logger.error("CRITICAL: System health is critical!", 
            health: health, 
            anomalies: health.anomalies
          )
          
          # In a real system, you'd send alerts here
          send_critical_alert(health)
        end
        
        schedule_health_check()
        {:noreply, new_state}
      
      {:error, reason} ->
        Logger.error("Failed to get system health: #{inspect(reason)}")
        schedule_health_check()
        {:noreply, state}
    end
  end
  
  # Private functions
  
  defp handle_analytics_event(:restart, event_data, state) do
    Logger.info("Process restart detected", restart_event: event_data)
    
    # Add to restart events history
    restart_event = %{
      supervisor: event_data.supervisor,
      child_id: event_data.child_id,
      reason: event_data.reason,
      timestamp: event_data.timestamp,
      restart_count: event_data.restart_count
    }
    
    restart_events = [restart_event | state.restart_events] |> Enum.take(100)
    
    # Check for restart storm (5+ restarts of same child in 1 minute)
    if event_data.restart_count >= 5 do
      Logger.warning("Restart storm detected!", 
        child: event_data.child_id,
        supervisor: event_data.supervisor,
        count: event_data.restart_count
      )
      
      send_restart_storm_alert(event_data)
    end
    
    %{state | restart_events: restart_events}
  end
  
  defp handle_analytics_event(:health_alert, event_data, state) do
    Logger.warning("Health alert received", alert: event_data)
    
    alert = %{
      type: :health_alert,
      data: event_data,
      timestamp: DateTime.utc_now()
    }
    
    health_alerts = [alert | state.health_alerts] |> Enum.take(50)
    
    %{state | health_alerts: health_alerts}
  end
  
  defp handle_analytics_event(:performance_alert, event_data, state) do
    Logger.warning("Performance alert received", alert: event_data)
    
    alert = %{
      type: :performance_alert,
      data: event_data,
      timestamp: DateTime.utc_now()
    }
    
    performance_alerts = [alert | state.performance_alerts] |> Enum.take(50)
    
    %{state | performance_alerts: performance_alerts}
  end
  
  defp handle_analytics_event(:anomaly, event_data, state) do
    Logger.warning("Anomaly detected", anomaly: event_data)
    
    case event_data.severity do
      :high ->
        send_anomaly_alert(event_data)
      
      :medium ->
        Logger.info("Medium anomaly detected", anomaly: event_data)
      
      _ ->
        :ok
    end
    
    state
  end
  
  defp handle_analytics_event(_event_type, _event_data, state) do
    # Handle other event types
    state
  end
  
  defp schedule_health_check do
    # Check health every 30 seconds
    Process.send_after(self(), :health_check, 30_000)
  end
  
  defp send_critical_alert(health) do
    # In a real system, you'd integrate with PagerDuty, Slack, etc.
    Logger.error("SENDING CRITICAL ALERT: System health critical", 
      status: health.overall_status,
      memory_usage: health.memory_usage.total,
      process_count: health.process_count,
      anomalies: health.anomalies
    )
    
    # Example integration:
    # PagerDuty.send_alert(%{
    #   summary: "Arsenal system health critical",
    #   severity: "critical",
    #   source: "arsenal-analytics",
    #   details: health
    # })
  end
  
  defp send_restart_storm_alert(restart_data) do
    Logger.error("SENDING RESTART STORM ALERT", restart_data: restart_data)
    
    # Example Slack integration:
    # Slack.send_message("#alerts", """
    # 🚨 *Restart Storm Detected*
    # 
    # Child: #{restart_data.child_id}
    # Supervisor: #{restart_data.supervisor}
    # Restart Count: #{restart_data.restart_count}
    # Reason: #{restart_data.reason}
    # """)
  end
  
  defp send_anomaly_alert(anomaly_data) do
    Logger.warning("SENDING ANOMALY ALERT", anomaly: anomaly_data)
    
    # Example email integration:
    # Email.send_alert("devops@company.com", %{
    #   subject: "Arsenal Anomaly Detected: #{anomaly_data.type}",
    #   body: "Anomaly detected: #{anomaly_data.description}",
    #   details: anomaly_data
    # })
  end
end