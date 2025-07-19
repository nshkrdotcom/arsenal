# Arsenal Operations Design Document

## Architecture Overview

The Arsenal operations system implements a layered architecture that provides a unified interface for OTP operations across the APEX ecosystem. The design emphasizes modularity, extensibility, and distributed capabilities.

```
┌─────────────────────────────────────────────────────────┐
│                    REST API Layer                        │
│              (Phoenix Controllers)                       │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│               Arsenal Core Layer                         │
│    (Operation Registry, Routing, Analytics)              │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│              Operation Modules                           │
│   (Process, Supervisor, System, Distributed, etc.)       │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│              OTP/BEAM Runtime                            │
│         (Processes, Supervisors, Nodes)                  │
└─────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Arsenal.Operation Behaviour

```elixir
defmodule Arsenal.Operation do
  @type params :: map()
  @type result :: {:ok, any()} | {:error, term()}
  @type metadata :: map()

  @callback name() :: atom()
  @callback category() :: atom()
  @callback description() :: String.t()
  @callback params_schema() :: map()
  @callback execute(params()) :: result()
  @callback metadata() :: metadata()
  
  # Optional callbacks for advanced features
  @callback validate_params(params()) :: {:ok, params()} | {:error, term()}
  @callback authorize(params(), context :: map()) :: :ok | {:error, :unauthorized}
  @callback emit_telemetry(result(), metadata()) :: :ok
end
```

### 2. Arsenal.Registry

Central registry for all operations with discovery and introspection capabilities.

```elixir
defmodule Arsenal.Registry do
  use GenServer
  
  @type operation_info :: %{
    module: module(),
    name: atom(),
    category: atom(),
    description: String.t(),
    schema: map()
  }
  
  # API
  def register_operation(module)
  def unregister_operation(name)
  def get_operation(name)
  def list_operations(category \\ nil)
  def search_operations(query)
  def validate_operation_params(name, params)
  def execute_operation(name, params, context \\ %{})
end
```

### 3. Operation Categories

#### Process Operations Module

```elixir
defmodule Arsenal.Operations.Process do
  @moduledoc """
  Process lifecycle and management operations
  """
  
  defmodule StartProcess do
    use Arsenal.Operation
    
    def name(), do: :start_process
    def category(), do: :process
    def description(), do: "Start a new process with options"
    
    def params_schema() do
      %{
        module: [type: :atom, required: true],
        function: [type: :atom, required: true],
        args: [type: :list, default: []],
        options: [type: :map, default: %{}]
      }
    end
    
    def execute(params) do
      with {:ok, pid} <- do_start_process(params),
           :ok <- register_process(pid, params) do
        {:ok, %{pid: pid, registered: params[:options][:name]}}
      end
    end
  end
end
```

#### Supervisor Operations Module

```elixir
defmodule Arsenal.Operations.Supervisor do
  @moduledoc """
  Supervisor management and introspection operations
  """
  
  defmodule ListChildren do
    use Arsenal.Operation
    
    def name(), do: :which_children
    def category(), do: :supervisor
    
    def execute(%{supervisor: sup}) do
      children = Supervisor.which_children(sup)
      formatted = Enum.map(children, &format_child_info/1)
      {:ok, %{children: formatted, count: length(formatted)}}
    end
  end
end
```

#### Distributed Operations Module

```elixir
defmodule Arsenal.Operations.Distributed do
  @moduledoc """
  Multi-node and cluster operations
  """
  
  defmodule ClusterHealth do
    use Arsenal.Operation
    
    def name(), do: :cluster_health
    def category(), do: :distributed
    
    def execute(_params) do
      nodes = [node() | Node.list()]
      health_data = Enum.map(nodes, &check_node_health/1)
      {:ok, %{nodes: health_data, status: overall_status(health_data)}}
    end
  end
end
```

### 4. REST API Design

#### Endpoint Structure

```
GET    /api/v1/operations                    # List all operations
GET    /api/v1/operations/:category          # List operations by category
POST   /api/v1/operations/:name/execute      # Execute operation

