# Phoenix Integration Examples

This directory demonstrates how to integrate Arsenal with Phoenix web framework, providing a complete REST API for all Arsenal operations.

## Files Overview

### 1. `arsenal_adapter.ex` - Arsenal Phoenix Adapter
The main adapter that translates between Phoenix's `Plug.Conn` and Arsenal's operation system.

**Features:**
- **Request/Response Translation**: Converts Phoenix requests to Arsenal format
- **Authentication & Authorization**: JWT and API key support
- **Rate Limiting**: Per-user/IP rate limiting
- **Error Handling**: Structured error responses with proper HTTP status codes
- **CORS Support**: Cross-origin request handling
- **Logging & Metrics**: Comprehensive request/response logging
- **Performance Tracking**: Request duration and performance headers

### 2. `arsenal_controller.ex` - Phoenix Controller
Phoenix controller that handles all Arsenal operations through a unified interface.

**Endpoints:**
- `POST /api/v1/*` - Main Arsenal operation handler
- `OPTIONS /api/v1/*` - CORS preflight handling  
- `GET /api/v1/health` - Health check endpoint
- `GET /api/v1/docs` - OpenAPI documentation
- `GET /api/v1/operations` - List all available operations

### 3. `router.ex` - Phoenix Router Configuration
Complete router setup with pipelines for authentication and rate limiting.

**Pipelines:**
- `:api` - Basic API setup (JSON, CORS, security headers)
- `:arsenal_auth` - Authentication and rate limiting for protected operations

### 4. `application.ex` - Application Startup
Shows the complete application supervision tree and operation registration.

## Quick Start

### 1. Add to your Phoenix project

Add Arsenal to your `mix.exs`:
```elixir
defp deps do
  [
    {:arsenal, "~> 0.1.0"},
    # ... other deps
  ]
end
```

### 2. Copy the integration files

Copy the files from this directory to your Phoenix project:
```bash
# Copy adapter and controller
cp examples/phoenix_integration/arsenal_adapter.ex lib/my_app_web/arsenal/
cp examples/phoenix_integration/arsenal_controller.ex lib/my_app_web/controllers/

# Update router.ex with Arsenal routes
# See router.ex for example configuration
```

### 3. Update your Application module

```elixir
defmodule MyAppWeb.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Start Arsenal early in supervision tree
      {Arsenal, []},
      
      # Your other children...
      MyAppWeb.Endpoint
    ]
    
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        register_arsenal_operations()
        {:ok, pid}
      error ->
        error
    end
  end
  
  defp register_arsenal_operations do
    # Register all operations you want to expose
    Arsenal.Registry.register(:list_processes, Arsenal.Operations.ListProcesses)
    Arsenal.Registry.register(:get_process_info, Arsenal.Operations.GetProcessInfo)
    # ... register more operations
  end
end
```

### 4. Configure your router

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  
  pipeline :api do
    plug :accepts, ["json"]
  end
  
  pipeline :arsenal_auth do
    plug MyAppWeb.AuthPlug  # Your auth implementation
  end
  
  scope "/api/v1", MyAppWeb do
    pipe_through :api
    
    # Public endpoints
    get "/health", ArsenalController, :health
    get "/docs", ArsenalController, :docs
    options "/*path", ArsenalController, :options
  end
  
  scope "/api/v1", MyAppWeb do
    pipe_through [:api, :arsenal_auth]
    
    # All Arsenal operations
    match :*, "/*path", ArsenalController, :handle
  end
end
```

## Usage Examples

### 1. Authentication

**JWT Token:**
```bash
curl -X POST http://localhost:4000/api/v1/processes \
  -H "Authorization: Bearer your-jwt-token" \
  -H "Content-Type: application/json" \
  -d '{"module": "GenServer", "function": "start_link", "args": []}'
```

**API Key:**
```bash
curl -X GET http://localhost:4000/api/v1/processes \
  -H "X-API-Key: your-api-key"
```

### 2. Operation Examples

**List Processes:**
```bash
curl -X GET "http://localhost:4000/api/v1/processes?limit=10&sort_by=memory" \
  -H "Authorization: Bearer valid-admin-token"
```

**Get Process Info:**
```bash
curl -X GET "http://localhost:4000/api/v1/processes/self" \
  -H "Authorization: Bearer valid-admin-token"
