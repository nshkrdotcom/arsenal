defmodule Examples.Analytics.DashboardData do
  @moduledoc """
  Data provider for monitoring dashboards.
  
  This module provides formatted data suitable for web dashboards,
  real-time monitoring displays, and external monitoring systems.
  """
  
  @doc """
  Get complete dashboard data with all metrics.
  """
  def get_dashboard_data do
    with {:ok, health} <- Arsenal.AnalyticsServer.get_system_health(),
         {:ok, performance} <- Arsenal.AnalyticsServer.get_performance_metrics() do
      
      {:ok, %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        system_overview: format_system_overview(health, performance),
        health_metrics: format_health_metrics(health),
        performance_metrics: format_performance_metrics(performance),
        process_metrics: format_process_metrics(performance),
        memory_metrics: format_memory_metrics(performance),
        restart_metrics: get_restart_metrics(),
        alerts: get_current_alerts(health),
        trends: get_trend_data()
      }}
    else
      error -> {:error, "Failed to get dashboard data: #{inspect(error)}"}
    end
  end
  
  @doc """
  Get real-time metrics for live dashboard updates.
  """
  def get_realtime_metrics do
    case Arsenal.AnalyticsServer.get_performance_metrics() do
      {:ok, metrics} ->
        {:ok, %{
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
          cpu_usage: metrics.cpu.utilization,
          memory_usage: (metrics.memory.used / metrics.memory.total * 100) |> Float.round(2),
          process_count: metrics.processes.count,
          runnable_processes: metrics.processes.runnable,
          running_processes: metrics.processes.running,
          gc_collections: metrics.gc.collections,
          io_input: metrics.io.input,
          io_output: metrics.io.output
        }}
      
      error ->
        {:error, "Failed to get realtime metrics: #{inspect(error)}"}
    end
  end
  
  @doc """
  Get historical performance data for charts.
  """
  def get_historical_data(hours_back \\ 24) do
    start_time = DateTime.add(DateTime.utc_now(), -hours_back * 3600, :second)
    end_time = DateTime.utc_now()
    
    case Arsenal.AnalyticsServer.get_historical_data(start_time, end_time) do
      {:ok, history} ->
        {:ok, %{
          timeframe: %{
            start: DateTime.to_iso8601(start_time),
            end: DateTime.to_iso8601(end_time),
            hours: hours_back
          },
          metrics: format_historical_metrics(history),
          restart_events: format_historical_restarts(history)
        }}
      
      error ->
        {:error, "Failed to get historical data: #{inspect(error)}"}
    end
  end
  
  @doc """
  Get supervisor health status for supervision tree view.
  """
  def get_supervisor_health do
    case Arsenal.Operations.ListSupervisors.execute(%{}) do
      {:ok, supervisors} ->
        supervisor_health = Enum.map(supervisors, fn supervisor ->
          restart_stats = case Arsenal.AnalyticsServer.get_restart_statistics(supervisor.pid) do
            {:ok, stats} -> stats
            {:error, _} -> %{total_restarts: 0, restart_rate: 0.0}
          end
          
          %{
            name: supervisor.name || "#{inspect(supervisor.pid)}",
            pid: inspect(supervisor.pid),
            children_count: supervisor.children_count,
            strategy: supervisor.strategy,
            max_restarts: supervisor.max_restarts,
            max_seconds: supervisor.max_seconds,
            total_restarts: restart_stats.total_restarts,
            restart_rate: restart_stats.restart_rate,
            health_status: determine_supervisor_health(restart_stats, supervisor)
          }
        end)
        
        {:ok, %{
          supervisors: supervisor_health,
          total_supervisors: length(supervisor_health),
          healthy_count: Enum.count(supervisor_health, &(&1.health_status == :healthy)),
          warning_count: Enum.count(supervisor_health, &(&1.health_status == :warning)),
          critical_count: Enum.count(supervisor_health, &(&1.health_status == :critical))
        }}
      
      error ->
        {:error, "Failed to get supervisor health: #{inspect(error)}"}
    end
  end
  
  @doc """
  Get process analysis for process management dashboard.
  """
  def get_process_analysis do
    case Arsenal.Operations.ListProcesses.execute(%{limit: 1000, sort_by: "memory"}) do
      {:ok, processes} ->
        analysis = %{
          total_processes: length(processes),
          memory_analysis: analyze_process_memory(processes),
          message_queue_analysis: analyze_message_queues(processes),
          cpu_analysis: analyze_process_cpu(processes),
          process_types: analyze_process_types(processes),
          long_running: get_long_running_processes(processes),
          high_memory: get_high_memory_processes(processes)
        }
        
        {:ok, analysis}
      
      error ->
        {:error, "Failed to get process analysis: #{inspect(error)}"}
    end
  end
  
  # Private formatting functions
  
  defp format_system_overview(health, performance) do
    %{
      status: health.overall_status,
      status_color: status_color(health.overall_status),
      uptime_ms: get_system_uptime(),
      node_name: Node.self(),
      erlang_version: System.version(),
      total_memory_mb: div(performance.memory.total, 1024 * 1024),
      used_memory_mb: div(performance.memory.used, 1024 * 1024),
      cpu_usage: performance.cpu.utilization,
      process_count: performance.processes.count,
      anomaly_count: length(health.anomalies)
    }
  end
  
  defp format_health_metrics(health) do
    %{
      overall_status: health.overall_status,
      process_count: health.process_count,
      memory_usage: %{
        total_mb: div(health.memory_usage.total, 1024 * 1024),
        processes_mb: div(health.memory_usage.processes, 1024 * 1024),
        system_mb: div(health.memory_usage.system, 1024 * 1024),
        atom_mb: div(health.memory_usage.atom, 1024 * 1024),
        binary_mb: div(health.memory_usage.binary, 1024 * 1024),
        code_mb: div(health.memory_usage.code, 1024 * 1024),
        ets_mb: div(health.memory_usage.ets, 1024 * 1024)
      },
      cpu_usage: health.cpu_usage,
      restart_rate: health.restart_rate,
      message_queues: health.message_queue_lengths,
      anomalies: Enum.map(health.anomalies, &format_anomaly/1),
      recommendations: health.recommendations,
      last_check: DateTime.to_iso8601(health.last_check)
    }
  end
  
  defp format_performance_metrics(metrics) do
    %{
      cpu: %{
        utilization: metrics.cpu.utilization,
        load_average: metrics.cpu.load_average,
        scheduler_utilization: metrics.cpu.scheduler_utilization
      },
      memory: %{
        total_mb: div(metrics.memory.total, 1024 * 1024),
        used_mb: div(metrics.memory.used, 1024 * 1024),
        available_mb: div(metrics.memory.available, 1024 * 1024),
        utilization: (metrics.memory.used / metrics.memory.total * 100) |> Float.round(2)
      },
      io: %{
        input_mb: div(metrics.io.input, 1024 * 1024),
        output_mb: div(metrics.io.output, 1024 * 1024)
      },
      gc: %{
        collections: metrics.gc.collections,
        words_reclaimed: metrics.gc.words_reclaimed,
        time_spent_ms: div(metrics.gc.time_spent, 1000)
      },
      timestamp: DateTime.to_iso8601(metrics.timestamp)
    }
  end
  
  defp format_process_metrics(metrics) do
    %{
      count: metrics.processes.count,
      limit: metrics.processes.limit,
      utilization: metrics.processes.utilization,
      runnable: metrics.processes.runnable,
      running: metrics.processes.running,
      availability: ((metrics.processes.limit - metrics.processes.count) / metrics.processes.limit * 100) |> Float.round(2)
    }
  end
  
  defp format_memory_metrics(metrics) do
    total = metrics.memory.total
    
    %{
      total_mb: div(total, 1024 * 1024),
      used_mb: div(metrics.memory.used, 1024 * 1024),
      processes_mb: div(metrics.memory.processes, 1024 * 1024),
      system_mb: div(metrics.memory.system, 1024 * 1024),
      breakdown_percentages: %{
        processes: (metrics.memory.processes / total * 100) |> Float.round(2),
        system: (metrics.memory.system / total * 100) |> Float.round(2),
        used: (metrics.memory.used / total * 100) |> Float.round(2),
        available: ((total - metrics.memory.used) / total * 100) |> Float.round(2)
      }
    }
  end
  
  defp get_restart_metrics do
    # This would aggregate restart data across all supervisors
    case Arsenal.Operations.ListSupervisors.execute(%{}) do
      {:ok, supervisors} ->
        restart_data = Enum.map(supervisors, fn supervisor ->
          case Arsenal.AnalyticsServer.get_restart_statistics(supervisor.pid) do
            {:ok, stats} ->
              %{
                supervisor: supervisor.name || inspect(supervisor.pid),
                total_restarts: stats.total_restarts,
                restart_rate: stats.restart_rate,
                last_restart: stats.last_restart
              }
            
            {:error, _} ->
              %{
                supervisor: supervisor.name || inspect(supervisor.pid),
                total_restarts: 0,
                restart_rate: 0.0,
                last_restart: nil
              }
          end
        end)
        
        total_restarts = Enum.sum(Enum.map(restart_data, & &1.total_restarts))
        avg_restart_rate = 
          restart_data
          |> Enum.map(& &1.restart_rate)
          |> Enum.sum()
          |> case do
            0 -> 0.0
            sum -> sum / length(restart_data)
          end
        
        %{
          supervisors: restart_data,
          total_restarts: total_restarts,
          average_restart_rate: avg_restart_rate,
          supervisors_with_restarts: Enum.count(restart_data, &(&1.total_restarts > 0))
        }
      
      {:error, _} ->
        %{error: "Unable to get restart metrics"}
    end
  end
  
  defp get_current_alerts(health) do
    alerts = []
    
    # Check for critical status
    alerts = if health.overall_status == :critical do
      [%{
        type: :critical,
        severity: :high,
        message: "System health is critical",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      } | alerts]
    else
      alerts
    end
    
    # Add anomaly alerts
    anomaly_alerts = Enum.map(health.anomalies, fn anomaly ->
      %{
        type: :anomaly,
        severity: Map.get(anomaly, :severity, :medium),
        message: Map.get(anomaly, :description, "Anomaly detected"),
        details: anomaly,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    end)
    
    alerts ++ anomaly_alerts
  end
  
  defp get_trend_data do
    # This would calculate trends from historical data
    # For now, return placeholder trend indicators
    %{
      cpu_trend: :stable,
      memory_trend: :increasing,
      process_count_trend: :stable,
      restart_rate_trend: :decreasing
    }
  end
  
  defp format_historical_metrics(history) do
    # Format historical data for charting
    # This would process the historical data structure
    %{
      cpu_history: [],
      memory_history: [],
      process_count_history: [],
      restart_rate_history: []
    }
  end
  
  defp format_historical_restarts(history) do
    # Format restart events for timeline display
    []
  end
  
  defp format_anomaly(anomaly) do
    %{
      type: anomaly.type,
      severity: Map.get(anomaly, :severity, :medium),
      description: Map.get(anomaly, :description, ""),
      current_value: Map.get(anomaly, :current_value),
      baseline_value: Map.get(anomaly, :baseline_value),
      timestamp: Map.get(anomaly, :timestamp) |> case do
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        _ -> nil
      end
    }
  end
  
  defp determine_supervisor_health(restart_stats, supervisor) do
    cond do
      restart_stats.restart_rate > 10.0 -> :critical
      restart_stats.restart_rate > 5.0 -> :warning
      restart_stats.total_restarts > supervisor.max_restarts -> :warning
      true -> :healthy
    end
  end
  
  defp analyze_process_memory(processes) do
    memory_usage = Enum.map(processes, & &1.memory)
    
    %{
      total_mb: div(Enum.sum(memory_usage), 1024 * 1024),
      average_mb: div(div(Enum.sum(memory_usage), length(processes)), 1024 * 1024),
      max_mb: div(Enum.max(memory_usage, fn -> 0 end), 1024 * 1024),
      min_mb: div(Enum.min(memory_usage, fn -> 0 end), 1024 * 1024)
    }
  end
  
  defp analyze_message_queues(processes) do
    queue_lengths = Enum.map(processes, & &1.message_queue_length)
    
    %{
      max_queue_length: Enum.max(queue_lengths, fn -> 0 end),
      average_queue_length: div(Enum.sum(queue_lengths), length(processes)),
      processes_with_queues: Enum.count(queue_lengths, &(&1 > 0)),
      processes_with_long_queues: Enum.count(queue_lengths, &(&1 > 100))
    }
  end
  
  defp analyze_process_cpu(processes) do
    # This would require CPU usage data per process
    # Placeholder implementation
    %{
      high_cpu_processes: 0,
      total_reductions: Enum.sum(Enum.map(processes, & &1.reductions))
    }
  end
  
  defp analyze_process_types(processes) do
    Enum.reduce(processes, %{}, fn process, acc ->
      initial_call = process.initial_call
      Map.update(acc, initial_call, 1, &(&1 + 1))
    end)
  end
  
  defp get_long_running_processes(processes) do
    # Sort by reductions (indicator of CPU usage over time)
    processes
    |> Enum.sort_by(& &1.reductions, :desc)
    |> Enum.take(10)
    |> Enum.map(fn process ->
      %{
        pid: inspect(process.pid),
        name: process.registered_name,
        initial_call: process.initial_call,
        reductions: process.reductions,
        message_queue_length: process.message_queue_length
      }
    end)
  end
  
  defp get_high_memory_processes(processes) do
    processes
    |> Enum.sort_by(& &1.memory, :desc)
    |> Enum.take(10)
    |> Enum.map(fn process ->
      %{
        pid: inspect(process.pid),
        name: process.registered_name,
        memory_mb: div(process.memory, 1024 * 1024),
        initial_call: process.initial_call,
        heap_size: process.heap_size,
        stack_size: process.stack_size
      }
    end)
  end
  
  defp status_color(:healthy), do: "green"
  defp status_color(:warning), do: "yellow"  
  defp status_color(:critical), do: "red"
  defp status_color(_), do: "gray"
  
  defp get_system_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end
end