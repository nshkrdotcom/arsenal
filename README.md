# Arsenal

A metaprogramming framework for building REST APIs from OTP operations in Elixir.

Arsenal enables automatic REST API generation by defining operations as simple Elixir modules with behavior callbacks. It provides a registry system, operation discovery, parameter validation, and OpenAPI documentation generation.

## Features

- **Automatic API Generation**: Define operations as modules and get REST endpoints automatically
- **Operation Registry**: Dynamic discovery and registration of operations
- **Parameter Validation**: Built-in validation with custom validators support
- **OpenAPI Documentation**: Automatic generation of OpenAPI/Swagger specs
- **Framework Agnostic**: Core library has no web framework dependencies
- **Extensible**: Easy to create custom operations and web adapters

## Installation

Add `arsenal` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:arsenal, "~> 0.0.1"}
  ]
end
```

## Quick Start

### 1. Define an Operation

Create a module that implements the `Arsenal.Operation` behavior:

```elixir
defmodule MyApp.Operations.GetUser do
  use Arsenal.Operation

  @impl true
  def rest_config do
    %{
      method: :get,
      path: "/api/v1/users/:id",
      summary: "Get user by ID",
      parameters: [
        %{
          name: :id,
          type: :integer,
          location: :path,
          required: true,
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
  def validate_params(%{"id" => id} = params) do
    case Integer.parse(id) do
      {user_id, ""} -> {:ok, %{id: user_id}}
      _ -> {:error, "Invalid user ID"}
    end
  end

  @impl true
  def execute(%{id: user_id}) do
    case MyApp.Users.get_user(user_id) do
      {:ok, user} -> {:ok, user}
      {:error, :not_found} -> {:error, :user_not_found}
    end
  end

  @impl true
  def format_response({:ok, user}) do
    %{
      status: "success",
      data: %{
        id: user.id,
        name: user.name,
        email: user.email
      }
    }
  end

  def format_response({:error, :user_not_found}) do
    %{
      status: "error",
      error: %{
        code: "USER_NOT_FOUND",
        message: "User not found"
      }
    }
  end
end
```

### 2. Register Operations

Start the Arsenal application and register your operations:

```elixir
# In your application supervisor
children = [
  Arsenal,
  # ... other children
]

# After startup, register operations
Arsenal.register_operation(MyApp.Operations.GetUser)

# Or discover all operations in a namespace
Arsenal.Registry.discover_operations("MyApp.Operations")
```

### 3. Use with a Web Framework

Arsenal is framework-agnostic. For Phoenix integration, use `arsenal_plug`:

```elixir
# In your router
forward "/api/v1", ArsenalPlug

# Or create your own adapter
defmodule MyApp.ArsenalHandler do
  def handle_request(path, method, params) do
    # Find matching operation
    case Arsenal.find_operation(path, method) do
      {:ok, operation} ->
        Arsenal.execute_operation(operation, params)
      
      {:error, :not_found} ->
        {:error, :operation_not_found}
    end
  end
end
```

## Core Concepts

### Operations

Operations are the building blocks of Arsenal. Each operation:
- Defines its REST endpoint configuration
- Validates input parameters
- Executes business logic
- Formats responses

### Registry

The registry manages all operations:
- Automatic discovery at startup
- Dynamic registration at runtime
- Operation lookup by path/method
- Metadata management

### Web Adapters

Arsenal doesn't depend on any web framework. You can:
- Use the provided Phoenix adapter (`arsenal_plug`)
- Create adapters for other frameworks (Plug, Cowboy, etc.)
- Use operations directly without HTTP

## API Documentation

Arsenal can generate OpenAPI documentation for all registered operations:

```elixir
# Generate OpenAPI spec
openapi_spec = Arsenal.generate_api_docs()

# Serve it from an endpoint
get "/api/docs" do
  json(conn, openapi_spec)
end
```

## Advanced Usage

### Custom Validators

```elixir
def validate_params(params) do
  with {:ok, params} <- validate_required(params, [:name, :email]),
       {:ok, params} <- validate_email(params),
       {:ok, params} <- validate_age(params) do
    {:ok, params}
  end
end
```

### Operation Composition

```elixir
defmodule MyApp.Operations.CreateUserWithProfile do
  use Arsenal.Operation

  def execute(params) do
    with {:ok, user} <- MyApp.Operations.CreateUser.execute(params),
         {:ok, profile} <- MyApp.Operations.CreateProfile.execute(params) do
      {:ok, %{user: user, profile: profile}}
    end
  end
end
```

### Middleware Support

```elixir
defmodule MyApp.Arsenal.Middleware.Authentication do
  def before_execute(operation, params) do
    case authenticate(params) do
      {:ok, user} -> {:ok, Map.put(params, :current_user, user)}
      {:error, _} -> {:error, :unauthorized}
    end
  end
end
```

## Examples

See the `examples/` directory for complete examples:
- Basic CRUD operations
- Authentication and authorization
- File upload handling
- WebSocket operations
- Background job triggering

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -am 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.