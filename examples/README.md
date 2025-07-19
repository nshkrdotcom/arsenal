# Arsenal Examples

This directory contains comprehensive examples demonstrating all major Arsenal functionality. The examples are organized into subdirectories by feature area, and include both detailed code examples and **standalone executable scripts**.

## 🚀 Quick Start - Standalone Scripts

You can run Arsenal examples directly without any setup:

```bash
# Run all examples in sequence
elixir examples/run_all_demos.exs

# Or run individual demos
elixir examples/run_basic_operations.exs
elixir examples/run_analytics_demo.exs
elixir examples/run_process_demo.exs
```

### Available Demo Scripts

| Script | Description | Features Demonstrated |
|--------|-------------|----------------------|
| `run_all_demos.exs` | Complete demo suite | All Arsenal functionality |
| `run_basic_operations.exs` | Basic operations | Parameter validation, execution, user CRUD |
| `run_analytics_demo.exs` | Analytics & monitoring | System health, performance metrics, monitoring |
| `run_process_demo.exs` | Process management | Process inspection, control, analysis |

### Demo Script Features

- **Self-contained**: No external dependencies needed
- **Automatic setup**: Starts Arsenal and required services
- **Live examples**: Real operations with actual results
- **Error demonstration**: Shows validation and error handling
- **Interactive output**: Colored output with explanations

## 📁 Example Categories

### [basic_operations/](basic_operations/)
Fundamental operation patterns and REST API generation.

**Key Examples:**
- `simple_operation.ex` - Mathematical operation with validation
- `user_management.ex` - Complete CRUD operations with complex validation

**Demonstrates:**
- Operation behavior implementation
- Parameter validation and type coercion
- Error handling and response formatting
- REST configuration and OpenAPI generation

### [phoenix_integration/](phoenix_integration/)
Complete Phoenix framework integration with authentication and security.

**Key Examples:**
- `arsenal_adapter.ex` - Full Phoenix adapter with auth, rate limiting
- `arsenal_controller.ex` - Phoenix controller for Arsenal operations
- `router.ex` - Complete routing setup with authentication pipelines
- `application.ex` - Application startup and operation registration

**Demonstrates:**
- Web framework integration
- Authentication and authorization
- Rate limiting and CORS
- Error handling and logging
- Production deployment patterns

### [analytics/](analytics/)
Comprehensive system monitoring, alerting, and observability.

**Key Examples:**
- `basic_monitoring.ex` - System health monitoring with event subscription
- `dashboard_data.ex` - Formatted data for monitoring dashboards
- `alerting_system.ex` - Advanced alerting with rules and escalation

**Demonstrates:**
- Real-time system monitoring
- Event subscription and handling
- Alert rules and escalation policies
- Dashboard data formatting
- Multi-channel notifications (Slack, email, PagerDuty)

### [process_management/](process_management/)
Advanced process inspection, control, and debugging tools.

**Key Examples:**
- `process_inspector.ex` - Comprehensive process analysis
- `process_controller.ex` - Process lifecycle management
- `tracing_tools.ex` - Advanced tracing and debugging

**Demonstrates:**
- Process categorization and analysis
- Memory and performance analysis
- Process health monitoring
- Automated process management policies
- Safe tracing with automatic cleanup

## 🎯 Usage Examples

### Running Individual Examples

```bash
# Basic operations with factorial and user management
elixir examples/run_basic_operations.exs
```

**Output Preview:**
```
🚀 Arsenal Basic Operations Demo
=========================================

1. Starting Arsenal...
   ✅ Arsenal started successfully

2. Starting user management storage...
   ✅ User storage started

3. Registering operations...
   ✅ Registered factorial
   ✅ Registered create_user
   ✅ Registered get_user
   ✅ Registered list_users

4. Testing Factorial Operation
-------------------------------
   Testing factorial(5): ✅ 120
   Testing factorial(0): ✅ 1
   Testing factorial(-1): ❌ Number must be non-negative
```

### Analytics and Monitoring

```bash
# System analytics and monitoring demo
elixir examples/run_analytics_demo.exs
```

**Shows:**
- Real-time system health metrics
- Performance analysis
- Memory and CPU utilization
- Process monitoring and alerting

### Process Management

```bash
# Advanced process management demo  
elixir examples/run_process_demo.exs
```

**Demonstrates:**
- Process categorization (GenServers, Tasks, Agents, etc.)
- Memory and performance analysis
- Process control operations
- Supervisor health monitoring

## 🔧 Integration Examples

### Using in Your Application

1. **Add Arsenal to your Mix project:**
```elixir
defp deps do
  [
    {:arsenal, "~> 0.1.0"}
  ]
end
```

2. **Start Arsenal in your application:**
```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    children = [
      # Start Arsenal
      {Arsenal, []},
      
      # Your other children...
      MyApp.Endpoint
    ]
    
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

3. **Create operations using the examples as templates:**
```elixir
defmodule MyApp.Operations.MyCustomOperation do
  use Arsenal.Operation
  
  @impl true
  def name(), do: :my_custom_operation
  
  @impl true 
  def category(), do: :custom
  
  @impl true
  def description(), do: "My custom operation"
  
  @impl true
  def params_schema() do
    %{
      param1: [type: :string, required: true],
      param2: [type: :integer, default: 0]
    }
  end
  
  @impl true
  def execute(params) do
    # Your operation logic here
    {:ok, %{result: "success", params: params}}
  end
end
```

### Phoenix Integration

Follow the complete Phoenix integration example in [`phoenix_integration/`](phoenix_integration/) which includes:

- Authentication and authorization
- Rate limiting and security
- CORS and error handling
- Health endpoints and API documentation

### Analytics Integration

Use the analytics examples to add monitoring to your application:

```elixir
# Start monitoring
{:ok, _} = Examples.Analytics.BasicMonitoring.start_link()

# Get system health
{:ok, health} = Examples.Analytics.BasicMonitoring.get_health_summary()

# Set up alerting
{:ok, _} = Examples.Analytics.AlertingSystem.start_link([
  slack_webhook: "your-webhook-url",
  email_recipients: ["ops@yourcompany.com"]
])
```

## 🧪 Testing Examples

Each example directory includes testing examples and patterns:

- **Unit tests** for individual operations
- **Integration tests** for complete workflows  
- **Property-based testing** examples
- **Performance testing** patterns

## 📚 Documentation

Each subdirectory contains detailed README files with:

- **Comprehensive usage examples**
- **API documentation**
- **Integration patterns**
- **Production considerations**
- **Troubleshooting guides**

## 🏃‍♂️ Next Steps

1. **Run the demos** to see Arsenal in action
2. **Explore the subdirectories** for detailed examples
3. **Read the README files** in each category
4. **Try the code examples** in your own projects
5. **Adapt the patterns** to your specific needs

## 💡 Tips

- **Start with basic_operations** to understand core concepts
- **Use phoenix_integration** for web application integration
- **Leverage analytics** for production monitoring
- **Explore process_management** for debugging and optimization
- **Study the testing examples** for comprehensive test coverage

The examples are designed to be **copy-paste ready** for your own applications while demonstrating Arsenal's full capabilities.