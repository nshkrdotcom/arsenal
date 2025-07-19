# Arsenal

**A metaprogramming framework for building REST APIs from OTP operations**

Arsenal enables automatic REST API generation by defining operations as simple Elixir modules with behavior callbacks. It provides a registry system, operation discovery, parameter validation, and OpenAPI documentation generation.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [Creating Operations](#creating-operations)
- [Framework Adapters](#framework-adapters)
- [Advanced Features](#advanced-features)
- [API Documentation](#api-documentation)
- [Development Guide](#development-guide)
- [Testing](#testing)
- [Contributing](#contributing)

## Overview

Arsenal is a powerful metaprogramming framework that transforms Elixir modules into REST API endpoints. It's designed for OTP-focused applications that need to expose system monitoring, management, and debugging capabilities through a standardized REST interface.

### Key Features

- **Automatic REST API Generation**: Define operations as modules, get REST endpoints automatically
- **Operation Registry**: Automatic discovery and registration of operations
- **Parameter Validation**: Built-in validation with custom validators support
- **OpenAPI Documentation**: Auto-generated API documentation
- **Framework Agnostic**: Adapter-based design works with any web framework
- **Analytics & Monitoring**: Production-grade system monitoring with `Arsenal.AnalyticsServer`
- **Distributed System Support**: Built-in operations for cluster management (when available)
- **Process Management**: Comprehensive process inspection, tracing, and control operations

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Web Framework  │───▶│     Adapter     │────▶│     Arsenal     │
│  (Phoenix/Plug) │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────┬───────┘
                                                          │
                                   ┌──────────────────────┼─────────────────────┐
                                   │                      │                     │
                            ┌──────▼──────┐       ┌───────▼───────┐      ┌──────▼──────┐
                            │  Registry   │       │  Operations   │      │  Analytics  │
                            │             │       │               │      │   Server    │
                            └─────────────┘       └───────────────┘      └─────────────┘
```

## Core Components

### 1. Arsenal Module (`lib/arsenal.ex`)

The main entry point and application supervisor.

```elixir
# Start Arsenal
{:ok, _pid} = Arsenal.start(:normal, [])

# List all registered operations
operations = Arsenal.list_operations()

# Execute an operation by name (V2)
{:ok, result} = Arsenal.Registry.execute(:list_processes, %{"limit" => 10})

# Execute an operation by module (V1 compatibility)
{:ok, result} = Arsenal.execute_operation(
  Arsenal.Operations.ListProcesses,
  %{"limit" => 10}
)

# Generate OpenAPI documentation
api_docs = Arsenal.generate_api_docs()
```

### 2. V2 Operation Behavior (`lib/arsenal/operation.ex`)

The enhanced V2 operation framework provides a standardized contract for all operations:

```elixir
defmodule Arsenal.Operation do
  @callback name() :: atom()
  @callback category() :: atom()
  @callback description() :: String.t()
  @callback params_schema() :: map()
  @callback execute(params :: map()) :: {:ok, term()} | {:error, term()}
  @callback metadata() :: map()
  @callback rest_config() :: map()
  
  # Optional callbacks
  @callback validate_params(params :: map()) :: {:ok, map()} | {:error, term()}
  @callback format_response(result :: term()) :: map()
  @callback authorize(params :: map(), context :: map()) :: :ok | {:error, term()}
  
  @optional_callbacks [validate_params: 1, format_response: 1, authorize: 2]
end
```

Key improvements in V2:
- **Named Operations**: Operations are registered by name for stable API
- **Categories**: Operations are organized into logical categories
- **Automated Validation**: Validation based on `params_schema/0`
- **Built-in Telemetry**: Automatic telemetry events for all operations
- **Standardized Metadata**: Consistent metadata for auth, rate limiting, etc.

### 3. Enhanced Registry V2 (`lib/arsenal/registry.ex`)

The V2 Registry serves as a central hub for the entire operation lifecycle:

```elixir
# Register operations by name
Arsenal.Registry.register(:my_operation, MyApp.Operations.MyOperation)

# Execute operations with built-in validation and telemetry
{:ok, result} = Arsenal.Registry.execute(:list_processes, %{"limit" => 10})

# Get operation metadata
{:ok, metadata} = Arsenal.Registry.get_metadata(:list_processes)

# List operations by category
operations = Arsenal.Registry.list_by_category(:process)

# Introspect operation schema
{:ok, schema} = Arsenal.Registry.get_params_schema(:start_process)

# V1 Compatibility - still works
Arsenal.Registry.register_operation(MyOperation)
{:ok, config} = Arsenal.Registry.get_operation(MyOperation)
```

Key V2 Registry features:
- **Lifecycle Management**: Handles discovery, validation, authorization, and execution
- **Named Registration**: Operations registered by atom names for API stability
- **Automatic Validation**: Validates params against schema before execution
- **Telemetry Integration**: Emits standardized events for monitoring
- **Authorization Hooks**: Built-in support for operation-level authorization

### 4. Adapter (`lib/arsenal/adapter.ex`)

Framework-agnostic adapter behavior for integrating with web frameworks:

```elixir
defmodule Arsenal.Adapter do
  @callback extract_method(request :: any()) :: atom()
  @callback extract_path(request :: any()) :: String.t()
  @callback extract_params(request :: any()) :: map()
  @callback send_response(request :: any(), status :: integer(), body :: map()) :: any()
  @callback send_error(request :: any(), status :: integer(), error :: any()) :: any()
  
  @optional_callbacks [before_process: 1, after_process: 2]
end
```

### 5. Analytics Server (`lib/arsenal/analytics_server.ex`)

Production-grade monitoring and analytics:

```elixir
# Track restart events
Arsenal.AnalyticsServer.track_restart(:my_supervisor, :worker_1, :normal)

# Get system health
{:ok, health} = Arsenal.AnalyticsServer.get_system_health()

# Subscribe to events
Arsenal.AnalyticsServer.subscribe_to_events([:restart, :health_alert])

# Get performance metrics
{:ok, metrics} = Arsenal.AnalyticsServer.get_performance_metrics()
```

## V2 Operation Framework

Arsenal V2 introduces a robust, standardized framework for operations that reduces boilerplate and improves consistency across the codebase.

### Migration Path and Compatibility Mode

To ensure a smooth transition, Arsenal V2 includes a compatibility mode that allows existing V1 operations to work without modification:

```elixir
defmodule MyApp.Operations.LegacyOperation do
  use Arsenal.Operation, compat: true  # Enable compatibility mode
  
  # V1 callbacks continue to work
  @impl true
  def rest_config do
    %{
      method: :get,
      path: "/api/v1/legacy/:id",
      summary: "Legacy operation"
    }
  end
  
  @impl true
  def execute(params) do
    # Your existing logic
  end
end
```

All existing operations in Arsenal have been updated to use `compat: true`, allowing them to function within the V2 framework while migration happens gradually.

### V2 Operation Example

Here's a complete V2 operation showcasing the new features:

```elixir
defmodule Arsenal.OperationsV2.Process.StartProcess do
  use Arsenal.Operation
  
  @impl true
  def name(), do: :start_process
  
  @impl true
  def category(), do: :process
  
  @impl true
  def description(), do: "Start a new process with configurable options"
  
  @impl true
  def params_schema() do
    %{
      module: [type: :atom, required: true],
      function: [type: :atom, required: true],
      args: [type: :list, default: []],
      options: [type: :map, default: %{}],
      name: [type: :atom, required: false],
      link: [type: :boolean, default: false],
      monitor: [type: :boolean, default: false]
    }
  end
  
  @impl true
  def metadata() do
    %{
      requires_authentication: true,
      minimum_role: :operator,
      idempotent: false,
      timeout: 5_000,
      rate_limit: {10, :minute}
    }
  end
  
  @impl true
  def rest_config() do
    %{
      method: :post,
      path: "/api/v1/processes",
      summary: "Start a new process",
      responses: %{
        201 => %{description: "Process started successfully"},
        400 => %{description: "Invalid parameters"},
        409 => %{description: "Process with given name already exists"}
      }
    }
  end
  
  @impl true
  def execute(params) do
    # Params are already validated based on params_schema
    # Telemetry events are automatically emitted
    # Authorization has already been checked
    
    with {:ok, pid} <- start_process_logic(params) do
      {:ok, %{pid: pid, started_at: DateTime.utc_now()}}
    end
  end
end
```

### Automated Validation and Telemetry

The V2 framework automatically handles common patterns:

#### Parameter Validation
Parameters are validated against the schema before execution:

```elixir
# This happens automatically before execute/1 is called
{:ok, validated_params} = Arsenal.Operation.Validator.validate(
  params,
  operation.params_schema()
)
```

#### Telemetry Events
Standard telemetry events are emitted for every operation:

```elixir
# Automatic events emitted by the framework:
[:arsenal, :operation, :start]
[:arsenal, :operation, :stop]
[:arsenal, :operation, :exception]

# Subscribe to operation events
:telemetry.attach_many(
  "arsenal-handler",
  [
    [:arsenal, :operation, :start],
    [:arsenal, :operation, :stop]
  ],
  &handle_event/4,
  nil
)
```

### Mix Task for Operation Generation

Arsenal V2 includes a Mix task to generate new operations:

```bash
# Generate a new V2 operation
mix arsenal.gen.operation MyApp.Operations.MyNewOperation \
  --name my_operation \
  --category custom \
  --method post \
  --path "/api/v1/my-operation"
```

## Creating Operations

### Basic Operation Example

```elixir
defmodule MyApp.Operations.GetUserInfo do
  use Arsenal.Operation

  @impl true
  def rest_config do
    %{
      method: :get,
      path: "/api/v1/users/:id",
      summary: "Get user information by ID",
      parameters: [
        %{
          name: :id,
          type: :integer,
          required: true,
          location: :path,
          description: "User ID"
        }
      ],
      responses: %{
        200 => %{description: "User found"},
        404 => %{description: "User not found"}
      }
    }
  end

  @impl true
  def validate_params(%{"id" => id}) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> {:ok, %{"id" => int_id}}
      _ -> {:error, {:invalid_parameter, :id, "must be an integer"}}
    end
  end

  @impl true
  def execute(%{"id" => id}) do
    case MyApp.Users.get_user(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @impl true
  def format_response(user) do
    %{
      data: %{
        id: user.id,
        name: user.name,
        email: user.email
      }
    }
  end
end
```

### Operation Configuration

The `rest_config/0` callback returns a map with:

- `method`: HTTP method (`:get`, `:post`, `:put`, `:delete`, `:patch`)
- `path`: URL path with parameter placeholders (e.g., `/api/v1/resource/:id`)
- `summary`: Human-readable operation description
- `parameters`: List of parameter definitions
- `responses`: Map of status codes to response descriptions

Parameter definitions include:
- `name`: Parameter name
- `type`: Data type (`:string`, `:integer`, `:boolean`, `:array`, `:object`)
- `required`: Whether the parameter is required
- `location`: Where the parameter comes from (`:path`, `:query`, `:body`)
- `description`: Human-readable description

## Framework Adapters

### Creating a Phoenix Adapter

```elixir
defmodule MyApp.ArsenalPhoenixAdapter do
  @behaviour Arsenal.Adapter

  @impl true
  def extract_method(%Plug.Conn{method: method}) do
    method |> String.downcase() |> String.to_atom()
  end

  @impl true
  def extract_path(%Plug.Conn{request_path: path}), do: path

  @impl true
  def extract_params(%Plug.Conn{} = conn) do
    conn.params
  end

  @impl true
  def send_response(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  @impl true
  def send_error(conn, status, error) do
    send_response(conn, status, error)
  end
end
```

### Using the Adapter in Phoenix

```elixir
defmodule MyAppWeb.ArsenalController do
  use MyAppWeb, :controller

  def handle(conn, _params) do
    Arsenal.Adapter.process_request(MyApp.ArsenalPhoenixAdapter, conn)
  end
end

# In router.ex
scope "/api", MyAppWeb do
  pipe_through :api
  
  # Route all Arsenal operations through the adapter
  forward "/v1", ArsenalController, :handle
end
```

## Advanced Features

### Analytics and Monitoring

Arsenal includes a comprehensive analytics server that monitors:

- **System Health**: CPU, memory, process count, message queues
- **Restart Tracking**: Supervisor restart events and patterns
- **Performance Metrics**: Real-time system performance data
- **Anomaly Detection**: Automatic detection of unusual patterns
- **Event Subscriptions**: Real-time notifications for system events

```elixir
# Subscribe to all events
Arsenal.AnalyticsServer.subscribe_to_events([:all])

# Get historical data
{:ok, history} = Arsenal.AnalyticsServer.get_historical_data(
  DateTime.add(DateTime.utc_now(), -3600, :second),
  DateTime.utc_now()
)

# Get restart statistics
{:ok, stats} = Arsenal.AnalyticsServer.get_restart_statistics(:my_supervisor)
```

### Process Management Operations

Arsenal includes built-in operations for process management:

- **ListProcesses**: List all system processes with sorting and filtering
- **GetProcessInfo**: Get detailed information about a specific process
- **TraceProcess**: Enable tracing on a process with configurable flags
- **SendMessage**: Send messages to processes (when implemented)
- **KillProcess**: Terminate processes (when implemented)

### Distributed Operations

For distributed Elixir systems, Arsenal provides:

- **ClusterTopology**: View cluster topology and node connectivity
- **NodeInfo**: Get detailed information about specific nodes
- **ProcessList**: List processes across the cluster
- **ClusterHealth**: Monitor cluster-wide health metrics
- **HordeRegistryInspect**: Inspect Horde registry state (when using Horde)

### Sandbox Operations

For testing and isolation:

- **CreateSandbox**: Create isolated supervisor trees
- **ListSandboxes**: View all active sandboxes
- **GetSandboxInfo**: Get detailed sandbox information
- **RestartSandbox**: Restart a sandbox supervisor
- **DestroySandbox**: Clean up sandboxes
- **HotReloadSandbox**: Hot-reload sandbox code

## API Documentation

Arsenal automatically generates OpenAPI 3.0 documentation:

```elixir
docs = Arsenal.generate_api_docs()

# Returns:
%{
  openapi: "3.0.0",
  info: %{
    title: "Arsenal API",
    version: "1.0.0",
    description: "Comprehensive OTP process and supervisor management API"
  },
  servers: [...],
  paths: %{
    "/api/v1/processes" => %{
      get: %{
        summary: "List all processes in the system",
        parameters: [...],
        responses: %{...}
      }
    },
    # ... more paths
  }
}
```

## Development Guide

### Project Structure

```
arsenal/
├── lib/
│   ├── arsenal.ex                    # Main module and application
│   └── arsenal/
│       ├── adapter.ex                # Web framework adapter behavior
│       ├── analytics_server.ex       # System monitoring and analytics
│       ├── operation.ex              # Operation behavior definition
│       ├── registry.ex               # Operation registry
│       └── operations/               # Built-in operations
│           ├── create_sandbox.ex
│           ├── get_process_info.ex
│           ├── list_processes.ex
│           ├── trace_process.ex
│           └── distributed/          # Distributed system operations
├── test/
│   └── arsenal_test.exs            # Test suite
└── mix.exs                          # Project configuration
```

### Adding New Operations

1. Create a new module in `lib/arsenal/operations/`
2. Implement the `Arsenal.Operation` behavior
3. Define REST configuration with `rest_config/0`
4. Implement parameter validation (optional)
5. Implement the `execute/1` function
6. Format the response (optional)

### Best Practices

1. **Parameter Validation**: Always validate and sanitize input parameters
2. **Error Handling**: Return consistent error tuples `{:error, reason}`
3. **Documentation**: Include comprehensive descriptions in `rest_config/0`
4. **Testing**: Write tests for parameter validation and execution logic
5. **Performance**: Consider performance implications for operations that list many items

## Testing

Run the test suite:

```bash
mix test
```

Example test for a custom operation:

```elixir
defmodule MyOperationTest do
  use ExUnit.Case

  test "validates parameters correctly" do
    assert {:ok, %{"id" => 123}} = 
      MyOperation.validate_params(%{"id" => "123"})
      
    assert {:error, _} = 
      MyOperation.validate_params(%{"id" => "invalid"})
  end

  test "executes successfully" do
    assert {:ok, result} = 
      MyOperation.execute(%{"id" => 123})
  end
end
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`mix test`)
5. Run code analysis (`mix dialyzer`)
6. Commit your changes (`git commit -m 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Development Setup

```bash
# Clone the repository
git clone https://github.com/nshkrdotcom/arsenal.git
cd arsenal

# Install dependencies
mix deps.get

# Run tests
mix test

# Generate documentation
mix docs
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

Arsenal is designed to work seamlessly with the Elixir/OTP ecosystem and can be integrated with various web frameworks through its adapter system.