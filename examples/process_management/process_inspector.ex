defmodule Examples.ProcessManagement.ProcessInspector do
  @moduledoc """
  Advanced process inspection and analysis tools.
  
  This module demonstrates:
  - Detailed process analysis and categorization
  - Process relationship mapping
  - Memory and performance analysis
  - Process lifecycle tracking
  - Interactive process exploration
  """
  
  @doc """
  Get a comprehensive analysis of all processes in the system.
  """
  def analyze_all_processes do
    case Arsenal.Operations.ListProcesses.execute(%{limit: 10000}) do
      {:ok, processes} ->
        analysis = %{
          summary: generate_process_summary(processes),
          categorization: categorize_processes(processes),
          memory_analysis: analyze_memory_usage(processes),
          performance_analysis: analyze_performance(processes),
          relationships: map_process_relationships(processes),
          outliers: detect_outliers(processes),
          recommendations: generate_recommendations(processes)
        }
        
        {:ok, analysis}
      
      error ->
        error
    end
  end
  
  @doc """
  Get detailed information about a specific process and its relationships.
  """
  def inspect_process(pid) when is_pid(pid) do
    case Arsenal.Operations.GetProcessInfo.execute(%{pid: pid}) do
      {:ok, process_info} ->
        detailed_info = %{
          basic_info: process_info,
          relationships: get_process_relationships(pid),
          memory_breakdown: get_memory_breakdown(pid),
          message_analysis: analyze_message_queue(pid),
          performance_metrics: get_performance_metrics(pid),
          trace_info: get_trace_information(pid),
          recommendations: generate_process_recommendations(process_info)
        }
        
        {:ok, detailed_info}
      
      error ->
        error
    end
  end
  
  def inspect_process(pid_string) when is_binary(pid_string) do
    case parse_pid(pid_string) do
      {:ok, pid} -> inspect_process(pid)
      error -> error
    end
  end
  
  @doc """
  Find processes matching specific criteria.
  """
  def find_processes(criteria) do
    case Arsenal.Operations.ListProcesses.execute(%{limit: 10000}) do
      {:ok, processes} ->
        matches = Enum.filter(processes, &matches_criteria?(&1, criteria))
        
        {:ok, %{
          matches: matches,
          count: length(matches),
          criteria: criteria,
          total_processes: length(processes)
        }}
      
      error ->
        error
    end
  end
  
  @doc """
  Track process creation and termination patterns.
  """
  def track_process_lifecycle(duration_minutes \\ 60) do
    # This would typically use a background process to track changes
    initial_snapshot = get_process_snapshot()
    
    Task.async(fn ->
      Process.sleep(duration_minutes * 60 * 1000)
      final_snapshot = get_process_snapshot()
      
      analyze_lifecycle_changes(initial_snapshot, final_snapshot)
    end)
  end
  
  @doc """
  Generate a process tree visualization.
  """
  def generate_process_tree(root_pid \\ nil) do
    case Arsenal.Operations.ListProcesses.execute(%{limit: 10000}) do
      {:ok, processes} ->
        tree = build_process_tree(processes, root_pid)
        {:ok, tree}
      
      error ->
        error
    end
  end
  
  # Private functions for process analysis
  
  defp generate_process_summary(processes) do
    total = length(processes)
    
    %{
      total_processes: total,
      alive_processes: Enum.count(processes, & &1.status == :running),
      waiting_processes: Enum.count(processes, & &1.status == :waiting),
      suspended_processes: Enum.count(processes, & &1.status == :suspended),
      total_memory_mb: div(Enum.sum(Enum.map(processes, & &1.memory)), 1024 * 1024),
      average_memory_kb: div(Enum.sum(Enum.map(processes, & &1.memory)), total * 1024),
      total_reductions: Enum.sum(Enum.map(processes, & &1.reductions)),
      processes_with_names: Enum.count(processes, & &1.registered_name != nil),
      processes_with_links: Enum.count(processes, &(length(&1.links) > 0)),
      processes_with_monitors: Enum.count(processes, &(length(&1.monitors) > 0))
    }
  end
  
  defp categorize_processes(processes) do
    categories = Enum.group_by(processes, &categorize_process/1)
    
    Enum.map(categories, fn {category, procs} ->
      %{
        category: category,
        count: length(procs),
        total_memory_mb: div(Enum.sum(Enum.map(procs, & &1.memory)), 1024 * 1024),
        average_memory_kb: div(Enum.sum(Enum.map(procs, & &1.memory)), length(procs) * 1024),
        examples: Enum.take(procs, 3) |> Enum.map(&format_process_summary/1)
      }
    end)
  end
  
  defp categorize_process(process) do
    cond do
      process.registered_name && String.contains?(to_string(process.registered_name), "Supervisor") ->
        :supervisor
      
      process.initial_call && match?({GenServer, _, _}, process.initial_call) ->
        :genserver
      
      process.initial_call && match?({Task, _, _}, process.initial_call) ->
        :task
      
      process.initial_call && match?({Agent, _, _}, process.initial_call) ->
        :agent
      
      process.registered_name ->
        :named_process
      
      length(process.links) > 0 ->
        :linked_process
      
      true ->
        :worker_process
    end
  end
  
  defp analyze_memory_usage(processes) do
    memory_values = Enum.map(processes, & &1.memory)
    sorted_memory = Enum.sort(memory_values, :desc)
    
    %{
      total_memory_mb: div(Enum.sum(memory_values), 1024 * 1024),
      average_memory_kb: div(Enum.sum(memory_values), length(memory_values) * 1024),
      median_memory_kb: div(Enum.at(sorted_memory, div(length(sorted_memory), 2)), 1024),
      max_memory_mb: div(Enum.max(memory_values), 1024 * 1024),
      min_memory_kb: div(Enum.min(memory_values), 1024),
      memory_distribution: calculate_memory_distribution(sorted_memory),
      high_memory_processes: get_high_memory_processes(processes, 10)
    }
  end
  
  defp analyze_performance(processes) do
    reductions = Enum.map(processes, & &1.reductions)
    queue_lengths = Enum.map(processes, & &1.message_queue_length)
    
    %{
      total_reductions: Enum.sum(reductions),
      average_reductions: div(Enum.sum(reductions), length(reductions)),
      max_reductions: Enum.max(reductions),
      processes_with_high_reductions: Enum.count(reductions, &(&1 > 1_000_000)),
      total_messages_queued: Enum.sum(queue_lengths),
      processes_with_queued_messages: Enum.count(queue_lengths, &(&1 > 0)),
      processes_with_long_queues: Enum.count(queue_lengths, &(&1 > 100)),
      max_queue_length: Enum.max(queue_lengths),
      busy_processes: get_busy_processes(processes, 10)
    }
  end
  
  defp map_process_relationships(processes) do
    # Build a map of process relationships
    process_map = Enum.into(processes, %{}, &{&1.pid, &1})
    
    relationships = Enum.map(processes, fn process ->
      %{
        pid: process.pid,
        links: process.links,
        monitors: process.monitors,
        monitored_by: process.monitored_by,
        parent: find_parent_process(process, process_map),
        children: find_child_processes(process, processes)
      }
    end)
    
    %{
      total_links: Enum.sum(Enum.map(processes, &length(&1.links))),
      total_monitors: Enum.sum(Enum.map(processes, &length(&1.monitors))),
      orphaned_processes: Enum.count(relationships, &(is_nil(&1.parent) && length(&1.links) == 0)),
      highly_connected: Enum.filter(relationships, &(length(&1.links) + length(&1.monitors) > 5)),
      process_relationships: relationships
    }
  end
  
  defp detect_outliers(processes) do
    memory_threshold = calculate_memory_threshold(processes)
    reduction_threshold = calculate_reduction_threshold(processes)
    queue_threshold = 100
    
    outliers = Enum.filter(processes, fn process ->
      process.memory > memory_threshold ||
      process.reductions > reduction_threshold ||
      process.message_queue_length > queue_threshold
    end)
    
    %{
      memory_outliers: Enum.filter(outliers, &(&1.memory > memory_threshold)),
      performance_outliers: Enum.filter(outliers, &(&1.reductions > reduction_threshold)),
      queue_outliers: Enum.filter(outliers, &(&1.message_queue_length > queue_threshold)),
      total_outliers: length(outliers),
      thresholds: %{
        memory_mb: div(memory_threshold, 1024 * 1024),
        reductions: reduction_threshold,
        queue_length: queue_threshold
      }
    }
  end
  
  defp generate_recommendations(processes) do
    recommendations = []
    
    # Check for memory issues
    high_memory_count = Enum.count(processes, &(&1.memory > 10 * 1024 * 1024))
    recommendations = if high_memory_count > 0 do
      ["#{high_memory_count} processes using >10MB memory - investigate for memory leaks" | recommendations]
    else
      recommendations
    end
    
    # Check for long message queues
    long_queue_count = Enum.count(processes, &(&1.message_queue_length > 100))
    recommendations = if long_queue_count > 0 do
      ["#{long_queue_count} processes with long message queues - check for bottlenecks" | recommendations]
    else
      recommendations
    end
    
    # Check for high reduction processes
    high_reduction_count = Enum.count(processes, &(&1.reductions > 10_000_000))
    recommendations = if high_reduction_count > 0 do
      ["#{high_reduction_count} processes with high CPU usage - consider optimization" | recommendations]
    else
      recommendations
    end
    
    # Check for orphaned processes
    orphaned_count = Enum.count(processes, &(length(&1.links) == 0 && &1.registered_name == nil))
    recommendations = if orphaned_count > 100 do
      ["#{orphaned_count} orphaned processes detected - review process lifecycle" | recommendations]
    else
      recommendations
    end
    
    if length(recommendations) == 0 do
      ["System appears healthy - no immediate recommendations"]
    else
      recommendations
    end
  end
  
  defp get_process_relationships(pid) do
    case Process.info(pid, [:links, :monitors, :monitored_by]) do
      nil ->
        %{error: "Process not found"}
      
      info ->
        %{
          links: Keyword.get(info, :links, []),
          monitors: Keyword.get(info, :monitors, []),
          monitored_by: Keyword.get(info, :monitored_by, [])
        }
    end
  end
  
  defp get_memory_breakdown(pid) do
    case Process.info(pid, [:memory, :heap_size, :stack_size, :binary]) do
      nil ->
        %{error: "Process not found"}
      
      info ->
        %{
          total_memory: Keyword.get(info, :memory, 0),
          heap_size: Keyword.get(info, :heap_size, 0),
          stack_size: Keyword.get(info, :stack_size, 0),
          binary_memory: Keyword.get(info, :binary, []) |> length()
        }
    end
  end
  
  defp analyze_message_queue(pid) do
    case Process.info(pid, [:message_queue_len, :messages]) do
      nil ->
        %{error: "Process not found"}
      
      info ->
        queue_len = Keyword.get(info, :message_queue_len, 0)
        messages = Keyword.get(info, :messages, [])
        
        %{
          queue_length: queue_len,
          message_types: analyze_message_types(messages),
          oldest_message_age: estimate_oldest_message_age(messages),
          queue_health: assess_queue_health(queue_len)
        }
    end
  end
  
  defp get_performance_metrics(pid) do
    case Process.info(pid, [:reductions, :current_function, :status]) do
      nil ->
        %{error: "Process not found"}
      
      info ->
        %{
          reductions: Keyword.get(info, :reductions, 0),
          current_function: Keyword.get(info, :current_function),
          status: Keyword.get(info, :status),
          cpu_usage_relative: calculate_relative_cpu_usage(Keyword.get(info, :reductions, 0))
        }
    end
  end
  
  defp get_trace_information(pid) do
    # Check if tracing is enabled for this process
    flags = try do
      :erlang.trace_info(pid, :flags)
    rescue
      _ -> {:flags, []}
    end
    
    case flags do
      {:flags, trace_flags} when trace_flags != [] ->
        %{
          tracing_enabled: true,
          trace_flags: trace_flags,
          trace_status: "Active tracing detected"
        }
      
      _ ->
        %{
          tracing_enabled: false,
          trace_flags: [],
          trace_status: "No active tracing"
        }
    end
  end
  
  defp generate_process_recommendations(process_info) do
    recommendations = []
    
    # Memory recommendations
    memory_mb = div(process_info.memory, 1024 * 1024)
    recommendations = if memory_mb > 50 do
      ["High memory usage (#{memory_mb}MB) - investigate for memory leaks" | recommendations]
    else
      recommendations
    end
    
    # Message queue recommendations
    recommendations = if process_info.message_queue_length > 1000 do
      ["Very long message queue (#{process_info.message_queue_length}) - check for processing bottlenecks" | recommendations]
    else
      recommendations
    end
    
    # Reduction recommendations
    recommendations = if process_info.reductions > 50_000_000 do
      ["High CPU usage - consider process optimization" | recommendations]
    else
      recommendations
    end
    
    # Status recommendations
    recommendations = if process_info.status == :suspended do
      ["Process is suspended - check for deadlocks or debugging sessions" | recommendations]
    else
      recommendations
    end
    
    if length(recommendations) == 0 do
      ["Process appears healthy"]
    else
      recommendations
    end
  end
  
  defp matches_criteria?(process, criteria) do
    Enum.all?(criteria, fn {key, value} ->
      case key do
        :memory_greater_than -> process.memory > value
        :memory_less_than -> process.memory < value
        :queue_length_greater_than -> process.message_queue_length > value
        :reductions_greater_than -> process.reductions > value
        :status -> process.status == value
        :has_name -> (process.registered_name != nil) == value
        :initial_call_contains -> 
          process.initial_call && 
          String.contains?(inspect(process.initial_call), to_string(value))
        :link_count_greater_than -> length(process.links) > value
        _ -> true
      end
    end)
  end
  
  defp get_process_snapshot do
    case Arsenal.Operations.ListProcesses.execute(%{limit: 10000}) do
      {:ok, processes} ->
        Enum.into(processes, %{}, fn process ->
          {process.pid, %{
            registered_name: process.registered_name,
            initial_call: process.initial_call,
            memory: process.memory,
            reductions: process.reductions
          }}
        end)
      
      {:error, _} ->
        %{}
    end
  end
  
  defp analyze_lifecycle_changes(initial, final) do
    initial_pids = MapSet.new(Map.keys(initial))
    final_pids = MapSet.new(Map.keys(final))
    
    terminated = MapSet.difference(initial_pids, final_pids) |> MapSet.to_list()
    created = MapSet.difference(final_pids, initial_pids) |> MapSet.to_list()
    survived = MapSet.intersection(initial_pids, final_pids) |> MapSet.to_list()
    
    %{
      terminated_processes: length(terminated),
      created_processes: length(created),
      survived_processes: length(survived),
      termination_rate: length(terminated) / length(Map.keys(initial)),
      creation_rate: length(created) / length(Map.keys(initial)),
      stability_rate: length(survived) / length(Map.keys(initial)),
      terminated_details: Enum.map(terminated, &Map.get(initial, &1)),
      created_details: Enum.map(created, &Map.get(final, &1))
    }
  end
  
  defp build_process_tree(processes, root_pid) do
    # Build a tree structure showing process relationships
    process_map = Enum.into(processes, %{}, &{&1.pid, &1})
    
    if root_pid do
      build_subtree(root_pid, process_map, processes)
    else
      # Build forest of all top-level processes
      top_level = Enum.filter(processes, fn process ->
        is_top_level_process?(process, processes)
      end)
      
      Enum.map(top_level, &build_subtree(&1.pid, process_map, processes))
    end
  end
  
  defp build_subtree(pid, process_map, all_processes) do
    case Map.get(process_map, pid) do
      nil ->
        %{pid: pid, info: "Process not found", children: []}
      
      process ->
        children = find_child_processes(process, all_processes)
        child_trees = Enum.map(children, &build_subtree(&1.pid, process_map, all_processes))
        
        %{
          pid: process.pid,
          name: process.registered_name,
          initial_call: process.initial_call,
          memory_mb: div(process.memory, 1024 * 1024),
          status: process.status,
          children: child_trees
        }
    end
  end
  
  # Helper functions
  
  defp format_process_summary(process) do
    %{
      pid: inspect(process.pid),
      name: process.registered_name,
      memory_kb: div(process.memory, 1024),
      queue_length: process.message_queue_length
    }
  end
  
  defp calculate_memory_distribution(sorted_memory) do
    total = length(sorted_memory)
    
    %{
      p50: Enum.at(sorted_memory, div(total, 2)),
      p75: Enum.at(sorted_memory, div(total * 3, 4)),
      p90: Enum.at(sorted_memory, div(total * 9, 10)),
      p95: Enum.at(sorted_memory, div(total * 95, 100)),
      p99: Enum.at(sorted_memory, div(total * 99, 100))
    }
  end
  
  defp get_high_memory_processes(processes, count) do
    processes
    |> Enum.sort_by(& &1.memory, :desc)
    |> Enum.take(count)
    |> Enum.map(&format_process_summary/1)
  end
  
  defp get_busy_processes(processes, count) do
    processes
    |> Enum.sort_by(& &1.reductions, :desc)
    |> Enum.take(count)
    |> Enum.map(&format_process_summary/1)
  end
  
  defp find_parent_process(process, process_map) do
    # This is simplified - in practice you'd need to check supervision relationships
    case process.links do
      [] -> nil
      [parent_pid | _] -> Map.get(process_map, parent_pid)
    end
  end
  
  defp find_child_processes(process, all_processes) do
    # Find processes that link to this one
    Enum.filter(all_processes, fn other ->
      process.pid in other.links
    end)
  end
  
  defp is_top_level_process?(process, all_processes) do
    # Check if this process has any parent in the supervision tree
    not Enum.any?(all_processes, fn other ->
      process.pid in other.links && other.pid != process.pid
    end)
  end
  
  defp calculate_memory_threshold(processes) do
    memory_values = Enum.map(processes, & &1.memory)
    average = div(Enum.sum(memory_values), length(memory_values))
    average * 10  # 10x average as threshold
  end
  
  defp calculate_reduction_threshold(processes) do
    reduction_values = Enum.map(processes, & &1.reductions)
    average = div(Enum.sum(reduction_values), length(reduction_values))
    average * 5  # 5x average as threshold
  end
  
  defp analyze_message_types(messages) do
    messages
    |> Enum.map(&inspect/1)
    |> Enum.group_by(&String.split(&1, " ") |> hd())
    |> Enum.map(fn {type, msgs} -> {type, length(msgs)} end)
    |> Enum.into(%{})
  end
  
  defp estimate_oldest_message_age(_messages) do
    # This would require message timestamps, which aren't available
    # In practice, you'd need custom message tracking
    "Unknown - message timestamps not available"
  end
  
  defp assess_queue_health(queue_len) do
    cond do
      queue_len == 0 -> :healthy
      queue_len < 10 -> :good
      queue_len < 100 -> :warning
      true -> :critical
    end
  end
  
  defp calculate_relative_cpu_usage(reductions) do
    cond do
      reductions < 1_000_000 -> :low
      reductions < 10_000_000 -> :medium
      reductions < 100_000_000 -> :high
      true -> :very_high
    end
  end
  
  defp parse_pid(pid_string) do
    # Parse PID string like "<0.123.0>"
    case Regex.run(~r/<(\d+)\.(\d+)\.(\d+)>/, pid_string) do
      [_, a, b, c] ->
        try do
          pid = :c.pid(String.to_integer(a), String.to_integer(b), String.to_integer(c))
          {:ok, pid}
        rescue
          _ -> {:error, "Invalid PID format"}
        end
      
      _ ->
        {:error, "Invalid PID string format"}
    end
  end
end