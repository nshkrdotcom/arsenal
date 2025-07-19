# Process Management Examples

This directory demonstrates advanced process management capabilities using Arsenal's process operations, including inspection, control, and tracing tools.

## Examples Overview

### 1. `process_inspector.ex` - Advanced Process Analysis
Comprehensive process inspection and analysis tools for understanding system behavior.

**Features:**
- **Complete Process Analysis**: Detailed analysis of all system processes
- **Process Categorization**: Automatic categorization (GenServer, Task, Agent, etc.)
- **Memory and Performance Analysis**: Resource usage patterns and outliers
- **Relationship Mapping**: Process links, monitors, and supervision trees
- **Lifecycle Tracking**: Process creation and termination patterns
- **Outlier Detection**: Identify processes with unusual resource usage
- **Process Tree Visualization**: Hierarchical process relationships

**Usage:**
```elixir
# Analyze all processes in the system
{:ok, analysis} = Examples.ProcessManagement.ProcessInspector.analyze_all_processes()

# Returns comprehensive analysis:
%{
  summary: %{
    total_processes: 1247,
    alive_processes: 1245,
    total_memory_mb: 156,
    average_memory_kb: 128
  },
  categorization: [
    %{category: :genserver, count: 45, total_memory_mb: 23},
    %{category: :supervisor, count: 12, total_memory_mb: 5}
  ],
  memory_analysis: %{...},
  performance_analysis: %{...},
  relationships: %{...},
  outliers: %{...},
  recommendations: [...]
}

# Inspect a specific process in detail
{:ok, details} = Examples.ProcessManagement.ProcessInspector.inspect_process(self())

# Find processes matching criteria
{:ok, results} = Examples.ProcessManagement.ProcessInspector.find_processes([
  {:memory_greater_than, 10 * 1024 * 1024},  # >10MB
  {:queue_length_greater_than, 100}
])

# Generate process tree visualization
{:ok, tree} = Examples.ProcessManagement.ProcessInspector.generate_process_tree()

# Track process lifecycle changes over time
task = Examples.ProcessManagement.ProcessInspector.track_process_lifecycle(60)
```

### 2. `process_controller.ex` - Process Lifecycle Management
High-level process management with automated policies and health monitoring.

**Features:**
- **Batch Process Operations**: Start, stop, restart multiple processes safely
- **Health Monitoring**: Continuous process health assessment
- **Automated Policies**: Rule-based process management
- **Resource Management**: Kill processes consuming too many resources  
- **Statistics and Reporting**: Comprehensive management statistics
- **Safety Features**: Validation, timeouts, and graceful handling

**Usage:**
```elixir
# Start the process controller
{:ok, _pid} = Examples.ProcessManagement.ProcessController.start_link()

# Start multiple processes with validation
process_specs = [
  %{module: GenServer, function: :start_link, args: [MyWorker, []]},
  %{module: Task, function: :start, args: [fn -> work() end]}
]

{:ok, results} = Examples.ProcessManagement.ProcessController.start_processes(process_specs)
# Returns: %{successful: [...], failed: [...], total_started: 1, total_failed: 1}

# Stop processes gracefully
{:ok, _} = Examples.ProcessManagement.ProcessController.stop_processes([pid1, pid2], 5000)

# Restart processes matching criteria
{:ok, _} = Examples.ProcessManagement.ProcessController.restart_matching_processes([
  {:memory_greater_than, 50 * 1024 * 1024}
])

# Kill resource-consuming processes
{:ok, _} = Examples.ProcessManagement.ProcessController.kill_resource_hogs(%{
  memory_mb: 100,
  queue_length: 10000,
  reductions: 100_000_000
})

# Configure automated management policies
policies = [
  %Examples.ProcessManagement.ProcessController.ProcessPolicy{
    name: "restart_dead_critical_processes",
    conditions: [:process_dead, {:has_name, true}],
    actions: [:restart],
    cooldown_seconds: 60,
    max_actions_per_hour: 10,
    enabled: true
  }
]
:ok = Examples.ProcessManagement.ProcessController.configure_policies(policies)

# Get management statistics
stats = Examples.ProcessManagement.ProcessController.get_stats()

# Perform health check on all managed processes
{:ok, health_results} = Examples.ProcessManagement.ProcessController.health_check()
```

### 3. `tracing_tools.ex` - Advanced Process Tracing
Sophisticated tracing and debugging tools with automatic cleanup and analysis.

**Features:**
- **Safe Process Tracing**: Automatic cleanup and timeout handling
- **Message Flow Analysis**: Track message patterns between processes
- **Performance Profiling**: Function call analysis and hot-spot detection
- **Call Stack Tracing**: Detailed function call tracing
- **Distributed Tracing**: Cross-node process tracing (when applicable)
- **Trace Session Management**: Multiple concurrent trace sessions
- **Event Filtering**: Focus on relevant trace events

