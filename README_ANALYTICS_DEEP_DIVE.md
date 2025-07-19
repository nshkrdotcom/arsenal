# Arsenal Analytics Server - Deep Dive

**Production-Grade Monitoring and Analytics for OTP Systems**

This document provides an in-depth exploration of Arsenal's AnalyticsServer, a comprehensive monitoring solution that tracks system health, performance metrics, restart patterns, and provides real-time anomaly detection for Elixir/OTP applications.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Core Data Structures](#core-data-structures)
- [Monitoring Capabilities](#monitoring-capabilities)
- [Event System](#event-system)
- [Anomaly Detection](#anomaly-detection)
- [Performance Considerations](#performance-considerations)
- [Integration Patterns](#integration-patterns)
- [Advanced Usage Scenarios](#advanced-usage-scenarios)
- [Troubleshooting Guide](#troubleshooting-guide)

## Architecture Overview

The AnalyticsServer is designed as a standalone GenServer that operates independently within your OTP supervision tree, collecting and analyzing system metrics without impacting application performance.

### Design Principles

1. **Non-Intrusive Monitoring**: Collects metrics without blocking application processes
2. **Bounded Memory Usage**: Implements sliding windows and data retention policies
3. **Real-Time Analysis**: Performs continuous analysis with configurable intervals
4. **Event-Driven Architecture**: Publishes events for external consumption
5. **Fault Tolerance**: Gracefully handles monitoring failures without crashing

### Internal State Management

```elixir
defstruct [
  :restart_history,      # Sliding window of supervisor restart events
  :performance_history,  # Time-series performance metrics
  :health_history,       # Historical health check results
  :event_subscriptions,  # Active event subscribers
  :monitoring_interval,  # How often to collect metrics (ms)
  :retention_period,     # How long to keep historical data (ms)
  :last_health_check,    # Timestamp of last health check
  :anomaly_thresholds,   # Configurable anomaly detection thresholds
  :baseline_metrics      # Rolling baseline for anomaly detection
]
```

## Core Data Structures

### Restart Event

```elixir
@type restart_event :: %{
  supervisor: pid() | atom(),      # Supervisor that performed restart
  child_id: term(),                # Child specification ID
  reason: term(),                  # Restart reason
  timestamp: DateTime.t(),         # When the restart occurred
  restart_count: non_neg_integer(), # Total restarts for this child
  child_pid: pid() | nil           # Current child PID if available
}
```

### System Health

```elixir
@type system_health :: %{
  overall_status: :healthy | :warning | :critical,
  process_count: non_neg_integer(),
  memory_usage: %{
    total: non_neg_integer(),
    processes: non_neg_integer(),
    system: non_neg_integer(),
    atom: non_neg_integer(),
    binary: non_neg_integer(),
    code: non_neg_integer(),
    ets: non_neg_integer()
  },
  cpu_usage: float(),
  restart_rate: float(),
  message_queue_lengths: %{
    max: non_neg_integer(),
    average: float(),
    processes_with_long_queues: non_neg_integer()
  },
  anomalies: [map()],
  recommendations: [String.t()],
  last_check: DateTime.t()
}
```

### Performance Metrics

```elixir
@type performance_metrics :: %{
  cpu: %{
    utilization: float(),
    load_average: [float()],
    scheduler_utilization: [float()]
  },
  memory: %{
    total: non_neg_integer(),
    used: non_neg_integer(),
    available: non_neg_integer(),
    processes: non_neg_integer(),
    system: non_neg_integer()
  },
  processes: %{
    count: non_neg_integer(),
    limit: non_neg_integer(),
    utilization: float(),
    runnable: non_neg_integer(),
    running: non_neg_integer()
  },
  io: %{
    input: non_neg_integer(),
    output: non_neg_integer()
  },
  gc: %{
    collections: non_neg_integer(),
    words_reclaimed: non_neg_integer(),
    time_spent: non_neg_integer()
  },
  timestamp: DateTime.t()
}
```

## Monitoring Capabilities

### 1. Restart Pattern Analysis

The AnalyticsServer tracks supervisor restart events to identify problematic patterns:

```elixir
# Track a restart event
Arsenal.AnalyticsServer.track_restart(:my_supervisor, :worker_1, :normal)

# Get comprehensive restart statistics
{:ok, stats} = Arsenal.AnalyticsServer.get_restart_statistics(:my_supervisor)

# Stats include:
# - Total restart count
# - Restart rate (per hour)
# - Most frequently restarted children
# - Restart reason distribution
# - Time between restarts
# - Detected patterns
```

#### Pattern Detection Algorithm

The server implements pattern detection to identify:

1. **Restart Storms**: Rapid consecutive restarts of the same child
2. **Cascading Failures**: Related processes failing in sequence
3. **Periodic Failures**: Restarts occurring at regular intervals
4. **Resource-Related Restarts**: Correlated with memory/CPU spikes

### 2. Performance Metrics Collection

```elixir
# Get current performance snapshot
{:ok, metrics} = Arsenal.AnalyticsServer.get_performance_metrics()

# Metrics include:
# - CPU utilization and scheduler usage
# - Memory breakdown by type
# - Process count and utilization
# - I/O statistics
# - Garbage collection metrics
```

#### CPU Metrics Deep Dive

The server calculates CPU utilization using scheduler wall time:

```elixir
defp get_scheduler_utilization do
  case :erlang.statistics(:scheduler_wall_time) do
    :undefined ->
      :erlang.system_flag(:scheduler_wall_time, true)
      # Retry after enabling
    schedulers ->
      calculate_scheduler_utilization(schedulers)
  end
end
```

### 3. Health Assessment

The health check system evaluates multiple indicators:

```elixir
# Automatic health checks run at configured intervals
# Manual health check
{:ok, health} = Arsenal.AnalyticsServer.get_system_health()
```

#### Health Evaluation Criteria

1. **Memory Health**
   - Critical: >90% utilization
   - Warning: >75% utilization
   - Healthy: <75% utilization

2. **Process Health**
   - Critical: >90% of process limit
   - Warning: >75% of process limit
   - Healthy: <75% of process limit

3. **CPU Health**
   - Critical: >90% utilization
   - Warning: >75% utilization
   - Healthy: <75% utilization

4. **Restart Health**
   - Critical: >10 restarts in 5 minutes
   - Warning: >5 restarts in 5 minutes
   - Healthy: ≤5 restarts in 5 minutes

### 4. Message Queue Analysis

```elixir
defp analyze_message_queues do
  processes = Process.list()
  
  queue_lengths = Enum.map(processes, fn pid ->
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len
      nil -> 0
    end
  end)
  
  %{
    max: Enum.max(queue_lengths, fn -> 0 end),
    average: calculate_average(queue_lengths),
    processes_with_long_queues: Enum.count(queue_lengths, &(&1 > 100))
  }
end
```

## Event System

### Event Types

```elixir
# Available event types
@event_types [:restart, :health_alert, :performance_alert, :anomaly, :all]
```

### Subscription Management

```elixir
# Subscribe to specific events
Arsenal.AnalyticsServer.subscribe_to_events([:restart, :health_alert])

# Subscribe with custom filter
filter = fn event ->
  event.severity == :high && event.type == :restart_anomaly
end
Arsenal.AnalyticsServer.subscribe_to_events([:anomaly], filter)

# Unsubscribe
Arsenal.AnalyticsServer.unsubscribe_from_events()
```

### Event Handling

```elixir
# In your GenServer or process
def handle_info({:arsenal_analytics_event, event_type, event_data}, state) do
  case event_type do
    :restart ->
      handle_restart_event(event_data)
    
    :health_alert ->
      handle_health_alert(event_data)
    
    :performance_alert ->
      handle_performance_alert(event_data)
    
    :anomaly ->
      handle_anomaly(event_data)
  end
  
  {:noreply, state}
end
```

## Anomaly Detection

### Baseline Establishment

The server maintains rolling baselines using exponential moving averages:

```elixir
defp update_baseline_metrics(nil, current_metrics) do
  current_metrics
end

defp update_baseline_metrics(baseline, current_metrics) do
  alpha = 0.1  # Smoothing factor
  
  %{
    cpu: %{
      utilization: 
        alpha * current_metrics.cpu.utilization + 
        (1 - alpha) * baseline.cpu.utilization
    },
    # ... similar for other metrics
  }
end
```

### Anomaly Types

1. **CPU Anomaly**
   ```elixir
   %{
     type: :cpu_anomaly,
     severity: :high | :medium,
     description: "CPU utilization significantly different from baseline",
     current_value: 85.5,
     baseline_value: 45.2,
     timestamp: ~U[2024-01-18 10:30:00Z]
   }
   ```

2. **Memory Anomaly**
   ```elixir
   %{
     type: :memory_anomaly,
     severity: :high | :medium,
     description: "Memory usage significantly different from baseline",
     current_value: 78.3,  # Percentage
     baseline_value: 52.1,
     timestamp: ~U[2024-01-18 10:30:00Z]
   }
   ```

3. **Process Count Anomaly**
   ```elixir
   %{
     type: :process_count_anomaly,
     severity: :medium,
     description: "Process count significantly different from baseline",
     current_value: 15000,
     baseline_value: 8000,
     timestamp: ~U[2024-01-18 10:30:00Z]
   }
   ```

4. **Restart Anomaly**
   ```elixir
   %{
     type: :restart_anomaly,
     severity: :high,
     description: "Rapid restart cycle detected for worker_process",
     child_id: :worker_process,
     supervisor: :main_supervisor,
     restart_count: 5,
     timestamp: ~U[2024-01-18 10:30:00Z]
   }
   ```

### Detection Thresholds

Configure anomaly detection sensitivity:

```elixir
# Start with custom thresholds
Arsenal.AnalyticsServer.start_link(
  anomaly_threshold: 3.0  # Standard deviations from baseline
)

# Default thresholds
@default_anomaly_threshold 2.0
```

## Performance Considerations

### Memory Management

1. **Bounded History**: The server limits historical data:
   ```elixir
   @max_history_size 1000
   
   new_history = [new_event | state.restart_history]
                 |> Enum.take(@max_history_size)
   ```

2. **Automatic Cleanup**: Old data is purged periodically:
   ```elixir
   defp cleanup_old_data(state) do
     cutoff_time = DateTime.add(DateTime.utc_now(), -state.retention_period, :millisecond)
     
     # Filter out old data from all history lists
   end
   ```

### CPU Optimization

1. **Lazy Evaluation**: Expensive calculations are deferred
2. **Sampling**: Not all processes are inspected every cycle
3. **Batch Processing**: Multiple metrics collected in single pass

### Monitoring Overhead

Typical overhead metrics:
- CPU: <1% in most cases
- Memory: ~1-5MB depending on history size
- Message passing: Minimal, uses cast for non-critical updates

## Integration Patterns

### 1. Alerting System Integration

```elixir
defmodule MyApp.AlertManager do
  use GenServer
  
  def init(_) do
    # Subscribe to critical events
    Arsenal.AnalyticsServer.subscribe_to_events(
      [:health_alert, :anomaly],
      &critical_event?/1
    )
    {:ok, %{}}
  end
  
  def handle_info({:arsenal_analytics_event, _type, event}, state) do
    send_alert(event)
    {:noreply, state}
  end
  
  defp critical_event?(event) do
    Map.get(event, :severity) == :high ||
    Map.get(event, :overall_status) == :critical
  end
  
  defp send_alert(event) do
    # Send to PagerDuty, Slack, etc.
  end
end
```

### 2. Metrics Export

```elixir
defmodule MyApp.MetricsExporter do
  use GenServer
  
  def init(_) do
    schedule_export()
    {:ok, %{}}
  end
  
  def handle_info(:export_metrics, state) do
    with {:ok, metrics} <- Arsenal.AnalyticsServer.get_performance_metrics(),
         {:ok, health} <- Arsenal.AnalyticsServer.get_system_health() do
      export_to_prometheus(metrics, health)
      export_to_datadog(metrics, health)
    end
    
    schedule_export()
    {:noreply, state}
  end
  
  defp schedule_export do
    Process.send_after(self(), :export_metrics, 60_000)  # Every minute
  end
end
```

### 3. Supervisor Integration

```elixir
defmodule MyApp.MonitoredSupervisor do
  use Supervisor
  
  def init(children) do
    # Wrap children with restart tracking
    wrapped_children = Enum.map(children, &wrap_child_spec/1)
    Supervisor.init(wrapped_children, strategy: :one_for_one)
  end
  
  defp wrap_child_spec(child_spec) do
    %{
      child_spec
      | restart: :transient,
        start: {__MODULE__, :start_child, [child_spec]}
    }
  end
  
  def start_child(child_spec) do
    case child_spec.start do
      {module, function, args} ->
        result = apply(module, function, args)
        
        # Track if this is a restart
        if Process.get(:restarting) do
          Arsenal.AnalyticsServer.track_restart(
            self(),
            child_spec.id,
            Process.get(:restart_reason)
          )
        end
        
        result
    end
  end
end
```

## Advanced Usage Scenarios

### 1. Predictive Failure Detection

```elixir
defmodule MyApp.FailurePredictor do
  def predict_failures do
    with {:ok, history} <- get_recent_history(),
         patterns <- analyze_patterns(history) do
      
      predictions = Enum.map(patterns, fn pattern ->
        case pattern do
          %{type: :periodic_restart, interval: interval} ->
            %{
              child_id: pattern.child_id,
              next_failure: DateTime.add(pattern.last_restart, interval, :second),
              confidence: calculate_confidence(pattern)
            }
          
          %{type: :resource_correlated} ->
            %{
              child_id: pattern.child_id,
              trigger: pattern.resource_threshold,
              resource_type: pattern.resource_type
            }
        end
      end)
      
      {:ok, predictions}
    end
  end
  
  defp get_recent_history do
    Arsenal.AnalyticsServer.get_historical_data(
      DateTime.add(DateTime.utc_now(), -3600, :second),
      DateTime.utc_now()
    )
  end
end
```

### 2. Capacity Planning

```elixir
defmodule MyApp.CapacityPlanner do
  def analyze_growth_trends do
    with {:ok, history} <- get_long_term_history() do
      trends = %{
        process_growth: calculate_growth_rate(history.metrics, :process_count),
        memory_growth: calculate_growth_rate(history.metrics, :memory_usage),
        cpu_trend: calculate_utilization_trend(history.metrics)
      }
      
      projections = %{
        processes_limit_reached: project_limit_breach(trends.process_growth),
        memory_exhaustion: project_resource_exhaustion(trends.memory_growth),
        cpu_bottleneck: project_cpu_bottleneck(trends.cpu_trend)
      }
      
      {:ok, projections}
    end
  end
  
  defp calculate_growth_rate(metrics, field) do
    # Linear regression or similar
  end
end
```

### 3. Automated Response System

```elixir
defmodule MyApp.AutoHealer do
  use GenServer
  
  def init(_) do
    Arsenal.AnalyticsServer.subscribe_to_events([:anomaly, :health_alert])
    {:ok, %{actions_taken: []}}
  end
  
  def handle_info({:arsenal_analytics_event, _type, event}, state) do
    action = determine_action(event)
    
    case execute_action(action) do
      :ok ->
        new_state = %{state | actions_taken: [action | state.actions_taken]}
        {:noreply, new_state}
      
      :error ->
        # Log but don't crash
        {:noreply, state}
    end
  end
  
  defp determine_action(%{type: :memory_anomaly, severity: :high}) do
    {:force_gc, :all_processes}
  end
  
  defp determine_action(%{type: :restart_anomaly, child_id: child_id}) do
    {:delay_restart, child_id, :exponential_backoff}
  end
  
  defp execute_action({:force_gc, :all_processes}) do
    Enum.each(Process.list(), &:erlang.garbage_collect/1)
    :ok
  end
end
```

## Troubleshooting Guide

### Common Issues

1. **High Memory Usage in AnalyticsServer**
   - Check retention period settings
   - Verify max_history_size limits
   - Look for memory leaks in event subscribers

2. **Missing Metrics**
   - Ensure scheduler wall time is enabled
   - Check for permission issues accessing system info
   - Verify the server is running

3. **Event Delivery Failures**
   - Check subscriber process health
   - Verify event filters aren't too restrictive
   - Monitor for message queue buildup

### Debugging Commands

```elixir
# Check server state
:sys.get_state(Arsenal.AnalyticsServer)

# Get server statistics
{:ok, stats} = Arsenal.AnalyticsServer.get_server_stats()

# Force immediate health check
Arsenal.AnalyticsServer.force_health_check()

# Trace server activity
:sys.trace(Arsenal.AnalyticsServer, true)
```

### Performance Tuning

1. **Adjust Monitoring Interval**
   ```elixir
   # For high-load systems, increase interval
   Arsenal.AnalyticsServer.start_link(monitoring_interval: 30_000)
   ```

2. **Tune History Sizes**
   ```elixir
   # Reduce memory usage
   Arsenal.AnalyticsServer.start_link(
     retention_period: 3_600_000,  # 1 hour instead of 24
   )
   ```

3. **Selective Monitoring**
   ```elixir
   # Create custom metrics collector
   defmodule MyApp.SelectiveAnalytics do
     # Only monitor specific supervisors
     def track_restart(supervisor, child_id, reason) 
       when supervisor in [:critical_sup, :important_sup] do
       Arsenal.AnalyticsServer.track_restart(supervisor, child_id, reason)
     end
     
     def track_restart(_, _, _), do: :ok
   end
   ```

## Best Practices

1. **Start Early**: Initialize AnalyticsServer in your application supervision tree
2. **Subscribe Wisely**: Only subscribe to events you'll act upon
3. **Handle Events Asynchronously**: Don't block on event processing
4. **Monitor the Monitor**: Track AnalyticsServer health itself
5. **Export Metrics**: Integrate with external monitoring systems
6. **Set Appropriate Thresholds**: Tune based on your system's normal behavior
7. **Use Historical Data**: Make decisions based on trends, not snapshots

## Conclusion

The Arsenal AnalyticsServer provides a robust foundation for production monitoring of OTP systems. By understanding its architecture and capabilities, you can build sophisticated monitoring, alerting, and self-healing systems that keep your applications running smoothly.

For specific implementation questions or advanced scenarios not covered here, consult the source code at `lib/arsenal/analytics_server.ex` which contains detailed documentation and examples.