defmodule Arsenal.AnalyticsServer do
  @moduledoc """
  Arsenal.AnalyticsServer provides production-grade monitoring and analytics for OTP systems.

  This GenServer continuously monitors system health, tracks supervisor restarts,
  collects performance metrics, and provides real-time event notifications.
  It maintains historical data for trend analysis and anomaly detection.
  """

  use GenServer
  require Logger

  @type restart_event :: %{
          supervisor: pid() | atom(),
          child_id: term(),
          reason: term(),
          timestamp: DateTime.t(),
          restart_count: non_neg_integer(),
          child_pid: pid() | nil
        }

  @type restart_statistics :: %{
          total_restarts: non_neg_integer(),
          restart_rate: float(),
          most_restarted_children: [%{child_id: term(), count: non_neg_integer()}],
          restart_reasons: %{atom() => non_neg_integer()},
          time_between_restarts: [non_neg_integer()],
          patterns: [%{pattern: String.t(), frequency: non_neg_integer()}]
        }

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

  @type historical_data :: %{
          time_range: %{start: DateTime.t(), end: DateTime.t()},
          metrics: [performance_metrics()],
          restarts: [restart_event()],
          health_checks: [system_health()],
          events: [map()]
        }

  @type event_subscription :: %{
          subscriber: pid(),
          event_types: [atom()],
          filter: (map() -> boolean()) | nil
        }

  # State structure
  defstruct [
    :restart_history,
    :performance_history,
    :health_history,
    :event_subscriptions,
    :monitoring_interval,
    :retention_period,
    :last_health_check,
    :anomaly_thresholds,
    :baseline_metrics
  ]

  # Default configuration
  # 5 seconds
  @default_monitoring_interval 5_000
  # 24 hours in milliseconds
  @default_retention_period 86_400_000
  # Standard deviations from baseline
  @default_anomaly_threshold 2.0
  @max_history_size 1000
  @health_check_timeout 5_000

  ## Public API

  @doc """
  Starts the AnalyticsServer with optional configuration.

  ## Options

    * `:monitoring_interval` - How often to collect metrics (default: 5000ms)
    * `:retention_period` - How long to keep historical data (default: 24 hours)
    * `:anomaly_threshold` - Threshold for anomaly detection (default: 2.0 std devs)

  ## Examples

      iex> {:ok, pid} = Arsenal.AnalyticsServer.start_link()
      iex> is_pid(pid)
      true
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Tracks a supervisor restart event for analysis and statistics.

  ## Examples

      iex> :ok = Arsenal.AnalyticsServer.track_restart(:my_supervisor, :worker_1, :normal)
      :ok
  """
  @spec track_restart(pid() | atom(), term(), term()) :: :ok
  def track_restart(supervisor, child_id, reason) do
    GenServer.cast(__MODULE__, {:track_restart, supervisor, child_id, reason})
  end

  @doc """
  Gets comprehensive restart statistics for a supervisor or the entire system.

  ## Examples

      iex> {:ok, stats} = Arsenal.AnalyticsServer.get_restart_statistics()
      iex> Map.has_key?(stats, :total_restarts)
      true
  """
  @spec get_restart_statistics(pid() | atom() | :all) ::
          {:ok, restart_statistics()} | {:error, term()}
  def get_restart_statistics(supervisor \\ :all) do
    GenServer.call(__MODULE__, {:get_restart_statistics, supervisor})
  end

  @doc """
  Gets comprehensive system health assessment.

  ## Examples

      iex> {:ok, health} = Arsenal.AnalyticsServer.get_system_health()
      iex> health.overall_status in [:healthy, :warning, :critical]
      true
  """
  @spec get_system_health() :: {:ok, system_health()} | {:error, term()}
  def get_system_health do
    GenServer.call(__MODULE__, :get_system_health, @health_check_timeout)
  end

  @doc """
  Gets current performance metrics for CPU, memory, and processes.

  ## Examples

      iex> {:ok, metrics} = Arsenal.AnalyticsServer.get_performance_metrics()
      iex> Map.has_key?(metrics, :cpu)
      true
  """
  @spec get_performance_metrics() :: {:ok, performance_metrics()} | {:error, term()}
  def get_performance_metrics do
    GenServer.call(__MODULE__, :get_performance_metrics)
  end

  @doc """
  Subscribes to real-time events with optional filtering.

  ## Event Types

    * `:restart` - Supervisor restart events
    * `:health_alert` - System health alerts
    * `:performance_alert` - Performance threshold alerts
    * `:anomaly` - Detected anomalies
    * `:all` - All event types

  ## Examples

      iex> :ok = Arsenal.AnalyticsServer.subscribe_to_events([:restart, :health_alert])
      :ok
  """
  @spec subscribe_to_events([atom()], (map() -> boolean()) | nil) :: :ok
  def subscribe_to_events(event_types, filter \\ nil) do
    GenServer.call(__MODULE__, {:subscribe_to_events, self(), event_types, filter})
  end

  @doc """
  Unsubscribes from event notifications.

  ## Examples

      iex> :ok = Arsenal.AnalyticsServer.unsubscribe_from_events()
      :ok
  """
  @spec unsubscribe_from_events() :: :ok
  def unsubscribe_from_events do
    GenServer.call(__MODULE__, {:unsubscribe_from_events, self()})
  end

  @doc """
  Gets historical data for a specified time range.

  ## Examples

      iex> start_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      iex> end_time = DateTime.utc_now()
      iex> {:ok, data} = Arsenal.AnalyticsServer.get_historical_data(start_time, end_time)
      iex> Map.has_key?(data, :metrics)
      true
  """
  @spec get_historical_data(DateTime.t(), DateTime.t()) ::
          {:ok, historical_data()} | {:error, term()}
  def get_historical_data(start_time, end_time) do
    GenServer.call(__MODULE__, {:get_historical_data, start_time, end_time})
  end

  @doc """
  Forces an immediate health check and metric collection.

  ## Examples

      iex> :ok = Arsenal.AnalyticsServer.force_health_check()
      :ok
  """
  @spec force_health_check() :: :ok
  def force_health_check do
    GenServer.cast(__MODULE__, :force_health_check)
  end

  @doc """
  Gets current server statistics and configuration.

  ## Examples

      iex> {:ok, stats} = Arsenal.AnalyticsServer.get_server_stats()
      iex> Map.has_key?(stats, :uptime)
      true
  """
  @spec get_server_stats() :: {:ok, map()}
  def get_server_stats do
    GenServer.call(__MODULE__, :get_server_stats)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    monitoring_interval = Keyword.get(opts, :monitoring_interval, @default_monitoring_interval)
    retention_period = Keyword.get(opts, :retention_period, @default_retention_period)
    anomaly_threshold = Keyword.get(opts, :anomaly_threshold, @default_anomaly_threshold)

    state = %__MODULE__{
      restart_history: [],
      performance_history: [],
      health_history: [],
      event_subscriptions: [],
      monitoring_interval: monitoring_interval,
      retention_period: retention_period,
      last_health_check: nil,
      anomaly_thresholds: %{
        cpu_usage: anomaly_threshold,
        memory_usage: anomaly_threshold,
        restart_rate: anomaly_threshold
      },
      baseline_metrics: nil
    }

    # Schedule initial health check and start monitoring
    schedule_health_check(0)
    schedule_cleanup()

    Logger.info(
      "Arsenal.AnalyticsServer started with monitoring interval: #{monitoring_interval}ms"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:get_restart_statistics, supervisor}, _from, state) do
    stats = calculate_restart_statistics(state.restart_history, supervisor)
    {:reply, {:ok, stats}, state}
  end

  def handle_call(:get_system_health, _from, state) do
    case perform_health_check(state) do
      {:ok, health, new_state} ->
        {:reply, {:ok, health}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_performance_metrics, _from, state) do
    case collect_performance_metrics() do
      {:ok, metrics} ->
        {:reply, {:ok, metrics}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:subscribe_to_events, subscriber, event_types, filter}, _from, state) do
    subscription = %{
      subscriber: subscriber,
      event_types: event_types,
      filter: filter
    }

    # Monitor the subscriber to clean up when it dies
    Process.monitor(subscriber)

    new_subscriptions = [subscription | state.event_subscriptions]
    new_state = %{state | event_subscriptions: new_subscriptions}

    {:reply, :ok, new_state}
  end

  def handle_call({:unsubscribe_from_events, subscriber}, _from, state) do
    new_subscriptions =
      Enum.reject(state.event_subscriptions, fn sub ->
        sub.subscriber == subscriber
      end)

    new_state = %{state | event_subscriptions: new_subscriptions}
    {:reply, :ok, new_state}
  end

  def handle_call({:get_historical_data, start_time, end_time}, _from, state) do
    data = extract_historical_data(state, start_time, end_time)
    {:reply, {:ok, data}, state}
  end

  def handle_call(:get_server_stats, _from, state) do
    stats = %{
      uptime: get_uptime(),
      restart_events_tracked: length(state.restart_history),
      performance_samples: length(state.performance_history),
      health_checks: length(state.health_history),
      active_subscriptions: length(state.event_subscriptions),
      monitoring_interval: state.monitoring_interval,
      retention_period: state.retention_period,
      last_health_check: state.last_health_check
    }

    {:reply, {:ok, stats}, state}
  end

  # Handle Supertester sync messages
  def handle_call(:__supertester_sync__, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:track_restart, supervisor, child_id, reason}, state) do
    restart_event = %{
      supervisor: supervisor,
      child_id: child_id,
      reason: reason,
      timestamp: DateTime.utc_now(),
      restart_count: count_previous_restarts(state.restart_history, supervisor, child_id) + 1,
      child_pid: get_child_pid(supervisor, child_id)
    }

    new_history =
      [restart_event | state.restart_history]
      |> Enum.take(@max_history_size)

    new_state = %{state | restart_history: new_history}

    # Notify subscribers
    notify_subscribers(new_state, :restart, restart_event)

    # Check if this indicates a problem
    check_restart_anomalies(new_state, restart_event)

    {:noreply, new_state}
  end

  def handle_cast(:force_health_check, state) do
    case perform_health_check(state) do
      {:ok, _health, new_state} ->
        {:noreply, new_state}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:health_check, state) do
    case perform_health_check(state) do
      {:ok, _health, new_state} ->
        schedule_health_check(new_state.monitoring_interval)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Health check failed: #{inspect(reason)}")
        schedule_health_check(state.monitoring_interval)
        {:noreply, state}
    end
  end

  def handle_info(:cleanup, state) do
    new_state = cleanup_old_data(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up subscriptions for dead processes
    new_subscriptions =
      Enum.reject(state.event_subscriptions, fn sub ->
        sub.subscriber == pid
      end)

    new_state = %{state | event_subscriptions: new_subscriptions}
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("Arsenal.AnalyticsServer received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_health_check(delay) do
    Process.send_after(self(), :health_check, delay)
  end

  defp schedule_cleanup do
    # Clean up old data every hour
    Process.send_after(self(), :cleanup, 3_600_000)
  end

  defp perform_health_check(state) do
    try do
      # Collect current metrics
      case collect_performance_metrics() do
        {:ok, metrics} ->
          # Analyze system health
          health = analyze_system_health(metrics, state)

          # Update state with new data
          new_performance_history =
            [metrics | state.performance_history]
            |> Enum.take(@max_history_size)

          new_health_history =
            [health | state.health_history]
            |> Enum.take(@max_history_size)

          new_state = %{
            state
            | performance_history: new_performance_history,
              health_history: new_health_history,
              last_health_check: DateTime.utc_now(),
              baseline_metrics: update_baseline_metrics(state.baseline_metrics, metrics)
          }

          # Notify subscribers if there are alerts
          if health.overall_status != :healthy do
            notify_subscribers(new_state, :health_alert, health)
          end

          # Check for anomalies
          check_performance_anomalies(new_state, metrics)

          {:ok, health, new_state}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Health check failed with error: #{inspect(error)}")
        {:error, {:health_check_failed, error}}
    end
  end

  defp collect_performance_metrics do
    try do
      # Get memory information
      memory_info = :erlang.memory()

      # Get system information
      process_count = :erlang.system_info(:process_count)
      process_limit = :erlang.system_info(:process_limit)

      # Get scheduler utilization (requires some time to measure)
      scheduler_usage = get_scheduler_utilization()

      # Get I/O statistics
      {{:input, input}, {:output, output}} = :erlang.statistics(:io)

      # Get garbage collection statistics
      {gc_collections, gc_words, gc_time} = :erlang.statistics(:garbage_collection)

      # Calculate memory usage safely
      total_memory = memory_info[:total] || 0
      available_memory = memory_info[:available] || 0
      used_memory = if available_memory > 0, do: total_memory - available_memory, else: 0

      metrics = %{
        cpu: %{
          utilization: calculate_cpu_utilization(),
          load_average: get_load_average(),
          scheduler_utilization: scheduler_usage
        },
        memory: %{
          total: total_memory,
          used: used_memory,
          available: available_memory,
          processes: memory_info[:processes] || 0,
          system: memory_info[:system] || 0
        },
        processes: %{
          count: process_count,
          limit: process_limit,
          utilization: process_count / process_limit * 100,
          runnable: count_runnable_processes(),
          running: count_running_processes()
        },
        io: %{
          input: input,
          output: output
        },
        gc: %{
          collections: gc_collections,
          words_reclaimed: gc_words,
          time_spent: gc_time
        },
        timestamp: DateTime.utc_now()
      }

      {:ok, metrics}
    rescue
      error ->
        Logger.error("Failed to collect performance metrics: #{inspect(error)}")
        {:error, {:metrics_collection_failed, error}}
    end
  end

  defp analyze_system_health(metrics, state) do
    # Calculate overall health status
    health_indicators = [
      check_memory_health(metrics.memory),
      check_process_health(metrics.processes),
      check_cpu_health(metrics.cpu),
      check_restart_health(state.restart_history)
    ]

    overall_status = determine_overall_status(health_indicators)

    # Get message queue analysis
    message_queue_analysis = analyze_message_queues()

    # Detect anomalies
    anomalies = detect_anomalies(metrics, state)

    # Generate recommendations
    recommendations = generate_recommendations(metrics, state, anomalies)

    %{
      overall_status: overall_status,
      process_count: metrics.processes.count,
      memory_usage: %{
        total: metrics.memory.total,
        processes: metrics.memory.processes,
        system: metrics.memory.system,
        atom: :erlang.memory(:atom),
        binary: :erlang.memory(:binary),
        code: :erlang.memory(:code),
        ets: :erlang.memory(:ets)
      },
      cpu_usage: metrics.cpu.utilization,
      restart_rate: calculate_recent_restart_rate(state.restart_history),
      message_queue_lengths: message_queue_analysis,
      anomalies: anomalies,
      recommendations: recommendations,
      last_check: DateTime.utc_now()
    }
  end

  defp check_memory_health(memory) do
    utilization = memory.used / memory.total * 100

    cond do
      utilization > 90 -> :critical
      utilization > 75 -> :warning
      true -> :healthy
    end
  end

  defp check_process_health(processes) do
    cond do
      processes.utilization > 90 -> :critical
      processes.utilization > 75 -> :warning
      true -> :healthy
    end
  end

  defp check_cpu_health(cpu) do
    cond do
      cpu.utilization > 90 -> :critical
      cpu.utilization > 75 -> :warning
      true -> :healthy
    end
  end

  defp check_restart_health(restart_history) do
    # 5 minutes
    recent_restarts = count_recent_restarts(restart_history, 300_000)

    cond do
      recent_restarts > 10 -> :critical
      recent_restarts > 5 -> :warning
      true -> :healthy
    end
  end

  defp determine_overall_status(indicators) do
    cond do
      Enum.any?(indicators, &(&1 == :critical)) -> :critical
      Enum.any?(indicators, &(&1 == :warning)) -> :warning
      true -> :healthy
    end
  end

  defp analyze_message_queues do
    processes = Process.list()

    queue_lengths =
      Enum.map(processes, fn pid ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, len} -> len
          nil -> 0
        end
      end)

    max_queue = Enum.max(queue_lengths, fn -> 0 end)

    avg_queue =
      if length(queue_lengths) > 0 do
        Enum.sum(queue_lengths) / length(queue_lengths)
      else
        0.0
      end

    long_queues = Enum.count(queue_lengths, &(&1 > 100))

    %{
      max: max_queue,
      average: avg_queue,
      processes_with_long_queues: long_queues
    }
  end

  defp detect_anomalies(current_metrics, state) do
    case state.baseline_metrics do
      nil ->
        []

      baseline ->
        anomalies = []

        # Check CPU anomalies
        anomalies =
          check_cpu_anomalies(
            current_metrics.cpu,
            baseline.cpu,
            state.anomaly_thresholds.cpu_usage,
            anomalies
          )

        # Check memory anomalies
        anomalies =
          check_memory_anomalies(
            current_metrics.memory,
            baseline.memory,
            state.anomaly_thresholds.memory_usage,
            anomalies
          )

        # Check process count anomalies
        check_process_anomalies(
          current_metrics.processes,
          baseline.processes,
          state.anomaly_thresholds.cpu_usage,
          anomalies
        )
    end
  end

  defp check_cpu_anomalies(current_cpu, baseline_cpu, threshold, anomalies) do
    if abs(current_cpu.utilization - baseline_cpu.utilization) >
         baseline_cpu.utilization * threshold do
      severity =
        if current_cpu.utilization > baseline_cpu.utilization * 2, do: :high, else: :medium

      anomaly = %{
        type: :cpu_anomaly,
        severity: severity,
        description: "CPU utilization significantly different from baseline",
        current_value: current_cpu.utilization,
        baseline_value: baseline_cpu.utilization,
        timestamp: DateTime.utc_now()
      }

      [anomaly | anomalies]
    else
      anomalies
    end
  end

  defp check_memory_anomalies(current_memory, baseline_memory, threshold, anomalies) do
    current_usage = current_memory.used / current_memory.total
    baseline_usage = baseline_memory.used / baseline_memory.total

    if abs(current_usage - baseline_usage) > baseline_usage * threshold do
      severity = if current_usage > baseline_usage * 1.5, do: :high, else: :medium

      anomaly = %{
        type: :memory_anomaly,
        severity: severity,
        description: "Memory usage significantly different from baseline",
        current_value: current_usage * 100,
        baseline_value: baseline_usage * 100,
        timestamp: DateTime.utc_now()
      }

      [anomaly | anomalies]
    else
      anomalies
    end
  end

  defp check_process_anomalies(current_processes, baseline_processes, threshold, anomalies) do
    if abs(current_processes.count - baseline_processes.count) >
         baseline_processes.count * threshold do
      anomaly = %{
        type: :process_count_anomaly,
        severity: :medium,
        description: "Process count significantly different from baseline",
        current_value: current_processes.count,
        baseline_value: baseline_processes.count,
        timestamp: DateTime.utc_now()
      }

      [anomaly | anomalies]
    else
      anomalies
    end
  end

  defp generate_recommendations(metrics, state, anomalies) do
    recommendations = []

    # Memory recommendations
    memory_usage = metrics.memory.used / metrics.memory.total * 100

    recommendations =
      if memory_usage > 80 do
        [
          "Consider reducing memory usage - current utilization: #{Float.round(memory_usage, 2)}%"
          | recommendations
        ]
      else
        recommendations
      end

    # Process recommendations
    recommendations =
      if metrics.processes.utilization > 80 do
        ["High process count detected - consider process pooling or cleanup" | recommendations]
      else
        recommendations
      end

    # Restart recommendations
    recent_restart_rate = calculate_recent_restart_rate(state.restart_history)

    recommendations =
      if recent_restart_rate > 0.1 do
        ["High restart rate detected - investigate supervisor configurations" | recommendations]
      else
        recommendations
      end

    # Anomaly-based recommendations
    anomaly_recommendations =
      Enum.map(anomalies, fn anomaly ->
        case anomaly.type do
          :cpu_anomaly -> "Investigate CPU usage spike - check for runaway processes"
          :memory_anomaly -> "Monitor memory usage - potential memory leak detected"
          :process_count_anomaly -> "Unusual process count change - verify system stability"
          _ -> "Investigate detected anomaly: #{anomaly.description}"
        end
      end)

    recommendations ++ anomaly_recommendations
  end

  defp calculate_restart_statistics(restart_history, supervisor) do
    filtered_history =
      case supervisor do
        :all -> restart_history
        sup -> Enum.filter(restart_history, &(&1.supervisor == sup))
      end

    total_restarts = length(filtered_history)

    # Calculate restart rate (restarts per hour)
    now = DateTime.utc_now()
    one_hour_ago = DateTime.add(now, -3600, :second)

    recent_restarts =
      Enum.count(filtered_history, fn event ->
        DateTime.compare(event.timestamp, one_hour_ago) == :gt
      end)

    # per hour
    restart_rate = recent_restarts / 1.0

    # Most restarted children
    child_restart_counts =
      filtered_history
      |> Enum.group_by(& &1.child_id)
      |> Enum.map(fn {child_id, events} -> %{child_id: child_id, count: length(events)} end)
      |> Enum.sort_by(& &1.count, :desc)
      |> Enum.take(10)

    # Restart reasons
    restart_reasons =
      filtered_history
      |> Enum.group_by(& &1.reason)
      |> Enum.map(fn {reason, events} -> {reason, length(events)} end)
      |> Enum.into(%{})

    # Time between restarts
    time_between_restarts =
      filtered_history
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [newer, older] ->
        DateTime.diff(newer.timestamp, older.timestamp, :millisecond)
      end)

    # Detect patterns (simplified)
    patterns = detect_restart_patterns(filtered_history)

    %{
      total_restarts: total_restarts,
      restart_rate: restart_rate,
      most_restarted_children: child_restart_counts,
      restart_reasons: restart_reasons,
      time_between_restarts: time_between_restarts,
      patterns: patterns
    }
  end

  defp detect_restart_patterns(restart_history) do
    # Simple pattern detection - look for recurring restart sequences
    # This is a simplified implementation
    restart_history
    |> Enum.group_by(& &1.child_id)
    |> Enum.filter(fn {_child_id, events} -> length(events) > 2 end)
    |> Enum.map(fn {child_id, events} ->
      frequency = length(events)

      %{
        pattern: "Recurring restarts for #{inspect(child_id)}",
        frequency: frequency
      }
    end)
    |> Enum.sort_by(& &1.frequency, :desc)
    |> Enum.take(5)
  end

  defp extract_historical_data(state, start_time, end_time) do
    # Filter data by time range
    filtered_metrics =
      Enum.filter(state.performance_history, fn metrics ->
        DateTime.compare(metrics.timestamp, start_time) != :lt and
          DateTime.compare(metrics.timestamp, end_time) != :gt
      end)

    filtered_restarts =
      Enum.filter(state.restart_history, fn event ->
        DateTime.compare(event.timestamp, start_time) != :lt and
          DateTime.compare(event.timestamp, end_time) != :gt
      end)

    filtered_health =
      Enum.filter(state.health_history, fn health ->
        DateTime.compare(health.last_check, start_time) != :lt and
          DateTime.compare(health.last_check, end_time) != :gt
      end)

    %{
      time_range: %{start: start_time, end: end_time},
      metrics: Enum.reverse(filtered_metrics),
      restarts: Enum.reverse(filtered_restarts),
      health_checks: Enum.reverse(filtered_health),
      # Could be extended to include other events
      events: []
    }
  end

  defp notify_subscribers(state, event_type, event_data) do
    matching_subscriptions =
      Enum.filter(state.event_subscriptions, fn subscription ->
        (event_type in subscription.event_types or :all in subscription.event_types) and
          (subscription.filter == nil or subscription.filter.(event_data))
      end)

    Enum.each(matching_subscriptions, fn subscription ->
      send(subscription.subscriber, {:arsenal_analytics_event, event_type, event_data})
    end)
  end

  defp check_restart_anomalies(state, restart_event) do
    # Check if this restart indicates an anomaly
    recent_restarts_for_child =
      Enum.count(state.restart_history, fn event ->
        # 5 minutes
        event.child_id == restart_event.child_id and
          event.supervisor == restart_event.supervisor and
          DateTime.diff(restart_event.timestamp, event.timestamp, :second) < 300
      end)

    if recent_restarts_for_child > 3 do
      anomaly = %{
        type: :restart_anomaly,
        severity: :high,
        description: "Rapid restart cycle detected for #{inspect(restart_event.child_id)}",
        child_id: restart_event.child_id,
        supervisor: restart_event.supervisor,
        restart_count: recent_restarts_for_child,
        timestamp: DateTime.utc_now()
      }

      notify_subscribers(state, :anomaly, anomaly)
    end
  end

  defp check_performance_anomalies(state, metrics) do
    anomalies = detect_anomalies(metrics, state)

    Enum.each(anomalies, fn anomaly ->
      if anomaly.severity == :high do
        notify_subscribers(state, :performance_alert, anomaly)
      end
    end)
  end

  defp cleanup_old_data(state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -state.retention_period, :millisecond)

    new_restart_history =
      Enum.filter(state.restart_history, fn event ->
        DateTime.compare(event.timestamp, cutoff_time) == :gt
      end)

    new_performance_history =
      Enum.filter(state.performance_history, fn metrics ->
        DateTime.compare(metrics.timestamp, cutoff_time) == :gt
      end)

    new_health_history =
      Enum.filter(state.health_history, fn health ->
        DateTime.compare(health.last_check, cutoff_time) == :gt
      end)

    %{
      state
      | restart_history: new_restart_history,
        performance_history: new_performance_history,
        health_history: new_health_history
    }
  end

  defp update_baseline_metrics(nil, current_metrics) do
    current_metrics
  end

  defp update_baseline_metrics(baseline, current_metrics) do
    # Simple exponential moving average for baseline
    alpha = 0.1

    %{
      cpu: %{
        utilization:
          alpha * current_metrics.cpu.utilization + (1 - alpha) * baseline.cpu.utilization
      },
      memory: %{
        total: current_metrics.memory.total,
        used: alpha * current_metrics.memory.used + (1 - alpha) * baseline.memory.used,
        available:
          alpha * current_metrics.memory.available + (1 - alpha) * baseline.memory.available,
        processes:
          alpha * current_metrics.memory.processes + (1 - alpha) * baseline.memory.processes,
        system: alpha * current_metrics.memory.system + (1 - alpha) * baseline.memory.system
      },
      processes: %{
        count: alpha * current_metrics.processes.count + (1 - alpha) * baseline.processes.count,
        limit: current_metrics.processes.limit,
        utilization:
          alpha * current_metrics.processes.utilization +
            (1 - alpha) * baseline.processes.utilization,
        runnable:
          alpha * current_metrics.processes.runnable + (1 - alpha) * baseline.processes.runnable,
        running:
          alpha * current_metrics.processes.running + (1 - alpha) * baseline.processes.running
      },
      timestamp: current_metrics.timestamp
    }
  end

  # Helper functions for system metrics

  defp get_scheduler_utilization do
    try do
      # Use scheduler wall time statistics if available
      case :erlang.statistics(:scheduler_wall_time) do
        :undefined ->
          # Enable scheduler wall time tracking and try again
          :erlang.system_flag(:scheduler_wall_time, true)

          case :erlang.statistics(:scheduler_wall_time) do
            :undefined -> [0.0]
            schedulers -> calculate_scheduler_utilization(schedulers)
          end

        schedulers ->
          calculate_scheduler_utilization(schedulers)
      end
    rescue
      _ -> [0.0]
    end
  end

  defp calculate_scheduler_utilization(schedulers) do
    # Calculate utilization as a percentage
    Enum.map(schedulers, fn {_id, active_time, total_time} ->
      if total_time > 0 do
        active_time / total_time * 100
      else
        0.0
      end
    end)
  end

  defp calculate_cpu_utilization do
    try do
      # Use scheduler utilization as a proxy for CPU utilization
      scheduler_utils = get_scheduler_utilization()

      if length(scheduler_utils) > 0 do
        Enum.sum(scheduler_utils) / length(scheduler_utils)
      else
        0.0
      end
    rescue
      _ -> 0.0
    end
  end

  defp get_load_average do
    try do
      # Load average is not directly available in standard Erlang
      # Use a simple approximation based on process count vs scheduler count
      process_count = :erlang.system_info(:process_count)
      scheduler_count = :erlang.system_info(:schedulers)

      load_approximation = process_count / scheduler_count
      # Return same value for 1, 5, and 15 minute averages as approximation
      [load_approximation, load_approximation, load_approximation]
    rescue
      _ -> [0.0, 0.0, 0.0]
    end
  end

  defp count_runnable_processes do
    Process.list()
    |> Enum.count(fn pid ->
      case Process.info(pid, :status) do
        {:status, :runnable} -> true
        _ -> false
      end
    end)
  end

  defp count_running_processes do
    Process.list()
    |> Enum.count(fn pid ->
      case Process.info(pid, :status) do
        {:status, :running} -> true
        _ -> false
      end
    end)
  end

  defp count_previous_restarts(restart_history, supervisor, child_id) do
    Enum.count(restart_history, fn event ->
      event.supervisor == supervisor and event.child_id == child_id
    end)
  end

  defp get_child_pid(supervisor, child_id) do
    try do
      # Only try to get child info if supervisor is actually a pid or registered process
      supervisor_pid =
        case supervisor do
          pid when is_pid(pid) ->
            if Process.alive?(pid), do: pid, else: nil

          atom when is_atom(atom) ->
            Process.whereis(atom)

          _ ->
            nil
        end

      case supervisor_pid do
        nil ->
          nil

        pid ->
          case Supervisor.which_children(pid) do
            children when is_list(children) ->
              case Enum.find(children, fn {id, _pid, _type, _modules} -> id == child_id end) do
                {_id, child_pid, _type, _modules} when is_pid(child_pid) -> child_pid
                {_id, :restarting, _type, _modules} -> nil
                {_id, :undefined, _type, _modules} -> nil
                nil -> nil
              end
          end
      end
    rescue
      _ -> nil
    end
  end

  defp calculate_recent_restart_rate(restart_history) do
    now = DateTime.utc_now()
    one_hour_ago = DateTime.add(now, -3600, :second)

    recent_restarts =
      Enum.count(restart_history, fn event ->
        DateTime.compare(event.timestamp, one_hour_ago) == :gt
      end)

    # per hour
    recent_restarts / 1.0
  end

  defp count_recent_restarts(restart_history, milliseconds_ago) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -milliseconds_ago, :millisecond)

    Enum.count(restart_history, fn event ->
      DateTime.compare(event.timestamp, cutoff_time) == :gt
    end)
  end

  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end
end