**Usage:**
```elixir
# Start the tracing tools
{:ok, _pid} = Examples.ProcessManagement.TracingTools.start_link()

# Start tracing a process
{:ok, trace_id} = Examples.ProcessManagement.TracingTools.start_trace(pid, [
  flags: [:send, :receive, :call, :return],
  duration_seconds: 30,
  filters: [
    {:type, :send},
    {:module, MyModule}
  ]
])

# Get trace results
{:ok, results} = Examples.ProcessManagement.TracingTools.get_trace_results(trace_id)
# Returns: %{session: %{...}, events: [...], summary: %{...}}

# Analyze message flow between processes
{:ok, flow_analysis} = Examples.ProcessManagement.TracingTools.analyze_message_flow(
  [pid1, pid2, pid3], 
  10  # duration in seconds
)

# Profile a process for performance
{:ok, profile} = Examples.ProcessManagement.TracingTools.profile_process(pid, 30)
# Returns: %{function_calls: 1234, hot_functions: [...], call_tree: %{...}}

# Trace specific function calls
{:ok, call_trace_id} = Examples.ProcessManagement.TracingTools.trace_calls(
  pid, 
  MyModule,    # module pattern
  :my_function # function pattern
)

# List all active traces
traces = Examples.ProcessManagement.TracingTools.list_traces()

# Stop a specific trace
:ok = Examples.ProcessManagement.TracingTools.stop_trace(trace_id)

# Emergency cleanup (stop all traces)
:ok = Examples.ProcessManagement.TracingTools.stop_all_traces()
```

## Integration with Arsenal Operations

These examples build upon Arsenal's built-in process operations:

### Core Process Operations
```elixir
# List processes with filtering and sorting
{:ok, processes} = Arsenal.Registry.execute(:list_processes, %{
  limit: 100,
  sort_by: "memory",
  filter_by: %{status: "running"}
})

# Get detailed process information
{:ok, info} = Arsenal.Registry.execute(:get_process_info, %{pid: self()})

# Start a new process
{:ok, result} = Arsenal.Registry.execute(:start_process, %{
  module: GenServer,
  function: :start_link,
  args: [MyWorker, []],
  options: %{name: :my_worker}
})

# Kill a process
{:ok, _} = Arsenal.Registry.execute(:kill_process, %{
  pid: pid,
  reason: :normal
})

# Restart a supervised process
{:ok, _} = Arsenal.Registry.execute(:restart_process, %{pid: pid})

# Send a message to a process
{:ok, _} = Arsenal.Registry.execute(:send_message, %{
  pid: pid,
  message: {:hello, "world"}
})

# Enable tracing on a process
{:ok, _} = Arsenal.Registry.execute(:trace_process, %{
  pid: pid,
  flags: [:send, :receive],
  duration: 30000
})
```

### Supervisor Operations
```elixir
# List all supervisors
{:ok, supervisors} = Arsenal.Registry.execute(:list_supervisors, %{})

# Each supervisor includes:
# - name, pid, children_count
# - strategy (one_for_one, one_for_all, etc.)
# - max_restarts, max_seconds
# - restart statistics
```

## Advanced Use Cases

### 1. Memory Leak Detection
```elixir
# Find processes with growing memory usage
defmodule MemoryLeakDetector do
  def detect_leaks do
    # Take two snapshots 5 minutes apart
    snapshot1 = get_memory_snapshot()
    Process.sleep(5 * 60 * 1000)
    snapshot2 = get_memory_snapshot()
    
    # Find processes with significant memory growth
    growing_processes = find_memory_growth(snapshot1, snapshot2)
    
    # Start detailed tracing on suspicious processes
    Enum.each(growing_processes, fn {pid, growth} ->
      if growth > 10 * 1024 * 1024 do  # >10MB growth
        Examples.ProcessManagement.TracingTools.start_trace(pid, [
          flags: [:call, :return],
          duration_seconds: 300,
          filters: [{:module, :erlang}, {:function, :binary_to_term}]
        ])
      end
    end)
  end
  
  defp get_memory_snapshot do
    {:ok, processes} = Arsenal.Registry.execute(:list_processes, %{limit: 10000})
    Enum.into(processes, %{}, &{&1.pid, &1.memory})
  end
  
  defp find_memory_growth(snapshot1, snapshot2) do
    Enum.map(snapshot2, fn {pid, memory2} ->
      memory1 = Map.get(snapshot1, pid, 0)
      {pid, memory2 - memory1}
    end)
    |> Enum.filter(fn {_pid, growth} -> growth > 0 end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end
end
```

