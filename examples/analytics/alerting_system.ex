defmodule Examples.Analytics.AlertingSystem do
  @moduledoc """
  Advanced alerting system for Arsenal analytics.
  
  This module demonstrates:
  - Custom alert rules and thresholds
  - Alert aggregation and deduplication
  - Multi-channel alert delivery (Slack, email, PagerDuty)
  - Alert escalation policies
  - Alert history and acknowledgment
  """
  
  use GenServer
  require Logger
  
  defmodule Alert do
    @moduledoc "Structure for alert data"
    
    defstruct [
      :id,
      :type,
      :severity,
      :title,
      :description,
      :source,
      :data,
      :triggered_at,
      :acknowledged_at,
      :resolved_at,
      :escalated_at,
      :escalation_level,
      :channels_notified,
      :fingerprint
    ]
    
    @type t :: %__MODULE__{
      id: String.t(),
      type: atom(),
      severity: :low | :medium | :high | :critical,
      title: String.t(),
      description: String.t(),
      source: atom(),
      data: map(),
      triggered_at: DateTime.t(),
      acknowledged_at: DateTime.t() | nil,
      resolved_at: DateTime.t() | nil,
      escalated_at: DateTime.t() | nil,
      escalation_level: non_neg_integer(),
      channels_notified: [atom()],
      fingerprint: String.t()
    }
  end
  
  @doc """
  Start the alerting system.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Acknowledge an alert by ID.
  """
  def acknowledge_alert(alert_id, acknowledged_by \\ "system") do
    GenServer.call(__MODULE__, {:acknowledge_alert, alert_id, acknowledged_by})
  end
  
  @doc """
  Resolve an alert by ID.
  """
  def resolve_alert(alert_id, resolved_by \\ "system") do
    GenServer.call(__MODULE__, {:resolve_alert, alert_id, resolved_by})
  end
  
  @doc """
  Get active alerts.
  """
  def get_active_alerts do
    GenServer.call(__MODULE__, :get_active_alerts)
  end
  
  @doc """
  Get alert history.
  """
  def get_alert_history(limit \\ 100) do
    GenServer.call(__MODULE__, {:get_alert_history, limit})
  end
  
  @doc """
  Configure custom alert rules.
  """
  def configure_rules(rules) do
    GenServer.call(__MODULE__, {:configure_rules, rules})
  end
  
  # GenServer callbacks
  
  @impl true
  def init(opts) do
    # Subscribe to Arsenal analytics events
    :ok = Arsenal.AnalyticsServer.subscribe_to_events([:all])
    
    # Schedule periodic health checks
    schedule_health_check()
    schedule_escalation_check()
    
    state = %{
      active_alerts: %{},
      alert_history: [],
      alert_rules: default_alert_rules(),
      escalation_policies: default_escalation_policies(),
      notification_channels: configure_notification_channels(opts),
      suppression_rules: default_suppression_rules()
    }
    
    Logger.info("AlertingSystem started with #{length(state.alert_rules)} rules")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:acknowledge_alert, alert_id, acknowledged_by}, _from, state) do
    case Map.get(state.active_alerts, alert_id) do
      nil ->
        {:reply, {:error, :alert_not_found}, state}
      
      alert ->
        acknowledged_alert = %{alert | 
          acknowledged_at: DateTime.utc_now(),
          data: Map.put(alert.data, :acknowledged_by, acknowledged_by)
        }
        
        active_alerts = Map.put(state.active_alerts, alert_id, acknowledged_alert)
        
        Logger.info("Alert acknowledged", 
          alert_id: alert_id, 
          acknowledged_by: acknowledged_by
        )
        
        {:reply, :ok, %{state | active_alerts: active_alerts}}
    end
  end
  
  @impl true
  def handle_call({:resolve_alert, alert_id, resolved_by}, _from, state) do
    case Map.get(state.active_alerts, alert_id) do
      nil ->
        {:reply, {:error, :alert_not_found}, state}
      
      alert ->
        resolved_alert = %{alert |
          resolved_at: DateTime.utc_now(),
          data: Map.put(alert.data, :resolved_by, resolved_by)
        }
        
        # Move to history and remove from active
        active_alerts = Map.delete(state.active_alerts, alert_id)
        alert_history = [resolved_alert | state.alert_history] |> Enum.take(1000)
        
        Logger.info("Alert resolved", 
          alert_id: alert_id, 
          resolved_by: resolved_by
        )
        
        send_notification(:alert_resolved, resolved_alert, state.notification_channels)
        
        {:reply, :ok, %{state | 
          active_alerts: active_alerts,
          alert_history: alert_history
        }}
    end
  end
  
  @impl true
  def handle_call(:get_active_alerts, _from, state) do
    alerts = Map.values(state.active_alerts)
    {:reply, alerts, state}
  end
  
  @impl true
  def handle_call({:get_alert_history, limit}, _from, state) do
    history = Enum.take(state.alert_history, limit)
    {:reply, history, state}
  end
  
  @impl true
  def handle_call({:configure_rules, rules}, _from, state) do
    Logger.info("Alert rules updated", rules_count: length(rules))
    {:reply, :ok, %{state | alert_rules: rules}}
  end
  
  @impl true
  def handle_info({:arsenal_analytics_event, event_type, event_data}, state) do
    new_state = process_analytics_event(event_type, event_data, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    new_state = check_system_health(state)
    schedule_health_check()
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:escalation_check, state) do
    new_state = check_alert_escalations(state)
    schedule_escalation_check()
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp process_analytics_event(event_type, event_data, state) do
    # Apply alert rules to the event
    state.alert_rules
    |> Enum.reduce(state, fn rule, acc_state ->
      if rule_matches?(rule, event_type, event_data) do
        create_alert_from_rule(rule, event_type, event_data, acc_state)
      else
        acc_state
      end
    end)
  end
  
  defp rule_matches?(rule, event_type, event_data) do
    # Check if rule applies to this event
    rule.event_types in [:all] or event_type in rule.event_types and
    evaluate_rule_conditions(rule.conditions, event_data)
  end
  
  defp evaluate_rule_conditions(conditions, event_data) do
    Enum.all?(conditions, fn condition ->
      case condition do
        {:field_equals, field, value} ->
          get_nested_field(event_data, field) == value
        
        {:field_greater_than, field, threshold} ->
          case get_nested_field(event_data, field) do
            val when is_number(val) -> val > threshold
            _ -> false
          end
        
        {:field_less_than, field, threshold} ->
          case get_nested_field(event_data, field) do
            val when is_number(val) -> val < threshold
            _ -> false
          end
        
        {:field_contains, field, substring} ->
          case get_nested_field(event_data, field) do
            val when is_binary(val) -> String.contains?(val, substring)
            _ -> false
          end
        
        {:custom, fun} when is_function(fun, 1) ->
          fun.(event_data)
        
        _ ->
          false
      end
    end)
  end
  
  defp create_alert_from_rule(rule, event_type, event_data, state) do
    # Generate alert fingerprint for deduplication
    fingerprint = generate_fingerprint(rule, event_data)
    
    # Check if we already have this alert (deduplication)
    existing_alert = Enum.find(Map.values(state.active_alerts), fn alert ->
      alert.fingerprint == fingerprint && alert.resolved_at == nil
    end)
    
    if existing_alert && should_suppress_alert?(existing_alert, rule, state) do
      # Alert is suppressed
      state
    else
      alert = %Alert{
        id: generate_alert_id(),
        type: rule.alert_type,
        severity: rule.severity,
        title: render_template(rule.title_template, event_data),
        description: render_template(rule.description_template, event_data),
        source: event_type,
        data: event_data,
        triggered_at: DateTime.utc_now(),
        escalation_level: 0,
        channels_notified: [],
        fingerprint: fingerprint
      }
      
      # Add to active alerts
      active_alerts = Map.put(state.active_alerts, alert.id, alert)
      
      # Send notifications
      send_initial_notifications(alert, rule, state.notification_channels)
      
      Logger.warning("Alert triggered", 
        alert_id: alert.id,
        type: alert.type,
        severity: alert.severity,
        title: alert.title
      )
      
      %{state | active_alerts: active_alerts}
    end
  end
  
  defp check_system_health(state) do
    case Arsenal.AnalyticsServer.get_system_health() do
      {:ok, health} ->
        # Check for system-level alerts
        health_alerts = evaluate_health_alerts(health, state.alert_rules)
        
        Enum.reduce(health_alerts, state, fn alert, acc_state ->
          existing = Enum.find(Map.values(acc_state.active_alerts), fn a ->
            a.type == alert.type && a.resolved_at == nil
          end)
          
          if existing do
            acc_state
          else
            active_alerts = Map.put(acc_state.active_alerts, alert.id, alert)
            send_initial_notifications(alert, nil, state.notification_channels)
            %{acc_state | active_alerts: active_alerts}
          end
        end)
      
      {:error, reason} ->
        Logger.error("Failed to check system health: #{inspect(reason)}")
        state
    end
  end
  
  defp check_alert_escalations(state) do
    now = DateTime.utc_now()
    
    Enum.reduce(state.active_alerts, state, fn {alert_id, alert}, acc_state ->
      if should_escalate_alert?(alert, now, state.escalation_policies) do
        escalated_alert = escalate_alert(alert, state.escalation_policies, state.notification_channels)
        active_alerts = Map.put(acc_state.active_alerts, alert_id, escalated_alert)
        %{acc_state | active_alerts: active_alerts}
      else
        acc_state
      end
    end)
  end
  
  defp should_escalate_alert?(alert, now, policies) do
    alert.acknowledged_at == nil &&
      alert.resolved_at == nil &&
      should_escalate_based_on_policy?(alert, now, policies)
  end
  
  defp should_escalate_based_on_policy?(alert, now, policies) do
    policy = get_escalation_policy(alert.severity, policies)
    
    if policy && alert.escalation_level < length(policy.levels) do
      current_level = Enum.at(policy.levels, alert.escalation_level)
      
      time_diff = DateTime.diff(now, alert.escalated_at || alert.triggered_at, :minute)
      time_diff >= current_level.delay_minutes
    else
      false
    end
  end
  
  defp escalate_alert(alert, policies, notification_channels) do
    policy = get_escalation_policy(alert.severity, policies)
    level = Enum.at(policy.levels, alert.escalation_level)
    
    Logger.warning("Escalating alert", 
      alert_id: alert.id,
      level: alert.escalation_level + 1,
      channels: level.channels
    )
    
    # Send escalation notifications
    send_escalation_notifications(alert, level, notification_channels)
    
    %{alert |
      escalation_level: alert.escalation_level + 1,
      escalated_at: DateTime.utc_now(),
      channels_notified: alert.channels_notified ++ level.channels
    }
  end
  
  defp send_initial_notifications(alert, rule, notification_channels) do
    channels = if rule, do: rule.notification_channels, else: [:console]
    
    Enum.each(channels, fn channel ->
      send_notification(channel, alert, notification_channels)
    end)
  end
  
  defp send_escalation_notifications(alert, level, notification_channels) do
    Enum.each(level.channels, fn channel ->
      send_notification(channel, alert, notification_channels)
    end)
  end
  
  defp send_notification(channel, alert, notification_channels) do
    case Map.get(notification_channels, channel) do
      nil ->
        Logger.warning("Unknown notification channel: #{channel}")
      
      channel_config ->
        send_to_channel(channel, alert, channel_config)
    end
  end
  
  defp send_to_channel(:console, alert, _config) do
    Logger.warning("ALERT: #{alert.title}", alert: alert)
  end
  
  defp send_to_channel(:slack, alert, config) do
    # Slack integration
    message = format_slack_message(alert)
    
    # In a real implementation, you'd use the Slack API
    Logger.info("Sending Slack alert", 
      channel: config.channel,
      message: message
    )
    
    # Example: HTTPoison.post(config.webhook_url, Jason.encode!(message))
  end
  
  defp send_to_channel(:email, alert, config) do
    # Email integration
    Logger.info("Sending email alert",
      to: config.recipients,
      subject: "Arsenal Alert: #{alert.title}"
    )
    
    # Example: YourMailer.send_alert_email(config.recipients, alert)
  end
  
  defp send_to_channel(:pagerduty, alert, config) do
    # PagerDuty integration
    Logger.info("Sending PagerDuty alert",
      service_key: config.service_key,
      alert_id: alert.id
    )
    
    # Example: PagerDuty.create_incident(config.service_key, alert)
  end
  
  defp send_to_channel(channel, alert, config) do
    Logger.warning("Unknown notification channel type: #{channel}")
  end
  
  # Configuration and defaults
  
  defp default_alert_rules do
    [
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
        notification_channels: [:console, :slack]
      },
      
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
        notification_channels: [:console, :slack, :pagerduty]
      },
      
      %{
        name: "Process Restart Storm",
        event_types: [:restart],
        alert_type: :restart_storm,
        severity: :high,
        conditions: [
          {:field_greater_than, [:restart_count], 5}
        ],
        title_template: "Process Restart Storm: {{child_id}}",
        description_template: "Process {{child_id}} has restarted {{restart_count}} times",
        notification_channels: [:console, :slack]
      },
      
      %{
        name: "System Health Critical",
        event_types: [:health_alert],
        alert_type: :system_critical,
        severity: :critical,
        conditions: [
          {:field_equals, [:overall_status], :critical}
        ],
        title_template: "System Health Critical",
        description_template: "Overall system health status is critical",
        notification_channels: [:console, :slack, :pagerduty, :email]
      }
    ]
  end
  
  defp default_escalation_policies do
    %{
      critical: %{
        levels: [
          %{delay_minutes: 0, channels: [:slack]},
          %{delay_minutes: 5, channels: [:pagerduty]},
          %{delay_minutes: 15, channels: [:email]}
        ]
      },
      high: %{
        levels: [
          %{delay_minutes: 0, channels: [:slack]},
          %{delay_minutes: 10, channels: [:email]}
        ]
      },
      warning: %{
        levels: [
          %{delay_minutes: 0, channels: [:slack]}
        ]
      }
    }
  end
  
  defp default_suppression_rules do
    [
      # Don't send duplicate alerts within 5 minutes
      %{
        type: :time_based,
        duration_minutes: 5
      }
    ]
  end
  
  defp configure_notification_channels(opts) do
    %{
      console: %{},
      slack: %{
        webhook_url: Keyword.get(opts, :slack_webhook),
        channel: Keyword.get(opts, :slack_channel, "#alerts")
      },
      email: %{
        recipients: Keyword.get(opts, :email_recipients, [])
      },
      pagerduty: %{
        service_key: Keyword.get(opts, :pagerduty_service_key)
      }
    }
  end
  
  # Helper functions
  
  defp generate_alert_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp generate_fingerprint(rule, event_data) do
    data = %{rule_name: rule.name, data: event_data}
    :crypto.hash(:sha256, :erlang.term_to_binary(data))
    |> Base.encode16(case: :lower)
  end
  
  defp get_nested_field(data, field_path) when is_list(field_path) do
    Enum.reduce(field_path, data, fn key, acc ->
      case acc do
        %{} -> Map.get(acc, key)
        _ -> nil
      end
    end)
  end
  
  defp render_template(template, data) do
    # Simple template rendering - in production you'd use a proper template engine
    String.replace(template, ~r/\{\{([^}]+)\}\}/, fn _, path ->
      field_path = String.split(path, ".") |> Enum.map(&String.to_atom/1)
      case get_nested_field(data, field_path) do
        nil -> "N/A"
        value -> to_string(value)
      end
    end)
  end
  
  defp should_suppress_alert?(existing_alert, rule, state) do
    suppression_rules = state.suppression_rules
    
    Enum.any?(suppression_rules, fn suppression_rule ->
      case suppression_rule.type do
        :time_based ->
          minutes_since = DateTime.diff(DateTime.utc_now(), existing_alert.triggered_at, :minute)
          minutes_since < suppression_rule.duration_minutes
        
        _ ->
          false
      end
    end)
  end
  
  defp evaluate_health_alerts(health, rules) do
    # Evaluate health data against rules that don't require events
    []
  end
  
  defp get_escalation_policy(severity, policies) do
    Map.get(policies, severity)
  end
  
  defp format_slack_message(alert) do
    color = case alert.severity do
      :critical -> "danger"
      :high -> "warning"
      :warning -> "warning"
      _ -> "good"
    end
    
    %{
      text: "Arsenal Alert: #{alert.title}",
      attachments: [
        %{
          color: color,
          fields: [
            %{title: "Severity", value: alert.severity, short: true},
            %{title: "Type", value: alert.type, short: true},
            %{title: "Time", value: DateTime.to_iso8601(alert.triggered_at), short: true},
            %{title: "Description", value: alert.description, short: false}
          ]
        }
      ]
    }
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, 30_000)
  end
  
  defp schedule_escalation_check do
    Process.send_after(self(), :escalation_check, 60_000)
  end
end