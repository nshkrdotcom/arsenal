# Analytics Examples

This directory demonstrates how to use Arsenal's analytics capabilities for comprehensive system monitoring, alerting, and observability.

## Examples Overview

### 1. `basic_monitoring.ex` - Basic System Monitoring
A simple monitoring service that demonstrates core analytics features.

**Features:**
- **Event Subscription**: Subscribe to all Arsenal analytics events
- **Health Monitoring**: Periodic system health checks with alerting
- **Restart Tracking**: Monitor and alert on process restart patterns
- **Performance Monitoring**: Track CPU, memory, and process metrics
- **Basic Alerting**: Console logging with structured alerts

**Usage:**
```elixir
# Start the monitoring service
{:ok, _pid} = Examples.Analytics.BasicMonitoring.start_link()

# Get health summary
{:ok, health} = Examples.Analytics.BasicMonitoring.get_health_summary()
# Returns:
%{
  overall_status: :healthy,
  process_count: 42,
  memory_usage_mb: 156,
  cpu_usage: 12.5,
  restart_rate: 0.1,
  anomalies_count: 0,
  recommendations: [],
  recent_alerts: []
}

# Get performance summary
{:ok, perf} = Examples.Analytics.BasicMonitoring.get_performance_summary()

# Get restart summary for all supervisors
{:ok, restarts} = Examples.Analytics.BasicMonitoring.get_restart_summary()
```

### 2. `dashboard_data.ex` - Dashboard Data Provider
Provides formatted data for monitoring dashboards and external systems.

**Features:**
- **Complete Dashboard Data**: All metrics formatted for web dashboards
- **Real-time Metrics**: Live metrics for streaming updates
- **Historical Data**: Time-series data for charts and trends
- **Process Analysis**: Detailed process breakdown and analysis
- **Supervisor Health**: Health status for supervision trees

**Usage:**
```elixir
# Get complete dashboard data
{:ok, dashboard} = Examples.Analytics.DashboardData.get_dashboard_data()
# Returns comprehensive monitoring data structure

# Get real-time metrics (for live updates)
{:ok, metrics} = Examples.Analytics.DashboardData.get_realtime_metrics()
# Returns:
%{
  timestamp: "2024-01-18T10:30:00Z",
  cpu_usage: 15.2,
  memory_usage: 68.5,
  process_count: 1247,
  runnable_processes: 3,
  running_processes: 8
}

# Get historical data for charts
{:ok, history} = Examples.Analytics.DashboardData.get_historical_data(24)

# Get supervisor health status
{:ok, supervisor_health} = Examples.Analytics.DashboardData.get_supervisor_health()

# Get detailed process analysis  
{:ok, process_analysis} = Examples.Analytics.DashboardData.get_process_analysis()
```

### 3. `alerting_system.ex` - Advanced Alerting System
Production-ready alerting system with rules, escalation, and multi-channel notifications.

**Features:**
- **Custom Alert Rules**: Configurable rules with conditions and templates
- **Alert Deduplication**: Prevents duplicate alerts using fingerprints
- **Escalation Policies**: Time-based escalation with multiple notification levels
- **Multi-channel Notifications**: Slack, email, PagerDuty, console logging
- **Alert Management**: Acknowledge, resolve, and track alert history
- **Suppression Rules**: Prevent alert storms with time-based suppression

**Usage:**
```elixir
# Start the alerting system
{:ok, _pid} = Examples.Analytics.AlertingSystem.start_link([
  slack_webhook: "https://hooks.slack.com/...",
  slack_channel: "#alerts",
  email_recipients: ["ops@company.com"],
  pagerduty_service_key: "your-service-key"
])

# Get active alerts
alerts = Examples.Analytics.AlertingSystem.get_active_alerts()

# Acknowledge an alert
:ok = Examples.Analytics.AlertingSystem.acknowledge_alert("alert-123", "john.doe")

# Resolve an alert
:ok = Examples.Analytics.AlertingSystem.resolve_alert("alert-123", "system")

# Get alert history
history = Examples.Analytics.AlertingSystem.get_alert_history(50)

# Configure custom alert rules
rules = [
  %{
    name: "Custom High Memory Alert",
    event_types: [:health_alert],
    alert_type: :custom_memory,
    severity: :warning,
    conditions: [
      {:field_greater_than, [:memory_usage, :processes], 500_000_000}
    ],
    title_template: "High Process Memory: {{memory_usage.processes}} bytes",
    description_template: "Process memory usage exceeds 500MB",
    notification_channels: [:slack, :email]
  }
]
:ok = Examples.Analytics.AlertingSystem.configure_rules(rules)
```