### 2. Process Performance Analysis
```elixir
# Identify CPU-intensive processes
defmodule PerformanceAnalyzer do
  def find_cpu_intensive_processes do
    {:ok, analysis} = Examples.ProcessManagement.ProcessInspector.analyze_all_processes()
    
    # Get processes with high reduction counts
    high_cpu = analysis.performance_analysis.busy_processes
    
    # Profile each one for detailed analysis
    Enum.map(high_cpu, fn process ->
      pid = String.to_existing_atom(process.pid)
      
      case Examples.ProcessManagement.TracingTools.profile_process(pid, 60) do
        {:ok, profile} ->
          %{
            pid: process.pid,
            reductions: process.reductions,
            hot_functions: profile.hot_functions,
            optimization_suggestions: suggest_optimizations(profile)
          }
        
        {:error, reason} ->
          %{pid: process.pid, error: reason}
      end
    end)
  end
  
  defp suggest_optimizations(profile) do
    suggestions = []
    
    # Check for expensive function calls
    suggestions = if length(profile.hot_functions) > 0 do
      ["Consider optimizing hot functions: #{inspect(profile.hot_functions)}" | suggestions]
    else
      suggestions
    end
    
    # More analysis...
    suggestions
  end
end
```

### 3. Automated Recovery System
```elixir
# Comprehensive process health and recovery
defmodule ProcessRecoverySystem do
  use GenServer
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  
  def init(_opts) do
    # Start monitoring subsystems
    {:ok, _} = Examples.ProcessManagement.ProcessController.start_link()
    {:ok, _} = Examples.ProcessManagement.TracingTools.start_link()
    
    # Configure recovery policies
    recovery_policies = [
      %{
        name: "memory_leak_recovery",
        trigger: {:memory_greater_than, 200 * 1024 * 1024},
        action: :restart_with_tracing,
        escalation: :kill_after_timeout
      },
      %{
        name: "queue_backlog_recovery", 
        trigger: {:queue_length_greater_than, 5000},
        action: :trace_and_alert,
        escalation: :restart_if_growing
      }
    ]
    
    Examples.ProcessManagement.ProcessController.configure_policies(recovery_policies)
    
    schedule_health_scan()
    {:ok, %{}}
  end
  
  def handle_info(:health_scan, state) do
    # Comprehensive system health check
    perform_recovery_scan()
    schedule_health_scan()
    {:noreply, state}
  end
  
  defp perform_recovery_scan do
    # Get system analysis
    case Examples.ProcessManagement.ProcessInspector.analyze_all_processes() do
      {:ok, analysis} ->
        # Check for various issues
        check_memory_issues(analysis.outliers.memory_outliers)
        check_performance_issues(analysis.outliers.performance_outliers)
        check_queue_issues(analysis.outliers.queue_outliers)
        
        # Apply recommendations
        apply_system_recommendations(analysis.recommendations)
      
      {:error, reason} ->
        Logger.error("Failed to perform recovery scan: #{inspect(reason)}")
    end
  end
  
  defp schedule_health_scan do
    Process.send_after(self(), :health_scan, 60_000)  # Every minute
  end
  
  # Implementation of check and recovery functions...
end
```

## Production Considerations

### 1. Resource Usage
- **Tracing Overhead**: Tracing can impact performance - use judiciously
- **Memory Growth**: Trace events consume memory - set appropriate durations
- **CPU Impact**: Process analysis operations can be CPU-intensive

### 2. Safety Features
- **Automatic Cleanup**: All tracing sessions have automatic timeouts
- **Validation**: Process operations validate inputs before execution
- **Error Handling**: Graceful handling of process termination during operations

### 3. Monitoring Integration
```elixir
# Export process management metrics
defmodule ProcessMetricsExporter do
  def export_metrics do
    stats = Examples.ProcessManagement.ProcessController.get_stats()
    
    # Export to Prometheus
    :prometheus_gauge.set(:process_controller_managed_processes, stats.managed_processes_count)
    :prometheus_counter.inc(:process_controller_processes_started, stats.processes_started)
    :prometheus_counter.inc(:process_controller_processes_killed, stats.processes_killed)
    
    # Export to custom monitoring
    MyMonitoring.send_metrics("process_management", stats)
  end
end
```

### 4. Security Considerations
- **Access Control**: Restrict process control operations to authorized users
- **Audit Logging**: Log all process management actions
- **Rate Limiting**: Prevent abuse of resource-intensive operations

## Running the Examples

1. **Start Arsenal and Operations**:
```elixir
Arsenal.start(:normal, [])
Arsenal.Registry.register(:list_processes, Arsenal.Operations.ListProcesses)
Arsenal.Registry.register(:get_process_info, Arsenal.Operations.GetProcessInfo)
Arsenal.Registry.register(:start_process, Arsenal.Operations.StartProcess)
Arsenal.Registry.register(:kill_process, Arsenal.Operations.KillProcess)
```

2. **Start Process Management Tools**:
```elixir
Examples.ProcessManagement.ProcessController.start_link()
Examples.ProcessManagement.TracingTools.start_link()
```

3. **Perform Process Analysis**:
```elixir
Examples.ProcessManagement.ProcessInspector.analyze_all_processes()
```

4. **Set up Monitoring and Recovery**:
```elixir
ProcessRecoverySystem.start_link([])
```

These examples provide a comprehensive toolkit for process management, from basic inspection to advanced tracing and automated recovery systems.