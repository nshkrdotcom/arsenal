# Arsenal Operations & Adapters - Deep Dive

**The Metaprogramming Engine for REST API Generation**

This document provides an in-depth exploration of Arsenal's Operation behavior system and Adapter pattern, which together form the foundation for automatic REST API generation from Elixir modules.

## Table of Contents

- [Conceptual Overview](#conceptual-overview)
- [The Operation Behavior](#the-operation-behavior)
- [Operation Lifecycle](#operation-lifecycle)
- [Registry Architecture](#registry-architecture)
- [Adapter Pattern](#adapter-pattern)
- [Request Processing Pipeline](#request-processing-pipeline)
- [Advanced Operation Patterns](#advanced-operation-patterns)
- [Parameter Validation Strategies](#parameter-validation-strategies)
- [Error Handling Philosophy](#error-handling-philosophy)
- [Performance Optimization](#performance-optimization)
- [Testing Strategies](#testing-strategies)

## Conceptual Overview

Arsenal's operation system is built on three core principles:

1. **Declaration over Implementation**: Operations declare their REST interface separately from implementation
2. **Framework Agnosticism**: Core logic has zero web framework dependencies
3. **Composability**: Operations can be composed, chained, and reused

### The Operation Contract

Every Arsenal operation is a contract between four concerns:

```
┌─────────────────┐
│ REST Interface  │ ← How the operation appears to HTTP clients
├─────────────────┤
│   Validation    │ ← How input is validated and transformed
├─────────────────┤
│   Execution     │ ← Core business logic
├─────────────────┤
│ Response Format │ ← How results are presented
└─────────────────┘
```

## The Operation Behavior

### Behavior Definition

```elixir
defmodule Arsenal.Operation do
  @doc """
  Returns the REST endpoint configuration for this operation.
  """
  @callback rest_config() :: map()

  @doc """
  Validates input parameters for the operation.
  """
  @callback validate_params(params :: map()) :: {:ok, map()} | {:error, term()}

  @doc """
  Executes the operation with validated parameters.
  """
  @callback execute(params :: map()) :: {:ok, term()} | {:error, term()}

  @doc """
  Transforms the operation result for JSON response.
  """
  @callback format_response(result :: term()) :: map()

  @optional_callbacks [validate_params: 1, format_response: 1]
end
```

### The `__using__` Macro

```elixir
defmacro __using__(_opts) do
  quote do
    @behaviour Arsenal.Operation
    
    # Default implementations
    def validate_params(params), do: {:ok, params}
    def format_response(result), do: %{data: result}
    
    defoverridable validate_params: 1, format_response: 1
  end
end
```

This macro provides sensible defaults while allowing operations to override as needed.

## Operation Lifecycle

### 1. Registration Phase

```elixir
# Manual registration
Arsenal.Registry.register_operation(MyOperation)

# Automatic discovery at compile time
defmodule MyApp.Application do
  def start(_type, _args) do
    # Discover all operations in a namespace
    Arsenal.Registry.discover_operations("MyApp.Operations")
    
    children = [Arsenal.Registry]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### 2. Configuration Phase

When an operation is registered, its `rest_config/0` is called and validated:

```elixir
def rest_config do
  %{
    method: :post,
    path: "/api/v1/users/:user_id/orders",
    summary: "Create a new order for a user",
    parameters: [
      %{
        name: :user_id,
        type: :integer,
        location: :path,
        required: true,
        description: "User ID"
      },
      %{
        name: :items,
        type: :array,
        location: :body,
        required: true,
        description: "Order items",
        schema: %{
          items: %{
            type: :object,
            properties: %{
              product_id: %{type: :integer, required: true},
              quantity: %{type: :integer, required: true, minimum: 1}
            }
          }
        }
      }
    ],
    responses: %{
      201 => %{
        description: "Order created successfully",
        schema: %{
          type: :object,
          properties: %{
            order_id: %{type: :integer},
            total: %{type: :number},
            status: %{type: :string}
          }
        }
      },
      400 => %{description: "Invalid request parameters"},
      404 => %{description: "User not found"},
      422 => %{description: "Unprocessable entity"}
    }
  }
end
```

### 3. Request Processing Phase

The complete request flow:

```
HTTP Request → Adapter → Registry Lookup → Operation Validation → 
Operation Execution → Response Formatting → Adapter Response → HTTP Response
```

## Registry Architecture

### ETS-Based Storage

The Registry uses ETS for high-performance operation lookup:

```elixir
def init(_opts) do
  :ets.new(@table_name, [
    :named_table, 
    :public, 
    :set, 
    {:read_concurrency, true}
  ])
  {:ok, %{}}
end
```

### Registration Process

```elixir
defp register_operation_module(module) do
  # 1. Ensure module is loaded
  Code.ensure_loaded(module)
  
  # 2. Verify it implements the behavior
  if function_exported?(module, :rest_config, 0) do
    config = module.rest_config()
    
    # 3. Validate configuration
    case validate_rest_config(config) do
      :ok ->
        # 4. Store in ETS with metadata
        :ets.insert(@table_name, {module, config})
        {:ok, Map.put(config, :module, module)}
      
      error ->
        error
    end
  else
    {:error, :not_an_operation}
  end
end
```

### Path Matching Algorithm

The registry implements efficient path matching for dynamic routes:

```elixir
defp find_operation(method, path) do
  operations = Arsenal.list_operations()
  
  Enum.find_value(operations, {:error, :operation_not_found}, fn op ->
    if op.method == method && path_matches?(path, op.path) do
      {:ok, op}
    else
      nil
    end
  end)
end

defp path_matches?(request_path, pattern_path) do
  # Convert "/api/v1/users/:id" to regex
  pattern = 
    pattern_path
    |> String.split("/")
    |> Enum.map(fn
      ":" <> param -> 
        # Named capture group
        "(?<#{param}>[^/]+)"
      segment -> 
        Regex.escape(segment)
    end)
    |> Enum.join("/")
  
  regex = ~r/^#{pattern}$/
  
  case Regex.named_captures(regex, request_path) do
    nil -> false
    captures -> {true, captures}
  end
end
```

## Adapter Pattern

### Adapter Behavior

```elixir
defmodule Arsenal.Adapter do
  @callback extract_method(request :: any()) :: atom()
  @callback extract_path(request :: any()) :: String.t()
  @callback extract_params(request :: any()) :: map()
  @callback send_response(request :: any(), status :: integer(), body :: map()) :: any()
  @callback send_error(request :: any(), status :: integer(), error :: any()) :: any()
  
  # Optional hooks
  @callback before_process(request :: any()) :: {:ok, any()} | {:error, any()}
  @callback after_process(request :: any(), response :: any()) :: any()
  
  @optional_callbacks [before_process: 1, after_process: 2]
end
```

### Phoenix Adapter Implementation

```elixir
defmodule Arsenal.Adapters.Phoenix do
  @behaviour Arsenal.Adapter
  
  @impl true
  def extract_method(%Plug.Conn{method: method}) do
    method |> String.downcase() |> String.to_atom()
  end
  
  @impl true
  def extract_path(%Plug.Conn{request_path: path}), do: path
  
  @impl true
  def extract_params(%Plug.Conn{} = conn) do
    # Merge all param sources
    conn.params
    |> Map.merge(conn.path_params)
    |> Map.merge(conn.query_params)
    |> stringify_keys()
  end
  
  @impl true
  def send_response(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.put_status(status)
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
  
  @impl true
  def send_error(conn, status, error) do
    error_body = format_error(error)
    send_response(conn, status, error_body)
  end
  
  @impl true
  def before_process(conn) do
    # Authentication, rate limiting, etc.
    with :ok <- authenticate(conn),
         :ok <- check_rate_limit(conn) do
      {:ok, conn}
    end
  end
  
  @impl true
  def after_process(conn, response) do
    # Logging, metrics, headers
    conn
    |> add_request_id_header()
    |> log_request()
    |> track_metrics()
  end
end
```

### Plug Adapter (Minimal)

```elixir
defmodule Arsenal.Adapters.Plug do
  @behaviour Arsenal.Adapter
  
  @impl true
  def extract_method(%{method: method}), do: method
  
  @impl true
  def extract_path(%{request_path: path}), do: path
  
  @impl true
  def extract_params(%{params: params}), do: params
  
  @impl true
  def send_response(conn, status, body) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(status, Jason.encode!(body))
  end
  
  @impl true
  def send_error(conn, status, error) do
    send_response(conn, status, %{error: error})
  end
end
```

## Request Processing Pipeline

### The Main Processing Function

```elixir
def process_request(adapter, request) do
  with {:ok, request} <- maybe_before_process(adapter, request),
       method <- adapter.extract_method(request),
       path <- adapter.extract_path(request),
       params <- adapter.extract_params(request),
       {:ok, operation} <- find_operation(method, path),
       {:ok, enriched_params} <- enrich_params(params, path, operation),
       {:ok, validated_params} <- validate_operation_params(operation, enriched_params),
       {:ok, result} <- execute_operation(operation, validated_params),
       formatted_response <- format_operation_response(operation, result),
       final_response <- maybe_after_process(adapter, request, formatted_response) do
    adapter.send_response(request, 200, final_response)
  else
    {:error, :operation_not_found} ->
      handle_not_found(adapter, request)
    
    {:error, {:validation_error, errors}} ->
      handle_validation_error(adapter, request, errors)
    
    {:error, {:execution_error, error}} ->
      handle_execution_error(adapter, request, error)
    
    {:error, error} ->
      handle_generic_error(adapter, request, error)
  end
end
```

### Parameter Enrichment

Path parameters are extracted and merged:

```elixir
defp enrich_params(params, path, operation) do
  case extract_path_params(path, operation.path) do
    {:ok, path_params} ->
      {:ok, Map.merge(params, path_params)}
    
    error ->
      error
  end
end

defp extract_path_params(request_path, pattern_path) do
  # Implementation shown in Registry section
end
```

### Validation Pipeline

```elixir
defp validate_operation_params(operation, params) do
  # 1. Check required parameters
  with :ok <- validate_required_params(operation.parameters, params),
       # 2. Validate parameter types
       {:ok, typed_params} <- validate_param_types(operation.parameters, params),
       # 3. Apply operation-specific validation
       {:ok, validated_params} <- operation.module.validate_params(typed_params) do
    {:ok, validated_params}
  end
end
```

## Advanced Operation Patterns

### 1. Composite Operations

```elixir
defmodule MyApp.Operations.CreateUserWithProfile do
  use Arsenal.Operation
  
  def execute(params) do
    with {:ok, user_params} <- extract_user_params(params),
         {:ok, profile_params} <- extract_profile_params(params),
         {:ok, user} <- MyApp.Operations.CreateUser.execute(user_params),
         {:ok, profile} <- MyApp.Operations.CreateProfile.execute(
           Map.put(profile_params, :user_id, user.id)
         ) do
      {:ok, %{user: user, profile: profile}}
    else
      {:error, error} when is_atom(error) ->
        {:error, error}
      
      {:error, {:create_user, error}} ->
        {:error, {:user_creation_failed, error}}
      
      {:error, {:create_profile, error}} ->
        # Rollback user creation
        MyApp.Operations.DeleteUser.execute(%{id: user.id})
        {:error, {:profile_creation_failed, error}}
    end
  end
end
```

### 2. Streaming Operations

```elixir
defmodule MyApp.Operations.StreamLogs do
  use Arsenal.Operation
  
  def rest_config do
    %{
      method: :get,
      path: "/api/v1/logs/stream",
      summary: "Stream logs in real-time",
      parameters: [
        %{name: :filter, type: :string, location: :query, required: false}
      ],
      responses: %{
        200 => %{
          description: "Log stream",
          content_type: "text/event-stream"
        }
      }
    }
  end
  
  def execute(%{filter: filter} = params) do
    stream = Stream.resource(
      fn -> init_log_reader(filter) end,
      fn state -> read_next_logs(state) end,
      fn state -> cleanup_log_reader(state) end
    )
    
    {:ok, {:stream, stream}}
  end
  
  def format_response({:stream, stream}) do
    # Special handling for streams
    {:stream, stream}
  end
end
```

### 3. Batch Operations

```elixir
defmodule MyApp.Operations.BatchUpdate do
  use Arsenal.Operation
  
  def rest_config do
    %{
      method: :patch,
      path: "/api/v1/users/batch",
      summary: "Update multiple users",
      parameters: [
        %{
          name: :updates,
          type: :array,
          location: :body,
          required: true,
          schema: %{
            items: %{
              type: :object,
              properties: %{
                id: %{type: :integer, required: true},
                changes: %{type: :object, required: true}
              }
            }
          }
        }
      ]
    }
  end
  
  def execute(%{updates: updates}) do
    results = Task.async_stream(
      updates,
      fn update ->
        MyApp.Operations.UpdateUser.execute(%{
          id: update["id"],
          changes: update["changes"]
        })
      end,
      max_concurrency: 10,
      timeout: 5000
    )
    |> Enum.map(fn
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, error}} -> {:error, error}
      {:exit, reason} -> {:error, {:timeout, reason}}
    end)
    
    successful = Enum.filter(results, &match?({:ok, _}, &1))
    failed = Enum.filter(results, &match?({:error, _}, &1))
    
    {:ok, %{successful: successful, failed: failed}}
  end
end
```

### 4. Paginated Operations

```elixir
defmodule MyApp.Operations.ListWithPagination do
  use Arsenal.Operation
  
  def rest_config do
    %{
      method: :get,
      path: "/api/v1/resources",
      parameters: [
        %{name: :page, type: :integer, location: :query, default: 1},
        %{name: :per_page, type: :integer, location: :query, default: 20, maximum: 100},
        %{name: :sort_by, type: :string, location: :query, enum: ["created_at", "name"]},
        %{name: :order, type: :string, location: :query, enum: ["asc", "desc"], default: "asc"}
      ]
    }
  end
  
  def validate_params(params) do
    params = 
      params
      |> ensure_defaults()
      |> validate_pagination_limits()
    
    {:ok, params}
  end
  
  def execute(%{page: page, per_page: per_page, sort_by: sort_by, order: order}) do
    offset = (page - 1) * per_page
    
    {items, total_count} = MyApp.Repo.paginate(
      MyApp.Resource,
      offset: offset,
      limit: per_page,
      order_by: [{order, sort_by}]
    )
    
    {:ok, %{
      items: items,
      pagination: %{
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: ceil(total_count / per_page),
        has_next: page * per_page < total_count,
        has_prev: page > 1
      }
    }}
  end
  
  def format_response(%{items: items, pagination: pagination}) do
    %{
      data: Enum.map(items, &format_item/1),
      meta: %{pagination: pagination}
    }
  end
end
```

## Parameter Validation Strategies

### 1. Type Coercion

```elixir
defmodule Arsenal.ParamValidator do
  def validate_type(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "must be a valid integer"}
    end
  end
  
  def validate_type(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, "must be a valid float"}
    end
  end
  
  def validate_type(value, :boolean) when is_binary(value) do
    case value do
      v when v in ["true", "1", "yes"] -> {:ok, true}
      v when v in ["false", "0", "no"] -> {:ok, false}
      _ -> {:error, "must be a boolean"}
    end
  end
  
  def validate_type(value, :date) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, "must be a valid ISO8601 date"}
    end
  end
  
  def validate_type(value, :array) when is_binary(value) do
    # Handle comma-separated values
    {:ok, String.split(value, ",")}
  end
end
```

### 2. Nested Validation

```elixir
defmodule MyApp.Operations.ComplexValidation do
  def validate_params(params) do
    with {:ok, user} <- validate_user_section(params["user"]),
         {:ok, address} <- validate_address_section(params["address"]),
         {:ok, preferences} <- validate_preferences(params["preferences"]) do
      {:ok, %{
        user: user,
        address: address,
        preferences: preferences
      }}
    end
  end
  
  defp validate_user_section(nil), do: {:error, "user section is required"}
  defp validate_user_section(user) do
    required = [:name, :email]
    
    with :ok <- check_required_fields(user, required),
         {:ok, email} <- validate_email(user["email"]),
         {:ok, name} <- validate_name(user["name"]) do
      {:ok, %{email: email, name: name}}
    end
  end
  
  defp validate_email(email) do
    if Regex.match?(~r/^[^\s]+@[^\s]+$/, email) do
      {:ok, email}
    else
      {:error, "invalid email format"}
    end
  end
end
```

### 3. Custom Validators

```elixir
defmodule Arsenal.Validators do
  defmodule Length do
    def validate(value, opts) when is_binary(value) do
      min = Keyword.get(opts, :min, 0)
      max = Keyword.get(opts, :max, :infinity)
      
      len = String.length(value)
      
      cond do
        len < min -> {:error, "must be at least #{min} characters"}
        max != :infinity && len > max -> {:error, "must be at most #{max} characters"}
        true -> :ok
      end
    end
  end
  
  defmodule Format do
    def validate(value, pattern: pattern) when is_binary(value) do
      if Regex.match?(pattern, value) do
        :ok
      else
        {:error, "invalid format"}
      end
    end
  end
  
  defmodule Range do
    def validate(value, opts) when is_number(value) do
      min = Keyword.get(opts, :min, :negative_infinity)
      max = Keyword.get(opts, :max, :infinity)
      
      cond do
        min != :negative_infinity && value < min -> 
          {:error, "must be at least #{min}"}
        max != :infinity && value > max -> 
          {:error, "must be at most #{max}"}
        true -> 
          :ok
      end
    end
  end
end
```

## Error Handling Philosophy

### Error Categories

1. **Client Errors (4xx)**
   - Validation errors
   - Not found errors
   - Authentication/Authorization errors
   - Rate limit errors

2. **Server Errors (5xx)**
   - Execution errors
   - External service failures
   - Unexpected errors

### Error Response Format

```elixir
defmodule Arsenal.ErrorFormatter do
  def format_error(:not_found) do
    %{
      error: %{
        code: "RESOURCE_NOT_FOUND",
        message: "The requested resource was not found",
        status: 404
      }
    }
  end
  
  def format_error({:validation_error, errors}) when is_list(errors) do
    %{
      error: %{
        code: "VALIDATION_FAILED",
        message: "Request validation failed",
        status: 422,
        details: format_validation_errors(errors)
      }
    }
  end
  
  def format_error({:execution_error, reason}) do
    %{
      error: %{
        code: "EXECUTION_FAILED",
        message: "Operation execution failed",
        status: 500,
        reason: sanitize_error_reason(reason)
      }
    }
  end
  
  defp format_validation_errors(errors) do
    Enum.map(errors, fn
      {field, message} when is_binary(message) ->
        %{field: field, message: message}
      
      {field, messages} when is_list(messages) ->
        %{field: field, messages: messages}
    end)
  end
  
  defp sanitize_error_reason(reason) do
    # Don't expose internal details in production
    if Application.get_env(:my_app, :environment) == :production do
      "Internal server error"
    else
      inspect(reason)
    end
  end
end
```

### Error Recovery

```elixir
defmodule MyApp.Operations.ResilientOperation do
  use Arsenal.Operation
  
  def execute(params) do
    # Retry with exponential backoff
    retry_with_backoff(
      fn -> do_execute(params) end,
      max_attempts: 3,
      initial_delay: 100
    )
  end
  
  defp retry_with_backoff(fun, opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    initial_delay = Keyword.get(opts, :initial_delay, 100)
    
    do_retry(fun, 1, max_attempts, initial_delay)
  end
  
  defp do_retry(fun, attempt, max_attempts, delay) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}
      
      {:error, :temporary_failure} when attempt < max_attempts ->
        Process.sleep(delay)
        do_retry(fun, attempt + 1, max_attempts, delay * 2)
      
      {:error, error} ->
        {:error, error}
    end
  end
end
```

## Performance Optimization

### 1. Operation Caching

```elixir
defmodule Arsenal.Cache do
  use GenServer
  
  def cache_operation(operation_module, params, ttl \\ 300_000) do
    key = generate_cache_key(operation_module, params)
    
    case get_cached(key) do
      {:ok, cached_result} ->
        {:ok, cached_result}
      
      :miss ->
        case operation_module.execute(params) do
          {:ok, result} = success ->
            put_cache(key, result, ttl)
            success
          
          error ->
            error
        end
    end
  end
  
  defp generate_cache_key(operation_module, params) do
    params_hash = :crypto.hash(:sha256, :erlang.term_to_binary(params))
    {operation_module, Base.encode16(params_hash)}
  end
end
```

### 2. Precompiled Routes

```elixir
defmodule Arsenal.RouteCompiler do
  def compile_routes(operations) do
    # Group by method for faster lookup
    by_method = Enum.group_by(operations, & &1.method)
    
    # Pre-compile regex patterns
    Enum.map(by_method, fn {method, ops} ->
      compiled_ops = Enum.map(ops, fn op ->
        %{
          op | 
          compiled_pattern: compile_pattern(op.path),
          param_names: extract_param_names(op.path)
        }
      end)
      
      {method, compiled_ops}
    end)
    |> Enum.into(%{})
  end
  
  defp compile_pattern(path) do
    pattern = 
      path
      |> String.split("/")
      |> Enum.map(fn
        ":" <> param -> "([^/]+)"
        segment -> Regex.escape(segment)
      end)
      |> Enum.join("/")
    
    Regex.compile!("^#{pattern}$")
  end
end
```

### 3. Lazy Parameter Loading

```elixir
defmodule MyApp.Operations.LazyLoad do
  use Arsenal.Operation
  
  def validate_params(params) do
    # Only validate IDs, not full objects
    with {:ok, user_id} <- validate_user_id(params["user_id"]),
         {:ok, resource_ids} <- validate_resource_ids(params["resource_ids"]) do
      {:ok, %{
        user_id: user_id,
        resource_ids: resource_ids,
        # Lazy load flag
        _lazy: [:user, :resources]
      }}
    end
  end
  
  def execute(%{_lazy: lazy_fields} = params) do
    # Load only what's needed
    loaded_params = load_lazy_fields(params, lazy_fields)
    do_execute(loaded_params)
  end
  
  defp load_lazy_fields(params, fields) do
    Enum.reduce(fields, params, fn field, acc ->
      case field do
        :user -> Map.put(acc, :user, load_user(acc.user_id))
        :resources -> Map.put(acc, :resources, load_resources(acc.resource_ids))
      end
    end)
  end
end
```

## Testing Strategies

### 1. Operation Testing

```elixir
defmodule MyApp.Operations.CreateUserTest do
  use ExUnit.Case
  
  alias MyApp.Operations.CreateUser
  
  describe "rest_config/0" do
    test "returns valid configuration" do
      config = CreateUser.rest_config()
      
      assert config.method == :post
      assert config.path == "/api/v1/users"
      assert is_list(config.parameters)
      assert is_map(config.responses)
    end
  end
  
  describe "validate_params/1" do
    test "validates required fields" do
      assert {:error, _} = CreateUser.validate_params(%{})
      assert {:error, _} = CreateUser.validate_params(%{"email" => "test@example.com"})
      
      assert {:ok, _} = CreateUser.validate_params(%{
        "email" => "test@example.com",
        "name" => "Test User"
      })
    end
    
    test "validates email format" do
      params = %{"name" => "Test", "email" => "invalid"}
      assert {:error, {:validation_error, _}} = CreateUser.validate_params(params)
    end
  end
  
  describe "execute/1" do
    setup do
      # Setup test data
      :ok
    end
    
    test "creates user successfully" do
      params = %{email: "test@example.com", name: "Test User"}
      assert {:ok, user} = CreateUser.execute(params)
      assert user.email == params.email
      assert user.name == params.name
    end
    
    test "handles duplicate email" do
      params = %{email: "existing@example.com", name: "Test User"}
      # Create first user
      {:ok, _} = CreateUser.execute(params)
      
      # Try to create duplicate
      assert {:error, :email_taken} = CreateUser.execute(params)
    end
  end
  
  describe "format_response/1" do
    test "formats success response" do
      user = %{id: 1, email: "test@example.com", name: "Test"}
      response = CreateUser.format_response({:ok, user})
      
      assert response.status == "success"
      assert response.data.id == user.id
    end
    
    test "formats error response" do
      response = CreateUser.format_response({:error, :email_taken})
      
      assert response.status == "error"
      assert response.error.code == "EMAIL_TAKEN"
    end
  end
end
```

### 2. Integration Testing

```elixir
defmodule MyApp.ArsenalIntegrationTest do
  use MyApp.ConnCase
  
  setup do
    # Register test operations
    Arsenal.Registry.register_operation(MyApp.Operations.CreateUser)
    Arsenal.Registry.register_operation(MyApp.Operations.GetUser)
    :ok
  end
  
  describe "full request cycle" do
    test "creates and retrieves user", %{conn: conn} do
      # Create user
      create_conn = 
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/users", %{
          email: "test@example.com",
          name: "Test User"
        })
      
      assert %{"data" => %{"id" => user_id}} = json_response(create_conn, 201)
      
      # Get user
      get_conn = get(conn, "/api/v1/users/#{user_id}")
      
      assert %{"data" => user} = json_response(get_conn, 200)
      assert user["id"] == user_id
      assert user["email"] == "test@example.com"
    end
    
    test "handles validation errors", %{conn: conn} do
      conn = 
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/users", %{email: "invalid"})
      
      assert %{"error" => error} = json_response(conn, 422)
      assert error["code"] == "VALIDATION_FAILED"
      assert is_list(error["details"])
    end
  end
end
```

### 3. Property-Based Testing

```elixir
defmodule MyApp.Operations.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "all valid inputs produce successful results" do
    check all email <- valid_email_generator(),
              name <- string(:alphanumeric, min_length: 1) do
      params = %{"email" => email, "name" => name}
      
      assert {:ok, validated} = MyApp.Operations.CreateUser.validate_params(params)
      assert is_map(validated)
      assert validated.email == email
      assert validated.name == name
    end
  end
  
  property "invalid emails are always rejected" do
    check all invalid_email <- invalid_email_generator() do
      params = %{"email" => invalid_email, "name" => "Test"}
      
      assert {:error, _} = MyApp.Operations.CreateUser.validate_params(params)
    end
  end
  
  defp valid_email_generator do
    gen all name <- string(:alphanumeric, min_length: 1),
            domain <- string(:alphanumeric, min_length: 1) do
      "#{name}@#{domain}.com"
    end
  end
  
  defp invalid_email_generator do
    one_of([
      constant(""),
      constant("@"),
      constant("no-at-sign"),
      constant("@no-local"),
      constant("no-domain@"),
      constant("multiple@@at")
    ])
  end
end
```

## Best Practices

1. **Keep Operations Focused**: Each operation should do one thing well
2. **Validate Early**: Catch errors in validate_params before execution
3. **Use Consistent Error Formats**: Makes client integration easier
4. **Document Parameters**: Good descriptions help API users
5. **Version Your APIs**: Use path versioning (/api/v1/, /api/v2/)
6. **Test All Layers**: Unit test operations, integration test the full stack
7. **Monitor Performance**: Track operation execution times
8. **Handle Errors Gracefully**: Never expose internal errors to clients

## Conclusion

Arsenal's Operation and Adapter system provides a powerful foundation for building REST APIs in Elixir. By separating concerns and providing a declarative interface, it enables rapid API development while maintaining flexibility and testability.

The metaprogramming approach allows operations to be discovered, validated, and executed automatically, reducing boilerplate and ensuring consistency across your API surface.

For more examples and advanced patterns, see the operations in `lib/arsenal/operations/` directory.