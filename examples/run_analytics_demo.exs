#!/usr/bin/env elixir

# Standalone script to run analytics examples
# Usage: elixir examples/run_analytics_demo.exs

# Add the lib directory to the code path
Code.prepend_path("lib")

# Install dependencies
Mix.install([
  {:jason, "~> 1.4"},
  {:telemetry, "~> 1.0"}
])

# Load Arsenal modules
Code.require_file("lib/arsenal.ex")
Code.require_file("lib/arsenal/operation.ex")
Code.require_file("lib/arsenal/operation/validator.ex")
Code.require_file("lib/arsenal/registry.ex")
Code.require_file("lib/arsenal/analytics_server.ex")
Code.require_file("lib/arsenal/startup.ex")

# Load built-in operations that analytics examples use
Code.require_file("lib/arsenal/operations/list_supervisors.ex")
Code.require_file("lib/arsenal/operations/list_processes.ex")

# Load example modules
Code.require_file("examples/analytics/basic_monitoring.ex")
Code.require_file("examples/analytics/dashboard_data.ex")

defmodule AnalyticsDemo do
  def run do
    IO.puts("📊 Arsenal Analytics Demo")
    IO.puts("=" <> String.duplicate("=", 30))
    
    # Start Arsenal
    IO.puts("\n1. Starting Arsenal...")
    case Arsenal.start(:normal, []) do
      {:ok, _pid} -> IO.puts("   ✅ Arsenal started successfully")
      {:error, {:already_started, _}} -> IO.puts("   ✅ Arsenal already running")
      error -> 
        IO.puts("   ❌ Failed to start Arsenal: #{inspect(error)}")
        System.halt(1)
    end
    
    # Wait for analytics server to initialize
    Process.sleep(100)
    
    # Start basic monitoring
    IO.puts("\n2. Starting basic monitoring...")
    case Examples.Analytics.BasicMonitoring.start_link() do
      {:ok, _pid} -> IO.puts("   ✅ Basic monitoring started")
      {:error, {:already_started, _}} -> IO.puts("   ✅ Basic monitoring already running")
      error -> 
        IO.puts("   ❌ Failed to start monitoring: #{inspect(error)}")
        System.halt(1)
    end
    
    # Demo system health
    IO.puts("\n3. System Health Analysis")
    IO.puts("-" <> String.duplicate("-", 30))
    demo_system_health()
    
    # Demo performance metrics
    IO.puts("\n4. Performance Metrics")
    IO.puts("-" <> String.duplicate("-", 25))
    demo_performance_metrics()
    
    # Demo dashboard data
    IO.puts("\n5. Dashboard Data")
    IO.puts("-" <> String.duplicate("-", 20))
    demo_dashboard_data()
    
    # Generate some activity and monitor it
    IO.puts("\n6. Generating Activity & Monitoring")
    IO.puts("-" <> String.duplicate("-", 35))
    demo_activity_monitoring()
    
    IO.puts("\n📊 Analytics Demo Complete!")
    IO.puts("\nTry exploring analytics manually:")
    IO.puts("  Arsenal.AnalyticsServer.get_system_health()")
    IO.puts("  Examples.Analytics.BasicMonitoring.get_health_summary()")
  end
  
  defp demo_system_health do
    case Arsenal.AnalyticsServer.get_system_health() do
      {:ok, health} ->
        IO.puts("   Overall Status: #{format_status(health.overall_status)}")
        IO.puts("   Process Count: #{health.process_count}")
        IO.puts("   Memory Usage: #{format_memory(health.memory_usage.total)}")
        IO.puts("   CPU Usage: #{Float.round(health.cpu_usage, 2)}%")
        IO.puts("   Restart Rate: #{Float.round(health.restart_rate, 3)} restarts/hour")
        
        if length(health.anomalies) > 0 do
          IO.puts("   ⚠️  Anomalies detected: #{length(health.anomalies)}")
          Enum.each(health.anomalies, fn anomaly ->
            IO.puts("     - #{Map.get(anomaly, :description, "Unknown anomaly")}")
          end)
        else
          IO.puts("   ✅ No anomalies detected")
        end
        
        if length(health.recommendations) > 0 do
          IO.puts("   💡 Recommendations:")
          Enum.each(health.recommendations, fn rec ->
            IO.puts("     - #{rec}")
          end)
        end
      
      {:error, reason} ->
        IO.puts("   ❌ Failed to get system health: #{inspect(reason)}")
    end
  end
  
  defp demo_performance_metrics do
    case Arsenal.AnalyticsServer.get_performance_metrics() do
      {:ok, metrics} ->
        IO.puts("   CPU Utilization: #{Float.round(metrics.cpu.utilization, 2)}%")
        IO.puts("   Memory: #{format_memory(metrics.memory.used)} / #{format_memory(metrics.memory.total)}")
        IO.puts("   Memory Utilization: #{Float.round(metrics.memory.used / metrics.memory.total * 100, 2)}%")
        IO.puts("   Processes: #{metrics.processes.count} / #{metrics.processes.limit}")
        IO.puts("   Process Utilization: #{Float.round(metrics.processes.utilization, 2)}%")
        IO.puts("   Runnable Processes: #{metrics.processes.runnable}")
        IO.puts("   Running Processes: #{metrics.processes.running}")
        IO.puts("   GC Collections: #{metrics.gc.collections}")
        IO.puts("   I/O Input: #{format_bytes(metrics.io.input)}")
        IO.puts("   I/O Output: #{format_bytes(metrics.io.output)}")
      
      {:error, reason} ->
        IO.puts("   ❌ Failed to get performance metrics: #{inspect(reason)}")
    end
  end
  
  defp demo_dashboard_data do
    case Examples.Analytics.DashboardData.get_dashboard_data() do
      {:ok, dashboard} ->
        overview = dashboard.system_overview
        IO.puts("   System Overview:")
        IO.puts("     Status: #{format_status(overview.status)}")
        IO.puts("     Uptime: #{format_duration(overview.uptime_ms)}")
        IO.puts("     Node: #{overview.node_name}")
        IO.puts("     Erlang Version: #{overview.erlang_version}")
        IO.puts("     Total Memory: #{overview.total_memory_mb}MB")
        IO.puts("     Used Memory: #{overview.used_memory_mb}MB")
        IO.puts("     CPU Usage: #{overview.cpu_usage}%")
        IO.puts("     Process Count: #{overview.process_count}")
        
        if overview.anomaly_count > 0 do
          IO.puts("     ⚠️  Anomalies: #{overview.anomaly_count}")
        end
      
      {:error, reason} ->
        IO.puts("   ❌ Failed to get dashboard data: #{inspect(reason)}")
    end
    
    # Show real-time metrics
    IO.puts("\n   Real-time Metrics:")
    case Examples.Analytics.DashboardData.get_realtime_metrics() do
      {:ok, metrics} ->
        IO.puts("     CPU: #{metrics.cpu_usage}%")
        IO.puts("     Memory: #{metrics.memory_usage}%")
        IO.puts("     Processes: #{metrics.process_count}")
        IO.puts("     Runnable: #{metrics.runnable_processes}")
        IO.puts("     Running: #{metrics.running_processes}")
      
      {:error, reason} ->
        IO.puts("     ❌ Failed to get real-time metrics: #{inspect(reason)}")
    end
  end
  
  defp demo_activity_monitoring do
    IO.puts("   Generating some system activity...")
    
    # Spawn some temporary processes to create activity
    pids = Enum.map(1..10, fn _i ->
      spawn(fn ->
        # Do some work
        Enum.each(1..1000, fn _ ->
          :math.sin(:rand.uniform() * 3.14159)
        end)
        
        # Sleep a bit
        Process.sleep(100 + :rand.uniform(200))
      end)
    end)
    
    IO.puts("   Created #{length(pids)} temporary processes")
    
    # Wait a moment for activity
    Process.sleep(500)
    
    # Check monitoring results
    case Examples.Analytics.BasicMonitoring.get_health_summary() do
      {:ok, summary} ->
        IO.puts("   Health Summary After Activity:")
        IO.puts("     Status: #{format_status(summary.overall_status)}")
        IO.puts("     Process Count: #{summary.process_count}")
        IO.puts("     Memory Usage: #{summary.memory_usage_mb}MB")
        IO.puts("     CPU Usage: #{summary.cpu_usage}%")
        IO.puts("     Restart Rate: #{Float.round(summary.restart_rate, 3)}")
        IO.puts("     Anomalies: #{summary.anomalies_count}")
        
        if length(summary.recent_alerts) > 0 do
          IO.puts("     Recent Alerts: #{length(summary.recent_alerts)}")
        end
      
      {:error, reason} ->
        IO.puts("   ❌ Failed to get health summary: #{inspect(reason)}")
    end
    
    # Check performance summary
    case Examples.Analytics.BasicMonitoring.get_performance_summary() do
      {:ok, perf} ->
        IO.puts("   Performance Summary:")
        IO.puts("     CPU Utilization: #{Float.round(perf.cpu_utilization, 2)}%")
        IO.puts("     Memory Total: #{perf.memory_total_mb}MB")
        IO.puts("     Memory Used: #{perf.memory_used_mb}MB")
        IO.puts("     Memory Utilization: #{perf.memory_utilization}%")
        IO.puts("     Process Count: #{perf.process_count}")
        IO.puts("     GC Collections: #{perf.gc_collections}")
      
      {:error, reason} ->
        IO.puts("   ❌ Failed to get performance summary: #{inspect(reason)}")
    end
    
    # Wait for processes to complete
    Process.sleep(1000)
    IO.puts("   Temporary processes completed")
  end
  
  defp format_status(:healthy), do: "🟢 Healthy"
  defp format_status(:warning), do: "🟡 Warning"
  defp format_status(:critical), do: "🔴 Critical"
  defp format_status(status), do: "⚪ #{status}"
  
  defp format_memory(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024 * 1024), 2)}GB"
      bytes >= 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 2)}MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)}KB"
      true -> "#{bytes}B"
    end
  end
  
  defp format_bytes(bytes) when is_integer(bytes) do
    format_memory(bytes)
  end
  
  defp format_duration(ms) when is_integer(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    hours = div(minutes, 60)
    days = div(hours, 24)
    
    cond do
      days > 0 -> "#{days}d #{rem(hours, 24)}h"
      hours > 0 -> "#{hours}h #{rem(minutes, 60)}m"
      minutes > 0 -> "#{minutes}m #{rem(seconds, 60)}s"
      true -> "#{seconds}s"
    end
  end
end

# Run the demo
AnalyticsDemo.run()