# Convenience endpoints for common operations
GET    /api/v1/processes                     # List processes
POST   /api/v1/processes                     # Start process
GET    /api/v1/processes/:pid                # Get process info
DELETE /api/v1/processes/:pid                # Kill process

GET    /api/v1/supervisors                   # List supervisors
GET    /api/v1/supervisors/:id/children      # List children
POST   /api/v1/supervisors/:id/restart       # Restart supervisor

GET    /api/v1/cluster/health                # Cluster health
GET    /api/v1/cluster/topology              # Cluster topology
```

#### Controller Implementation

```elixir
defmodule ArsenalWeb.OperationController do
  use ArsenalWeb, :controller
  
  def index(conn, params) do
    operations = Arsenal.Registry.list_operations(params["category"])
    render(conn, "index.json", operations: operations)
  end
  
  def execute(conn, %{"name" => name} = params) do
    context = build_context(conn)
    
    case Arsenal.Registry.execute_operation(name, params, context) do
      {:ok, result} ->
        render(conn, "result.json", result: result)
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> render("error.json", error: reason)
    end
  end
end
```

### 5. Analytics Integration

```elixir
defmodule Arsenal.AnalyticsCollector do
  @moduledoc """
  Collects and aggregates operation metrics
  """
  
  def track_operation(operation, params, result, duration) do
    telemetry_event = build_telemetry_event(operation, result, duration)
    :telemetry.execute([:arsenal, :operation], telemetry_event, %{
      operation: operation,
      params: sanitize_params(params)
    })
  end
  
  def get_operation_stats(operation_name, time_range \\ :last_hour) do
    Arsenal.AnalyticsServer.query_stats(operation_name, time_range)
  end
end
```

### 6. Sandbox Integration

```elixir
defmodule Arsenal.Operations.Sandbox do
  @moduledoc """
  Sandbox-specific operations with isolation
  """
  
  defmodule ExecuteInSandbox do
    use Arsenal.Operation
    
    def execute(%{sandbox_id: id, operation: op, params: params}) do
      with {:ok, sandbox} <- Sandbox.Manager.get_sandbox(id),
           {:ok, result} <- Sandbox.IsolatedExecution.run(sandbox, op, params) do
        {:ok, %{sandbox_id: id, result: result}}
      end
    end
  end
end
```

### 7. Error Handling Strategy

```elixir
defmodule Arsenal.ErrorHandler do
  @moduledoc """
  Centralized error handling and recovery
  """
  
  @type error_class :: :validation | :authorization | :execution | :system
  
  def wrap_operation(operation, params, fun) do
    try do
      fun.()
    rescue
      e in [ArgumentError, KeyError] ->
        {:error, %{class: :validation, message: Exception.message(e)}}
      e in [ErlangError] ->
        handle_erlang_error(e)
    catch
      :exit, reason ->
        {:error, %{class: :system, message: inspect(reason)}}
    end
  end
  
  defp handle_erlang_error(%{original: {:noproc, _}}) do
    {:error, %{class: :execution, message: "Process not found"}}
  end
end
```

### 8. Testing Framework

```elixir
defmodule Arsenal.TestSupport do
  @moduledoc """
  Testing utilities for Arsenal operations
  """
  
  defmacro assert_operation_success(operation, params) do
    quote do
      result = Arsenal.Registry.execute_operation(unquote(operation), unquote(params))
      assert {:ok, _} = result
      result
    end
  end
  
  def with_test_cluster(nodes, fun) do
    ClusterTest.Manager.start_cluster(nodes)
    try do
      fun.()
    after
      ClusterTest.Manager.stop_cluster()
    end
  end
