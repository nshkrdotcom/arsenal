#!/usr/bin/env elixir

# Standalone script to run process management examples
# Usage: elixir examples/run_process_demo.exs

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

# Load built-in operations
Code.require_file("lib/arsenal/operations/list_processes.ex")
Code.require_file("lib/arsenal/operations/get_process_info.ex")
Code.require_file("lib/arsenal/operations/start_process.ex")
Code.require_file("lib/arsenal/operations/list_supervisors.ex")

# Load example modules
Code.require_file("examples/process_management/process_inspector.ex")
Code.require_file("examples/process_management/process_controller.ex")

defmodule ProcessDemo do
  def run do
    IO.puts("🔧 Arsenal Process Management Demo")
    IO.puts("=" <> String.duplicate("=", 40))
    
    # Start Arsenal
    IO.puts("\n1. Starting Arsenal...")
    case Arsenal.start(:normal, []) do
      {:ok, _pid} -> IO.puts("   ✅ Arsenal started successfully")
      {:error, {:already_started, _}} -> IO.puts("   ✅ Arsenal already running")
      error -> 
        IO.puts("   ❌ Failed to start Arsenal: #{inspect(error)}")
        System.halt(1)
    end
    
    # Register operations
    IO.puts("\n2. Registering process operations...")
    register_operations()
    
    # Start process management tools
    IO.puts("\n3. Starting process management tools...")
    case Examples.ProcessManagement.ProcessController.start_link() do
      {:ok, _pid} -> IO.puts("   ✅ Process controller started")
      {:error, {:already_started, _}} -> IO.puts("   ✅ Process controller already running")
      error -> 
        IO.puts("   ❌ Failed to start process controller: #{inspect(error)}")
        System.halt(1)
    end
    
    # Demo process analysis
    IO.puts("\n4. Process Analysis")
    IO.puts("-" <> String.duplicate("-", 25))
    demo_process_analysis()
    
    # Demo process inspection
    IO.puts("\n5. Process Inspection")
    IO.puts("-" <> String.duplicate("-", 25))
    demo_process_inspection()
    
    # Demo process control
    IO.puts("\n6. Process Control")
    IO.puts("-" <> String.duplicate("-", 22))
    demo_process_control()
    
    # Demo supervisor information
    IO.puts("\n7. Supervisor Analysis")
    IO.puts("-" <> String.duplicate("-", 25))
    demo_supervisor_analysis()
    
    IO.puts("\n🔧 Process Management Demo Complete!")
    IO.puts("\nTry exploring process management manually:")
    IO.puts("  Arsenal.Registry.execute_operation(:list_processes, %{\"limit\" => 10})")
    IO.puts("  Examples.ProcessManagement.ProcessInspector.analyze_all_processes()")
  end
  
  defp register_operations do
    operations = [
      Arsenal.Operations.ListProcesses,
      Arsenal.Operations.GetProcessInfo,
      Arsenal.Operations.StartProcess,
      Arsenal.Operations.ListSupervisors
    ]
    
    Enum.each(operations, fn module ->
      case Arsenal.Registry.register_operation(module) do
        {:ok, _config} -> IO.puts("   ✅ Registered #{module}")
        {:error, reason} -> IO.puts("   ⚠️  #{module}: #{inspect(reason)}")
      end
    end)
  end
  
  defp demo_process_analysis do
    case Examples.ProcessManagement.ProcessInspector.analyze_all_processes() do
      {:ok, analysis} ->
        summary = analysis.summary
        IO.puts("   System Process Summary:")
        IO.puts("     Total Processes: #{summary.total_processes}")
        IO.puts("     Alive: #{summary.alive_processes}")
        IO.puts("     Waiting: #{summary.waiting_processes}")
        IO.puts("     Total Memory: #{format_memory(summary.total_memory_mb * 1024 * 1024)}")
        IO.puts("     Average Memory: #{summary.average_memory_kb}KB per process")
        IO.puts("     With Names: #{summary.processes_with_names}")
        IO.puts("     With Links: #{summary.processes_with_links}")
        IO.puts("     With Monitors: #{summary.processes_with_monitors}")
        
        IO.puts("\n   Process Categories:")
        Enum.each(analysis.categorization, fn category ->
          IO.puts("     #{format_category(category.category)}: #{category.count} processes (#{category.total_memory_mb}MB)")
        end)
        
        IO.puts("\n   Memory Analysis:")
        mem = analysis.memory_analysis
        IO.puts("     Total: #{mem.total_memory_mb}MB")
        IO.puts("     Average: #{mem.average_memory_kb}KB")
        IO.puts("     Median: #{mem.median_memory_kb}KB")
        IO.puts("     Max: #{mem.max_memory_mb}MB")
        IO.puts("     Min: #{mem.min_memory_kb}KB")
        
        IO.puts("\n   Performance Analysis:")
        perf = analysis.performance_analysis
        IO.puts("     Total Reductions: #{format_number(perf.total_reductions)}")
        IO.puts("     Average Reductions: #{format_number(perf.average_reductions)}")
        IO.puts("     High Reduction Processes: #{perf.processes_with_high_reductions}")
        IO.puts("     Processes with Messages: #{perf.processes_with_queued_messages}")
        IO.puts("     Long Message Queues: #{perf.processes_with_long_queues}")
        
        if length(analysis.recommendations) > 0 do
          IO.puts("\n   💡 Recommendations:")
          Enum.each(analysis.recommendations, fn rec ->
            IO.puts("     - #{rec}")
          end)
        else
          IO.puts("\n   ✅ No recommendations - system looks healthy!")
        end
      
      {:error, reason} ->
        IO.puts("   ❌ Failed to analyze processes: #{inspect(reason)}")
    end
  end
  
  defp demo_process_inspection do
    # Inspect the current process
    IO.puts("   Inspecting current process (#{inspect(self())})...")
    
    case Examples.ProcessManagement.ProcessInspector.inspect_process(self()) do
      {:ok, details} ->
        basic = details.basic_info
        IO.puts("     Status: #{basic.status}")
        IO.puts("     Memory: #{format_memory(basic.memory)}")
        IO.puts("     Message Queue: #{Map.get(basic, :message_queue_len, 0)}")
        IO.puts("     Reductions: #{format_number(basic.reductions)}")
        IO.puts("     Links: #{length(Map.get(basic, :links, []))}")
        IO.puts("     Monitors: #{length(Map.get(basic, :monitors, []))}")
        
        if length(details.recommendations) > 0 do
          IO.puts("     Recommendations:")
          Enum.each(details.recommendations, fn rec ->
            IO.puts("       - #{rec}")
          end)
        end
      
      {:error, reason} ->
        IO.puts("     ❌ Failed to inspect process: #{inspect(reason)}")
    end
    
    # Find high-memory processes
    IO.puts("\n   Finding high-memory processes...")
    case Examples.ProcessManagement.ProcessInspector.find_processes([
      {:memory_greater_than, 5 * 1024 * 1024}  # >5MB
    ]) do
      {:ok, %{matches: matches, count: count}} ->
        IO.puts("     Found #{count} processes using >5MB memory:")
        Enum.take(matches, 5) |> Enum.each(fn process ->
          name = process.registered_name || "unnamed"
          IO.puts("       - #{name} (#{inspect(process.pid)}): #{format_memory(process.memory)}")
        end)
        
        if count > 5 do
          IO.puts("       ... and #{count - 5} more")
        end
      
      {:error, reason} ->
        IO.puts("     ❌ Failed to find processes: #{inspect(reason)}")
    end
    
    # Find processes with long message queues
    IO.puts("\n   Finding processes with message queues...")
    case Examples.ProcessManagement.ProcessInspector.find_processes([
      {:queue_length_greater_than, 0}
    ]) do
      {:ok, %{matches: matches, count: count}} ->
        if count > 0 do
          IO.puts("     Found #{count} processes with message queues:")
          Enum.take(matches, 3) |> Enum.each(fn process ->
            name = Map.get(process, :registered_name, "unnamed")
            IO.puts("       - #{name}: #{process.message_queue_len} messages")
          end)
        else
          IO.puts("     No processes with message queues found")
        end
      
      {:error, reason} ->
        IO.puts("     ❌ Failed to find processes: #{inspect(reason)}")
    end
  end
  
  defp demo_process_control do
    # Create some test processes to manage
    IO.puts("   Creating test processes...")
    
    test_processes = [
      %{module: :timer, function: :sleep, args: [30000]},  # Long-running process
      %{module: :timer, function: :sleep, args: [5000]},   # Medium process
      %{module: :timer, function: :sleep, args: [1000]}    # Short process
    ]
    
    case Examples.ProcessManagement.ProcessController.start_processes(test_processes) do
      {:ok, results} ->
        IO.puts("     ✅ Started #{results.total_started} processes")
        
        if results.total_failed > 0 do
          IO.puts("     ❌ Failed to start #{results.total_failed} processes")
        end
        
        # Get controller stats
        stats = Examples.ProcessManagement.ProcessController.get_stats()
        IO.puts("     Controller Stats:")
        IO.puts("       Managed Processes: #{stats.managed_processes_count}")
        IO.puts("       Total Started: #{stats.processes_started}")
        IO.puts("       Total Stopped: #{stats.processes_stopped}")
        IO.puts("       Total Restarted: #{stats.processes_restarted}")
        IO.puts("       Uptime: #{format_duration(stats.uptime_seconds * 1000)}")
        
        # Perform health check
        IO.puts("\n   Performing health check on managed processes...")
        case Examples.ProcessManagement.ProcessController.health_check() do
          {:ok, health_results} ->
            healthy_count = Enum.count(health_results, fn {_pid, result} ->
              result.status == :healthy
            end)
            
            IO.puts("     Health Check Results:")
            IO.puts("       Healthy Processes: #{healthy_count}")
            IO.puts("       Total Checked: #{length(health_results)}")
            
            # Show details for first few processes
            Enum.take(health_results, 3) |> Enum.each(fn {pid, health} ->
              IO.puts("       #{inspect(pid)}: #{health.status} (#{health.memory_mb}MB, #{health.queue_length} msgs)")
            end)
          
          {:error, reason} ->
            IO.puts("     ❌ Health check failed: #{inspect(reason)}")
        end
        
        # Clean up - stop the test processes after a moment
        Process.sleep(2000)
        IO.puts("\n   Cleaning up test processes...")
        
        successful_pids = Enum.map(results.successful, fn {:ok, {pid, _spec}} -> pid end)
        case Examples.ProcessManagement.ProcessController.stop_processes(successful_pids, 1000) do
          {:ok, stop_results} ->
            IO.puts("     ✅ Stopped #{stop_results.successful_stops} processes")
          
          {:error, reason} ->
            IO.puts("     ❌ Failed to stop processes: #{inspect(reason)}")
        end
      
      {:error, reason} ->
        IO.puts("     ❌ Failed to start test processes: #{inspect(reason)}")
    end
  end
  
  defp demo_supervisor_analysis do
    case Arsenal.Registry.execute_operation(:list_supervisors, %{}) do
      {:ok, {supervisors, meta}} ->
        IO.puts("   Found #{length(supervisors)} supervisors (total: #{meta.total}):")
        
        Enum.take(supervisors, 5) |> Enum.each(fn supervisor ->
          name = Map.get(supervisor, :name, "unnamed")
          IO.puts("     #{name} (#{inspect(supervisor.pid)}):")
          IO.puts("       Strategy: #{Map.get(supervisor, :strategy, :unknown)}")
          IO.puts("       Children: #{Map.get(supervisor, :children_count, 0)}")
        end)
        
        if length(supervisors) > 5 do
          IO.puts("     ... and #{length(supervisors) - 5} more supervisors")
        end
        
        # Try to get restart statistics for the first supervisor
        if length(supervisors) > 0 do
          first_sup = hd(supervisors)
          name = Map.get(first_sup, :name, "first supervisor")
          IO.puts("\n   Restart statistics for #{name}:")
          
          case Arsenal.AnalyticsServer.get_restart_statistics(first_sup.pid) do
            {:ok, stats} ->
              IO.puts("     Total Restarts: #{stats.total_restarts}")
              IO.puts("     Restart Rate: #{Float.round(stats.restart_rate, 3)} per hour")
              IO.puts("     Last Restart: #{stats.last_restart || "never"}")
            
            {:error, reason} ->
              IO.puts("     ❌ Failed to get restart stats: #{inspect(reason)}")
          end
        end
      
      {:error, reason} ->
        IO.puts("   ❌ Failed to list supervisors: #{inspect(reason)}")
    end
  end
  
  defp format_category(:supervisor), do: "🔧 Supervisors"
  defp format_category(:genserver), do: "⚙️  GenServers"
  defp format_category(:task), do: "📋 Tasks"
  defp format_category(:agent), do: "📊 Agents"
  defp format_category(:named_process), do: "🏷️  Named Processes"
  defp format_category(:linked_process), do: "🔗 Linked Processes"
  defp format_category(:worker_process), do: "👷 Worker Processes"
  defp format_category(other), do: "❓ #{other}"
  
  defp format_memory(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024 * 1024), 2)}GB"
      bytes >= 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 2)}MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)}KB"
      true -> "#{bytes}B"
    end
  end
  
  defp format_number(num) when num >= 1_000_000_000 do
    "#{Float.round(num / 1_000_000_000, 2)}B"
  end
  defp format_number(num) when num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 2)}M"
  end
  defp format_number(num) when num >= 1_000 do
    "#{Float.round(num / 1_000, 2)}K"
  end
  defp format_number(num), do: to_string(num)
  
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
ProcessDemo.run()