## Core Analytics Features Demonstrated

### 1. Event Subscription and Handling
```elixir
# Subscribe to specific events
Arsenal.AnalyticsServer.subscribe_to_events([:restart, :health_alert])

# Handle events in your GenServer
def handle_info({:arsenal_analytics_event, :restart, event_data}, state) do
  # Process restart event
  Logger.warn("Process restarted", event: event_data)
  {:noreply, state}
end
```

### 2. System Health Monitoring
```elixir
# Get current system health
{:ok, health} = Arsenal.AnalyticsServer.get_system_health()

# Health includes:
# - overall_status: :healthy | :warning | :critical
# - process_count, memory_usage, cpu_usage
# - restart_rate, message_queue_lengths
# - anomalies and recommendations
```

### 3. Performance Metrics
```elixir
# Get detailed performance metrics
{:ok, metrics} = Arsenal.AnalyticsServer.get_performance_metrics()

# Metrics include:
# - CPU utilization and scheduler stats
# - Memory breakdown by type
# - Process counts and utilization
# - I/O statistics
# - Garbage collection metrics
```

### 4. Restart Tracking
```elixir
# Track a restart event
Arsenal.AnalyticsServer.track_restart(:my_supervisor, :worker_1, :normal)

# Get restart statistics for a supervisor
{:ok, stats} = Arsenal.AnalyticsServer.get_restart_statistics(:my_supervisor)
```

### 5. Historical Data
```elixir
# Get historical data for analysis
start_time = DateTime.add(DateTime.utc_now(), -3600, :second)
end_time = DateTime.utc_now()

{:ok, history} = Arsenal.AnalyticsServer.get_historical_data(start_time, end_time)
```

## Integration Patterns

### 1. Web Dashboard Integration
```elixir
# In your Phoenix controller
def dashboard_data(conn, _params) do
  case Examples.Analytics.DashboardData.get_dashboard_data() do
    {:ok, data} -> json(conn, data)
    {:error, reason} -> 
      conn
      |> put_status(500)
      |> json(%{error: reason})
  end
end

# For real-time updates via WebSocket
def handle_info(:update_metrics, socket) do
  case Examples.Analytics.DashboardData.get_realtime_metrics() do
    {:ok, metrics} ->
      push(socket, "metrics_update", metrics)
      schedule_next_update()
      {:noreply, socket}
    
    {:error, _} ->
      {:noreply, socket}
  end
end
```

### 2. External Monitoring Integration
```elixir
# Export metrics to Prometheus
defmodule MyApp.PrometheusExporter do
  def export_metrics do
    case Arsenal.AnalyticsServer.get_performance_metrics() do
      {:ok, metrics} ->
        # Update Prometheus metrics
        :prometheus_gauge.set(:erlang_memory_usage, metrics.memory.used)
        :prometheus_gauge.set(:erlang_process_count, metrics.processes.count)
        :prometheus_gauge.set(:erlang_cpu_usage, metrics.cpu.utilization)
      
      {:error, _} ->
        :error
    end
  end
end

# Schedule regular exports
{:ok, _} = :timer.apply_interval(30_000, MyApp.PrometheusExporter, :export_metrics, [])
```