end
```

## Data Flow

### Operation Execution Flow

1. **Request Reception**: REST endpoint receives operation request
2. **Authentication**: Verify caller credentials
3. **Parameter Validation**: Schema validation against operation definition
4. **Authorization**: Check permissions for operation
5. **Pre-execution Hooks**: Telemetry, logging, rate limiting
6. **Operation Execution**: Delegate to operation module
7. **Result Processing**: Format response data
8. **Post-execution Hooks**: Analytics, audit logging
9. **Response Delivery**: Return formatted JSON response

### State Management

```elixir
defmodule Arsenal.StateManager do
  @moduledoc """
  Manages operation state and history
  """
  
  use GenServer
  
  defstruct [
    :operations_history,
    :active_operations,
    :operation_results
  ]
  
  def record_operation(operation, params, result) do
    GenServer.cast(__MODULE__, {:record, operation, params, result})
  end
  
  def get_operation_history(operation_name, limit \\ 100) do
    GenServer.call(__MODULE__, {:history, operation_name, limit})
  end
end
```

## Security Considerations

### Authentication

- API key-based authentication for programmatic access
- JWT tokens for web UI access
- mTLS for inter-node communication

### Authorization

```elixir
defmodule Arsenal.Authorization do
  @moduledoc """
  Role-based access control for operations
  """
  
  @operation_permissions %{
    start_process: [:admin, :operator],
    kill_process: [:admin],
    list_processes: [:admin, :operator, :viewer],
    cluster_health: [:admin, :operator, :viewer]
  }
  
  def authorize(operation, user_roles) do
    allowed_roles = Map.get(@operation_permissions, operation, [])
    
    if Enum.any?(user_roles, &(&1 in allowed_roles)) do
      :ok
    else
      {:error, :unauthorized}
    end
  end
end
```

### Input Sanitization

- Parameter type validation
- Size limits on collections
- Rate limiting per operation type
- SQL injection prevention for analytics queries

## Performance Optimizations

### Caching Strategy

```elixir
defmodule Arsenal.Cache do
  @moduledoc """
  Caching layer for expensive operations
  """
  
  def get_or_compute(key, ttl, fun) do
    case get(key) do
      {:ok, value} -> 
        {:ok, value}
      :miss ->
        value = fun.()
        put(key, value, ttl)
        {:ok, value}
    end
  end
end
```

### Batch Operations

```elixir
defmodule Arsenal.BatchProcessor do
  @moduledoc """
  Efficient batch operation processing
  """
  
  def execute_batch(operations) do
    operations
    |> Task.async_stream(&execute_single/1, max_concurrency: 10)
    |> Enum.map(&handle_result/1)
  end
end
```

## Monitoring and Observability

### Metrics Collection

- Operation execution count
- Operation duration percentiles
- Error rates by operation type
- Resource usage per operation

### Distributed Tracing

```elixir
defmodule Arsenal.Tracing do
  @moduledoc """
  Distributed tracing integration
  """
  
  def with_span(operation, fun) do
    span = start_span(operation)
    try do
      result = fun.()
      set_span_status(span, :ok)
      result
    rescue
      e ->
        set_span_status(span, :error)
        record_exception(span, e)
        reraise e, __STACKTRACE__
    after
      end_span(span)
    end
  end
end
```

## Extension Points

### Custom Operations

Developers can add custom operations by implementing the `Arsenal.Operation` behaviour:

```elixir
defmodule MyApp.Operations.CustomOperation do
  use Arsenal.Operation
  
  def name(), do: :my_custom_op
  def category(), do: :custom
  
  def execute(params) do
    # Custom logic here
    {:ok, %{result: "success"}}
  end
end

# Registration
Arsenal.Registry.register_operation(MyApp.Operations.CustomOperation)
```

### Middleware Pipeline

```elixir
defmodule Arsenal.Middleware do
  @moduledoc """
  Pluggable middleware for operation processing
  """
  
  def build_pipeline(operation) do
    [
      &validate_params/2,
      &authorize/2,
      &rate_limit/2,
      &execute/2,
      &emit_telemetry/2
    ]
  end
end
```

## Migration Strategy

### Phase 1: Core Operations
- Implement basic process operations
- Establish REST API structure
- Set up operation registry

### Phase 2: Advanced Features
- Add supervisor operations
- Implement distributed operations
- Enable analytics collection

### Phase 3: Integration
- Sandbox integration
- ClusterTest support
- SuperLearner analytics

### Phase 4: Production Hardening
- Performance optimization
- Security audit
- Monitoring enhancement