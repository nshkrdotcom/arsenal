# Basic Operations Examples

This directory contains examples demonstrating fundamental Arsenal operation patterns.

## Examples

### 1. Simple Operation (`simple_operation.ex`)

A basic mathematical operation that calculates factorials. Demonstrates:

- **Basic operation structure** with all required callbacks
- **Parameter validation** with type checking and range validation
- **Error handling** for invalid inputs and execution errors
- **Response formatting** with structured output
- **Metadata configuration** for authentication, timeouts, and rate limiting

**Usage:**
```elixir
# Register the operation
Arsenal.Registry.register(:factorial, Examples.BasicOperations.SimpleOperation)

# Execute via registry
{:ok, result} = Arsenal.Registry.execute(:factorial, %{"number" => 5})
# Returns: {:ok, %{number: 5, factorial: 120, calculated_at: ~U[...]}}

# Test validation
{:error, reason} = Arsenal.Registry.execute(:factorial, %{"number" => -1})
# Returns: {:error, {:validation_error, "Number must be non-negative"}}
```

**REST API:**
```bash
POST /api/v1/math/factorial
Content-Type: application/json

{
  "number": 5
}
```

### 2. User Management (`user_management.ex`)

Complete CRUD operations for user management. Demonstrates:

- **Multiple operations** in a single module
- **Different HTTP methods** (GET, POST, PUT, DELETE)
- **Path parameters** (`:id` in URLs)
- **Body and query parameters**
- **Complex validation** with custom validators
- **In-memory storage** for demonstration
- **Conflict handling** (duplicate emails)
- **Resource not found** error handling

**Operations:**
- `CreateUser` - POST /api/v1/users
- `GetUser` - GET /api/v1/users/:id  
- `ListUsers` - GET /api/v1/users?role=admin&limit=10

**Usage:**

```elixir
# Start the in-memory storage
{:ok, _pid} = Examples.BasicOperations.UserManagement.start_link([])

# Register operations
Arsenal.Registry.register(:create_user, Examples.BasicOperations.CreateUser)
Arsenal.Registry.register(:get_user, Examples.BasicOperations.GetUser)
Arsenal.Registry.register(:list_users, Examples.BasicOperations.ListUsers)

# Create a user
{:ok, user} = Arsenal.Registry.execute(:create_user, %{
  "name" => "John Doe",
  "email" => "john@example.com",
  "age" => 30,
  "role" => "admin"
})

# Get the user
{:ok, user} = Arsenal.Registry.execute(:get_user, %{"id" => user.id})

# List users with filtering
{:ok, results} = Arsenal.Registry.execute(:list_users, %{
  "role" => "admin",
  "limit" => 10
})
```

**REST API Examples:**

```bash
# Create user
POST /api/v1/users
Content-Type: application/json

{
  "name": "John Doe",
  "email": "john@example.com",
  "age": 30,
  "role": "admin"
}

# Get user
GET /api/v1/users/123

# List users with filtering
GET /api/v1/users?role=admin&limit=10
```

## Key Patterns Demonstrated

### 1. Parameter Validation
```elixir
def validate_params(params) do
  with {:ok, name} <- validate_name(params["name"]),
       {:ok, email} <- validate_email(params["email"]) do
    {:ok, %{name: name, email: email}}
  end
end
```

### 2. Error Handling
```elixir
def execute(params) do
  try do
    # Business logic here
    {:ok, result}
  rescue
    error ->
      {:error, {:execution_error, inspect(error)}}
  end
end
```

### 3. Response Formatting
```elixir
def format_response(data) do
  %{
    status: "success",
    data: data,
    meta: %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  }
end
```

### 4. REST Configuration
```elixir
def rest_config() do
  %{
    method: :post,
    path: "/api/v1/users",
    summary: "Create a new user",
    parameters: [...],
    responses: %{
      201 => %{description: "User created successfully"},
      400 => %{description: "Invalid user data"}
    }
  }
end
```

## Running the Examples

1. Start your application with Arsenal:
```elixir
Arsenal.start(:normal, [])
```

2. For user management examples, start the storage:
```elixir
Examples.BasicOperations.UserManagement.start_link([])
```

3. Register the operations:
```elixir
Arsenal.Registry.register(:factorial, Examples.BasicOperations.SimpleOperation)
Arsenal.Registry.register(:create_user, Examples.BasicOperations.CreateUser)
# ... etc
```

4. Execute operations:
```elixir
Arsenal.Registry.execute(:factorial, %{"number" => 5})
```

## Testing

Each operation can be tested independently:

```elixir
# Test validation
{:ok, validated} = Examples.BasicOperations.SimpleOperation.validate_params(%{"number" => 5})

# Test execution
{:ok, result} = Examples.BasicOperations.SimpleOperation.execute(validated)

# Test formatting
formatted = Examples.BasicOperations.SimpleOperation.format_response(result)
```

## Next Steps

- See `../phoenix_integration/` for web framework integration
- See `../testing/` for comprehensive testing strategies
- See `../advanced_patterns/` for complex operation patterns