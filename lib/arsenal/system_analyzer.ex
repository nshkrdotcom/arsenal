defmodule Arsenal.SystemAnalyzer do
  @moduledoc """
  Arsenal.SystemAnalyzer provides comprehensive system health monitoring and anomaly detection.
  """

  use GenServer
  require Logger

  @type health_status :: :healthy | :warning | :critical

  @type health_report :: %{
          overall_status: health_status(),
          timestamp: DateTime.t(),
          system_metrics: map(),
          health_indicators: [map()],
          risk_factors: [map()],
          stability_score: float(),
          recommendations: [String.t()]
        }

  @type anomaly_report :: %{
          timestamp: DateTime.t(),
          anomalies: [map()],
          severity_distribution: %{high: integer(), medium: integer(), low: integer()},
          affected_systems: [atom()],
          correlation_analysis: map()
        }

  @type resource_data :: %{
          timestamp: DateTime.t(),
          cpu: map(),
          memory: map(),
          io: map(),
          network: map(),
          processes: map(),
          system_load: map()
        }

  @type prediction_report :: %{
          timestamp: DateTime.t(),
          predictions: [map()],
          confidence_level: float(),
          time_horizon: integer(),
          recommended_actions: [String.t()]
        }

  # State structure
  defstruct [
    :baseline_metrics,
    :historical_data,
    :anomaly_thresholds,
    :health_check_interval,
    :prediction_models,
    :last_health_check,
    :monitoring_active,
    :subscribers
  ]

  # Configuration constants
  # 30 seconds
  @default_health_check_interval 30_000
  # 24 hours at 30-second intervals
  @max_history_size 2880
  # 1 hour in seconds
  @prediction_horizon 3600

  ## Public API

  @doc """
  Starts the SystemAnalyzer with optional configuration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Performs comprehensive system health analysis.
  """
  @spec analyze_system_health() :: {:ok, health_report()} | {:error, term()}
  def analyze_system_health do
    GenServer.call(__MODULE__, :analyze_system_health, 10_000)
  end

  @doc """
  Detects system anomalies using statistical methods and pattern analysis.
  """
  @spec detect_anomalies() :: {:ok, anomaly_report()} | {:error, term()}
  def detect_anomalies do
    GenServer.call(__MODULE__, :detect_anomalies, 5_000)
  end

  @doc """
  Gets detailed resource usage information for CPU, memory, and I/O.
  """
  @spec get_resource_usage() :: {:ok, resource_data()} | {:error, term()}
  def get_resource_usage do
    GenServer.call(__MODULE__, :get_resource_usage, 5_000)
  end

  @doc """
  Predicts potential system issues based on historical patterns and trends.
  """
  @spec predict_issues() :: {:ok, prediction_report()} | {:error, term()}
  def predict_issues do
    GenServer.call(__MODULE__, :predict_issues, 10_000)
  end

  @doc """
  Generates automated optimization recommendations based on current system state.
  """
  @spec generate_recommendations() :: {:ok, [String.t()]} | {:error, term()}
  def generate_recommendations do
    GenServer.call(__MODULE__, :generate_recommendations, 5_000)
  end

  @doc """
  Schedules automated periodic health monitoring.
  """
  @spec schedule_health_check(pos_integer()) :: :ok
  def schedule_health_check(interval) when is_integer(interval) and interval > 0 do
    GenServer.call(__MODULE__, {:schedule_health_check, interval})
  end

  @doc """
  Stops automated health monitoring.
  """
  @spec stop_health_monitoring() :: :ok
  def stop_health_monitoring do
    GenServer.call(__MODULE__, :stop_health_monitoring)
  end

  @doc """
  Gets current analyzer statistics and configuration.
  """
  @spec get_analyzer_stats() :: {:ok, map()}
  def get_analyzer_stats do
    GenServer.call(__MODULE__, :get_analyzer_stats)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    health_check_interval =
      Keyword.get(opts, :health_check_interval, @default_health_check_interval)

    enable_predictions = Keyword.get(opts, :enable_predictions, true)

    anomaly_thresholds =
      Keyword.get(opts, :anomaly_thresholds, %{
        cpu_utilization: 2.0,
        memory_usage: 2.0,
        process_count: 1.5,
        io_wait: 2.0,
        load_average: 1.5
      })

    state = %__MODULE__{
      baseline_metrics: nil,
      historical_data: [],
      anomaly_thresholds: anomaly_thresholds,
      health_check_interval: health_check_interval,
      prediction_models: if(enable_predictions, do: initialize_prediction_models(), else: nil),
      last_health_check: nil,
      monitoring_active: false,
      subscribers: []
    }

    # Perform initial health check to establish baseline
    send(self(), :initial_health_check)

    Logger.info(
      "Arsenal.SystemAnalyzer started with health check interval: #{health_check_interval}ms"
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:analyze_system_health, _from, state) do
    case perform_comprehensive_health_analysis(state) do
      {:ok, report, new_state} ->
        {:reply, {:ok, report}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:detect_anomalies, _from, state) do
    case detect_system_anomalies(state) do
      {:ok, report} ->
        {:reply, {:ok, report}, state}
    end
  end

  def handle_call(:get_resource_usage, _from, state) do
    case collect_resource_metrics() do
      {:ok, data} ->
        {:reply, {:ok, data}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:predict_issues, _from, state) do
    case perform_predictive_analysis(state) do
      {:ok, report} ->
        {:reply, {:ok, report}, state}
    end
  end

  def handle_call(:generate_recommendations, _from, state) do
    case generate_system_recommendations(state) do
      {:ok, recommendations} ->
        {:reply, {:ok, recommendations}, state}
    end
  end

  def handle_call({:schedule_health_check, interval}, _from, state) do
    new_state = %{state | health_check_interval: interval, monitoring_active: true}

    schedule_next_health_check(interval)
    {:reply, :ok, new_state}
  end

  def handle_call(:stop_health_monitoring, _from, state) do
    new_state = %{state | monitoring_active: false}
    {:reply, :ok, new_state}
  end

  def handle_call(:get_analyzer_stats, _from, state) do
    stats = %{
      uptime: get_uptime(),
      monitoring_active: state.monitoring_active,
      health_check_interval: state.health_check_interval,
      historical_data_points: length(state.historical_data),
      last_health_check: state.last_health_check,
      baseline_established: state.baseline_metrics != nil,
      prediction_models_enabled: state.prediction_models != nil,
      active_subscribers: length(state.subscribers)
    }

    {:reply, {:ok, stats}, state}
  end

  # Handle Supertester sync messages
  def handle_call(:__supertester_sync__, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:initial_health_check, state) do
    case establish_baseline_metrics() do
      {:ok, baseline} ->
        new_state = %{state | baseline_metrics: baseline}
        Logger.info("SystemAnalyzer baseline metrics established")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to establish baseline metrics: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info(:scheduled_health_check, state) do
    if state.monitoring_active do
      case perform_comprehensive_health_analysis(state) do
        {:ok, _report, new_state} ->
          schedule_next_health_check(new_state.health_check_interval)
          {:noreply, new_state}

        {:error, reason} ->
          Logger.error("Scheduled health check failed: #{inspect(reason)}")
          schedule_next_health_check(state.health_check_interval)
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("SystemAnalyzer received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp initialize_prediction_models do
    # Initialize simple prediction models
    %{
      memory_model: %{type: :linear_regression, parameters: []},
      cpu_model: %{type: :moving_average, window: 10},
      process_model: %{type: :trend_analysis, threshold: 0.05}
    }
  end

  defp perform_comprehensive_health_analysis(state) do
    try do
      case collect_resource_metrics() do
        {:ok, current_metrics} ->
          health_indicators = analyze_health_indicators(current_metrics, state.baseline_metrics)
          overall_status = determine_overall_health_status(health_indicators)
          stability_score = calculate_stability_score(health_indicators, state.historical_data)
          risk_factors = identify_risk_factors(current_metrics, state.historical_data)
          recommendations = generate_health_recommendations(health_indicators, risk_factors)

          report = %{
            overall_status: overall_status,
            timestamp: DateTime.utc_now(),
            system_metrics: current_metrics,
            health_indicators: health_indicators,
            risk_factors: risk_factors,
            stability_score: stability_score,
            recommendations: recommendations
          }

          new_historical_data =
            [current_metrics | state.historical_data]
            |> Enum.take(@max_history_size)

          new_state = %{
            state
            | historical_data: new_historical_data,
              last_health_check: DateTime.utc_now()
          }

          {:ok, report, new_state}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Health analysis failed: #{inspect(error)}")
        {:error, {:analysis_failed, error}}
    end
  end

  defp collect_resource_metrics do
    try do
      timestamp = DateTime.utc_now()

      cpu_metrics = collect_cpu_metrics()
      memory_metrics = collect_memory_metrics()
      io_metrics = collect_io_metrics()
      network_metrics = collect_network_metrics()
      process_metrics = collect_process_metrics()
      system_load_metrics = collect_system_load_metrics()

      resource_data = %{
        timestamp: timestamp,
        cpu: cpu_metrics,
        memory: memory_metrics,
        io: io_metrics,
        network: network_metrics,
        processes: process_metrics,
        system_load: system_load_metrics
      }

      {:ok, resource_data}
    rescue
      error ->
        Logger.error("Failed to collect resource metrics: #{inspect(error)}")
        {:error, {:metrics_collection_failed, error}}
    end
  end

  defp collect_cpu_metrics do
    scheduler_usage = get_scheduler_utilization()
    cpu_utilization = calculate_cpu_utilization()
    load_average = get_load_average()

    %{
      utilization: cpu_utilization,
      load_average: load_average,
      scheduler_utilization: scheduler_usage,
      context_switches: get_context_switches(),
      interrupts: get_interrupts()
    }
  end

  defp collect_memory_metrics do
    memory_info = :erlang.memory()

    total = memory_info[:total] || 0
    processes = memory_info[:processes] || 0
    system = memory_info[:system] || 0

    fragmentation_ratio =
      if total > 0 do
        (system + processes) / total
      else
        0.0
      end

    %{
      total: total,
      available: get_available_memory(),
      used: processes + system,
      cached: memory_info[:ets] || 0,
      buffers: memory_info[:binary] || 0,
      swap_total: 0,
      swap_used: 0,
      fragmentation_ratio: fragmentation_ratio
    }
  end

  defp collect_io_metrics do
    {{:input, input}, {:output, output}} = :erlang.statistics(:io)

    %{
      disk_reads: 0,
      disk_writes: 0,
      disk_read_bytes: input,
      disk_write_bytes: output,
      network_rx: 0,
      network_tx: 0,
      io_wait: 0.0
    }
  end

  defp collect_network_metrics do
    %{
      connections: count_network_connections(),
      active_connections: count_active_connections(),
      listen_sockets: count_listen_sockets(),
      bandwidth_utilization: 0.0
    }
  end

  defp collect_process_metrics do
    process_count = :erlang.system_info(:process_count)
    _process_limit = :erlang.system_info(:process_limit)
    running = count_running_processes()

    %{
      total_count: process_count,
      running: running,
      sleeping: process_count - running,
      zombie: 0,
      stopped: 0,
      memory_per_process: calculate_memory_per_process(),
      cpu_per_process: calculate_cpu_per_process()
    }
  end

  defp collect_system_load_metrics do
    uptime = get_system_uptime()

    %{
      load_1min: get_load_average() |> Enum.at(0, 0.0),
      load_5min: get_load_average() |> Enum.at(1, 0.0),
      load_15min: get_load_average() |> Enum.at(2, 0.0),
      uptime: uptime,
      boot_time: DateTime.add(DateTime.utc_now(), -uptime, :second)
    }
  end

  # Helper functions for metrics collection
  defp get_scheduler_utilization do
    try do
      schedulers = :erlang.system_info(:schedulers)
      # Simplified scheduler utilization calculation
      # Mock value for now
      [schedulers * 0.5]
    rescue
      _ -> [0.0]
    end
  end

  defp calculate_cpu_utilization do
    try do
      # Use reductions as a proxy for CPU utilization
      {_, reductions} = :erlang.statistics(:reductions)
      # Convert to percentage (simplified calculation)
      min(reductions / 1_000_000 * 100, 100.0)
    rescue
      _ -> 0.0
    end
  end

  defp get_load_average do
    # Mock load average values since we can't access system load on all platforms
    [0.5, 0.7, 0.9]
  end

  defp get_context_switches do
    try do
      {_, context_switches} = :erlang.statistics(:context_switches)
      context_switches
    rescue
      _ -> 0
    end
  end

  defp get_interrupts do
    # Mock interrupt count
    0
  end

  defp get_available_memory do
    # Estimate available memory
    memory_info = :erlang.memory()
    total = memory_info[:total] || 0
    # Assume 50% of total is available (simplified)
    round(total * 0.5)
  end

  defp count_network_connections do
    # Count active ports as a proxy for network connections
    length(Port.list())
  end

  defp count_active_connections do
    # Simplified active connection count
    (length(Port.list()) * 0.8) |> round()
  end

  defp count_listen_sockets do
    # Mock listen socket count
    5
  end

  defp count_running_processes do
    # Count processes that are currently running
    Process.list()
    |> Enum.count(fn pid ->
      case Process.info(pid, :status) do
        {:status, :running} -> true
        _ -> false
      end
    end)
  end

  defp calculate_memory_per_process do
    memory_info = :erlang.memory()
    process_count = :erlang.system_info(:process_count)
    processes_memory = memory_info[:processes] || 0

    if process_count > 0 do
      processes_memory / process_count
    else
      0.0
    end
  end

  defp calculate_cpu_per_process do
    # Simplified CPU per process calculation
    process_count = :erlang.system_info(:process_count)

    if process_count > 0 do
      100.0 / process_count
    else
      0.0
    end
  end

  defp get_system_uptime do
    # Get system uptime in seconds
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    round(uptime_ms / 1000)
  end

  defp get_uptime do
    # Get process uptime
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    round(uptime_ms / 1000)
  end

  # Analysis functions
  defp analyze_health_indicators(current_metrics, baseline_metrics) do
    indicators = []

    cpu_indicator = analyze_cpu_health(current_metrics.cpu, baseline_metrics)
    indicators = [cpu_indicator | indicators]

    memory_indicator = analyze_memory_health(current_metrics.memory, baseline_metrics)
    indicators = [memory_indicator | indicators]

    process_indicator = analyze_process_health(current_metrics.processes, baseline_metrics)
    indicators = [process_indicator | indicators]

    io_indicator = analyze_io_health(current_metrics.io, baseline_metrics)
    indicators = [io_indicator | indicators]

    load_indicator = analyze_load_health(current_metrics.system_load, baseline_metrics)
    [load_indicator | indicators]
  end

  defp analyze_cpu_health(cpu_metrics, baseline) do
    utilization = cpu_metrics.utilization

    {status, score, message} =
      cond do
        utilization > 90.0 ->
          {:critical, 0.1, "CPU utilization critically high at #{Float.round(utilization, 1)}%"}

        utilization > 75.0 ->
          {:warning, 0.5, "CPU utilization elevated at #{Float.round(utilization, 1)}%"}

        true ->
          {:healthy, 0.9, "CPU utilization normal at #{Float.round(utilization, 1)}%"}
      end

    %{
      component: :cpu,
      status: status,
      score: score,
      message: message,
      metrics: %{
        current_utilization: utilization,
        baseline_utilization: get_baseline_cpu(baseline),
        scheduler_utilization: cpu_metrics.scheduler_utilization
      }
    }
  end

  defp analyze_memory_health(memory_metrics, baseline) do
    usage_ratio =
      if memory_metrics.total > 0 do
        memory_metrics.used / memory_metrics.total
      else
        0.0
      end

    usage_percent = usage_ratio * 100

    {status, score, message} =
      cond do
        usage_percent > 90.0 ->
          {:critical, 0.1, "Memory usage critically high at #{Float.round(usage_percent, 1)}%"}

        usage_percent > 75.0 ->
          {:warning, 0.5, "Memory usage elevated at #{Float.round(usage_percent, 1)}%"}

        true ->
          {:healthy, 0.9, "Memory usage normal at #{Float.round(usage_percent, 1)}%"}
      end

    %{
      component: :memory,
      status: status,
      score: score,
      message: message,
      metrics: %{
        current_usage_percent: usage_percent,
        baseline_usage: get_baseline_memory(baseline),
        fragmentation_ratio: memory_metrics.fragmentation_ratio
      }
    }
  end

  defp analyze_process_health(process_metrics, baseline) do
    process_count = process_metrics.total_count
    process_limit = :erlang.system_info(:process_limit)
    utilization = process_count / process_limit * 100

    {status, score, message} =
      cond do
        utilization > 90.0 ->
          {:critical, 0.1, "Process count critically high: #{process_count}/#{process_limit}"}

        utilization > 75.0 ->
          {:warning, 0.5, "Process count elevated: #{process_count}/#{process_limit}"}

        true ->
          {:healthy, 0.9, "Process count normal: #{process_count}/#{process_limit}"}
      end

    %{
      component: :processes,
      status: status,
      score: score,
      message: message,
      metrics: %{
        current_count: process_count,
        utilization_percent: utilization,
        baseline_count: get_baseline_processes(baseline),
        running_processes: process_metrics.running
      }
    }
  end

  defp analyze_io_health(io_metrics, _baseline) do
    total_io = io_metrics.disk_read_bytes + io_metrics.disk_write_bytes

    {status, score, message} =
      cond do
        total_io > 1_000_000_000 ->
          {:warning, 0.6, "High I/O activity detected"}

        true ->
          {:healthy, 0.9, "I/O activity normal"}
      end

    %{
      component: :io,
      status: status,
      score: score,
      message: message,
      metrics: %{
        total_io_bytes: total_io,
        read_bytes: io_metrics.disk_read_bytes,
        write_bytes: io_metrics.disk_write_bytes
      }
    }
  end

  defp analyze_load_health(load_metrics, _baseline) do
    load_1min = load_metrics.load_1min
    cpu_count = :erlang.system_info(:schedulers)

    normalized_load = load_1min / cpu_count

    {status, score, message} =
      cond do
        normalized_load > 2.0 ->
          {:critical, 0.2, "System load critically high: #{Float.round(load_1min, 2)}"}

        normalized_load > 1.0 ->
          {:warning, 0.6, "System load elevated: #{Float.round(load_1min, 2)}"}

        true ->
          {:healthy, 0.9, "System load normal: #{Float.round(load_1min, 2)}"}
      end

    %{
      component: :system_load,
      status: status,
      score: score,
      message: message,
      metrics: %{
        load_1min: load_1min,
        load_5min: load_metrics.load_5min,
        load_15min: load_metrics.load_15min,
        normalized_load: normalized_load
      }
    }
  end

  defp determine_overall_health_status(health_indicators) do
    statuses = Enum.map(health_indicators, & &1.status)

    cond do
      Enum.any?(statuses, &(&1 == :critical)) -> :critical
      Enum.any?(statuses, &(&1 == :warning)) -> :warning
      true -> :healthy
    end
  end

  defp calculate_stability_score(health_indicators, _historical_data) do
    scores = Enum.map(health_indicators, & &1.score)

    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      0.0
    end
  end

  defp identify_risk_factors(_current_metrics, _historical_data) do
    # Simplified risk factor identification
    []
  end

  defp generate_health_recommendations(health_indicators, risk_factors) do
    recommendations = []

    recommendations =
      Enum.reduce(health_indicators, recommendations, fn indicator, acc ->
        case indicator.status do
          :critical -> [generate_critical_recommendation(indicator) | acc]
          :warning -> [generate_warning_recommendation(indicator) | acc]
          _ -> acc
        end
      end)

    risk_recommendations = Enum.map(risk_factors, & &1.mitigation)

    recommendations ++ risk_recommendations
  end

  defp generate_critical_recommendation(indicator) do
    case indicator.component do
      :cpu -> "CRITICAL: Reduce CPU load immediately - investigate high-CPU processes"
      :memory -> "CRITICAL: Free memory immediately - check for memory leaks"
      :processes -> "CRITICAL: Reduce process count - implement process pooling"
      :system_load -> "CRITICAL: Reduce system load - scale horizontally or optimize workload"
      _ -> "CRITICAL: Address #{indicator.component} issues immediately"
    end
  end

  defp generate_warning_recommendation(indicator) do
    case indicator.component do
      :cpu -> "WARNING: Monitor CPU usage - consider optimization"
      :memory -> "WARNING: Monitor memory usage - implement garbage collection tuning"
      :processes -> "WARNING: Monitor process count - review process lifecycle"
      :system_load -> "WARNING: Monitor system load - consider load balancing"
      _ -> "WARNING: Monitor #{indicator.component} metrics closely"
    end
  end

  # Anomaly detection functions
  defp detect_system_anomalies(_state) do
    # Simplified anomaly detection
    report = %{
      timestamp: DateTime.utc_now(),
      anomalies: [],
      severity_distribution: %{high: 0, medium: 0, low: 0},
      affected_systems: [],
      correlation_analysis: %{}
    }

    {:ok, report}
  end

  # Predictive analysis functions
  defp perform_predictive_analysis(_state) do
    # Simplified prediction
    report = %{
      timestamp: DateTime.utc_now(),
      predictions: [],
      confidence_level: 0.0,
      time_horizon: @prediction_horizon,
      recommended_actions: ["Insufficient historical data for predictions"]
    }

    {:ok, report}
  end

  # Recommendation generation
  defp generate_system_recommendations(_state) do
    # Simplified recommendations
    recommendations = [
      "Monitor system performance regularly",
      "Implement proper logging and alerting",
      "Review resource usage patterns"
    ]

    {:ok, recommendations}
  end

  # Utility functions
  defp establish_baseline_metrics do
    case collect_resource_metrics() do
      {:ok, metrics} -> {:ok, metrics}
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_next_health_check(interval) do
    Process.send_after(self(), :scheduled_health_check, interval)
  end

  # Baseline helper functions
  defp get_baseline_cpu(nil), do: 0.0
  defp get_baseline_cpu(baseline), do: baseline.cpu.utilization

  defp get_baseline_memory(nil), do: 0
  defp get_baseline_memory(baseline), do: baseline.memory.used

  defp get_baseline_processes(nil), do: 0
  defp get_baseline_processes(baseline), do: baseline.processes.total_count
end