### 3. Custom Alert Integrations
```elixir
# Custom Slack integration
defmodule MyApp.SlackAlerter do
  def send_alert(alert) do
    message = %{
      text: "🚨 #{alert.title}",
      attachments: [
        %{
          color: severity_color(alert.severity),
          fields: [
            %{title: "Description", value: alert.description},
            %{title: "Time", value: DateTime.to_iso8601(alert.triggered_at)}
          ]
        }
      ]
    }
    
    HTTPoison.post(slack_webhook_url(), Jason.encode!(message))
  end
end

# Custom PagerDuty integration  
defmodule MyApp.PagerDutyAlerter do
  def create_incident(alert) do
    payload = %{
      incident_key: alert.id,
      event_type: "trigger",
      description: alert.title,
      details: alert.data
    }
    
    HTTPoison.post(pagerduty_url(), Jason.encode!(payload))
  end
end
```

## Alert Rule Examples

### 1. CPU Alert Rule
```elixir
%{
  name: "High CPU Usage",
  event_types: [:performance_alert],
  alert_type: :high_cpu,
  severity: :warning,
  conditions: [
    {:field_greater_than, [:cpu, :utilization], 80.0}
  ],
  title_template: "High CPU Usage: {{cpu.utilization}}%",
  description_template: "CPU utilization is {{cpu.utilization}}%, exceeding 80% threshold",
  notification_channels: [:slack]
}
```

### 2. Memory Alert Rule
```elixir
%{
  name: "Critical Memory Usage",
  event_types: [:health_alert],
  alert_type: :high_memory,
  severity: :critical,
  conditions: [
    {:field_greater_than, [:memory_usage, :total], 0.9}
  ],
  title_template: "Critical Memory Usage",
  description_template: "Memory usage is critical: {{memory_usage.total}}",
  notification_channels: [:slack, :pagerduty]
}
```

### 3. Custom Alert Rule
```elixir
%{
  name: "Long Message Queues",
  event_types: [:health_alert],
  alert_type: :long_queues,
  severity: :warning,
  conditions: [
    {:custom, fn data -> 
      queues = get_in(data, [:message_queue_lengths, :max]) || 0
      queues > 1000
    end}
  ],
  title_template: "Long Message Queues Detected",
  description_template: "Maximum queue length: {{message_queue_lengths.max}}",
  notification_channels: [:slack]
}
```

## Running the Examples

### 1. Start Arsenal and Analytics
```elixir
# Start Arsenal
{:ok, _} = Arsenal.start(:normal, [])

# Register some operations to monitor
Arsenal.Registry.register(:list_processes, Arsenal.Operations.ListProcesses)
```

### 2. Start Monitoring Services
```elixir
# Start basic monitoring
{:ok, _} = Examples.Analytics.BasicMonitoring.start_link()

# Start alerting system
{:ok, _} = Examples.Analytics.AlertingSystem.start_link([
  slack_webhook: "your-webhook-url",
  email_recipients: ["alerts@yourcompany.com"]
])
```

### 3. Generate Some Activity
```elixir
# Trigger some events for monitoring
Arsenal.Registry.execute(:list_processes, %{})

# Simulate a restart
Arsenal.AnalyticsServer.track_restart(self(), :test_worker, :normal)

# Force a health check
Arsenal.AnalyticsServer.force_health_check()
```

### 4. View Results
```elixir
# Check alerts
Examples.Analytics.AlertingSystem.get_active_alerts()

# Get monitoring data
Examples.Analytics.BasicMonitoring.get_health_summary()

# Get dashboard data
Examples.Analytics.DashboardData.get_dashboard_data()
```

## Production Considerations

1. **Resource Usage**: Monitor the monitoring system itself to prevent resource exhaustion
2. **Alert Fatigue**: Configure appropriate thresholds and suppression rules
3. **Storage**: Historical data grows over time - implement rotation policies
4. **Network**: External integrations can fail - implement retry logic
5. **Security**: Protect webhook URLs and API keys
6. **Testing**: Test alert rules and escalation policies regularly
7. **Documentation**: Document all custom alert rules and their purposes

## Integration with External Systems

- **Grafana**: Use dashboard data for Grafana dashboards
- **Prometheus**: Export metrics to Prometheus for long-term storage
- **Elasticsearch**: Send logs and metrics to ELK stack
- **DataDog**: Custom metrics and events to DataDog
- **New Relic**: Application performance monitoring integration