```

**Start Process:**
```bash
curl -X POST http://localhost:4000/api/v1/processes \
  -H "Authorization: Bearer valid-admin-token" \
  -H "Content-Type: application/json" \
  -d '{
    "module": "GenServer",
    "function": "start_link", 
    "args": [],
    "options": {"name": "my_server"}
  }'
```

**Mathematical Operations:**
```bash
curl -X POST http://localhost:4000/api/v1/math/factorial \
  -H "Content-Type: application/json" \
  -d '{"number": 5}'
```

### 3. Health and Documentation

**Health Check:**
```bash
curl http://localhost:4000/api/v1/health
# Returns:
{
  "status": "healthy",
  "version": "0.1.0",
  "timestamp": "2024-01-18T10:30:00Z",
  "operations": 15,
  "uptime": 3600000
}
```

**API Documentation:**
```bash
curl http://localhost:4000/api/v1/docs
# Returns full OpenAPI 3.0 specification
```

**List Operations:**
```bash
curl http://localhost:4000/api/v1/operations
# Returns:
{
  "operations": [
    {
      "name": "list_processes",
      "category": "process",
      "description": "List all processes in the system",
      "method": "get",
      "path": "/api/v1/processes",
      "metadata": {...}
    }
  ],
  "total": 15
}
```

## Security Features

### 1. Authentication
- **JWT tokens** with configurable claims
- **API keys** for service-to-service communication
- **Role-based access control** (admin, user, etc.)
- **Public operations** that don't require authentication

### 2. Rate Limiting
- **Per-user limits** based on authenticated user ID
- **Per-IP limits** for unauthenticated requests
- **Operation-specific limits** (configurable per operation)
- **429 responses** with `Retry-After` headers

### 3. CORS Support
- **Preflight handling** for browser requests
- **Configurable origins** (defaults to allow all)
- **Proper headers** for cross-origin requests

### 4. Error Handling
- **Structured error responses** with consistent format
- **Error sanitization** (hide internal details in production)
- **HTTP status codes** that match error types
- **Request correlation** via `X-Request-ID` headers

## Monitoring and Observability

### 1. Logging
- **Request/response logging** with timing information
- **Error logging** with context and correlation IDs
- **User action tracking** (who did what when)
- **Performance metrics** (response times, operation counts)

### 2. Telemetry Events
The adapter emits telemetry events for monitoring:

```elixir
:telemetry.attach(
  "arsenal-monitoring",
  [:arsenal, :adapter, :request],
  fn event, measurements, metadata, _config ->
    # Track request metrics
    IO.inspect({event, measurements, metadata})
  end,
  nil
)
```

### 3. Health Monitoring
- **Built-in health endpoint** with system metrics
- **Operation availability** checking
- **Uptime tracking**
- **Version information**

## Advanced Configuration

### 1. Custom Authentication

```elixir
defmodule MyApp.ArsenalAuth do
  def verify_token(token) do
    # Your JWT verification logic
    case MyApp.JWT.verify(token) do
      {:ok, claims} -> {:ok, claims}
      error -> error
    end
  end
  
  def verify_api_key(api_key) do
    # Your API key verification logic
    case MyApp.APIKeys.lookup(api_key) do
      {:ok, user} -> {:ok, user}
      error -> error
    end
  end
end
```

### 2. Custom Rate Limiting

```elixir
defmodule MyApp.RateLimit do
  # Use Hammer or similar for production rate limiting
  def check_limit(user_id, operation) do
    Hammer.check_rate("arsenal:#{user_id}:#{operation}", 60_000, 100)
  end
end
```

### 3. Operation-Specific Authorization

```elixir
defmodule MyApp.Authorization do
  def authorize_operation(user, operation) do
    case {user.role, operation} do
      {"admin", _} -> :ok
      {"user", op} when op in [:list_processes, :get_process_info] -> :ok
      _ -> {:error, :forbidden}
    end
  end
end
```

## Testing

See the `../testing/` directory for comprehensive testing examples, including:
- **Unit tests** for the adapter
- **Integration tests** with Phoenix
- **Authentication testing**
- **Rate limiting tests**
- **Error handling tests**

## Production Considerations

1. **Use a proper rate limiting solution** (Redis + Hammer)
2. **Implement proper JWT verification** with your auth provider
3. **Configure CORS appropriately** for your domain
4. **Set up proper logging** and monitoring
5. **Use HTTPS** in production
6. **Implement API versioning** strategy
7. **Add request size limits** and timeouts
8. **Monitor operation performance** and set appropriate limits