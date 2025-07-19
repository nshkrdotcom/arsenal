defmodule Examples.BasicOperations.UserManagement do
  @moduledoc """
  Example CRUD operations for user management.
  
  Demonstrates:
  - REST-style operations (GET, POST, PUT, DELETE)
  - Path parameters
  - Body parameters 
  - Complex validation
  - Different response formats
  """
  
  # In-memory storage for demo purposes
  use Agent
  
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end
  
  def get_user(id) do
    Agent.get(__MODULE__, &Map.get(&1, id))
  end
  
  def create_user(user) do
    id = System.unique_integer([:positive])
    user_with_id = Map.put(user, :id, id)
    Agent.update(__MODULE__, &Map.put(&1, id, user_with_id))
    user_with_id
  end
  
  def update_user(id, changes) do
    Agent.get_and_update(__MODULE__, fn users ->
      case Map.get(users, id) do
        nil -> 
          {nil, users}
        user -> 
          updated_user = Map.merge(user, changes)
          {updated_user, Map.put(users, id, updated_user)}
      end
    end)
  end
  
  def delete_user(id) do
    Agent.get_and_update(__MODULE__, fn users ->
      {Map.get(users, id), Map.delete(users, id)}
    end)
  end
  
  def list_users do
    Agent.get(__MODULE__, &Map.values(&1))
  end
end

defmodule Examples.BasicOperations.CreateUser do
  use Arsenal.Operation
  
  @impl true
  def name(), do: :create_user
  
  @impl true
  def category(), do: :user_management
  
  @impl true
  def description(), do: "Create a new user"
  
  @impl true
  def params_schema() do
    %{
      name: [type: :string, required: true, min_length: 2, max_length: 50],
      email: [type: :string, required: true, format: :email],
      age: [type: :integer, required: false, minimum: 13, maximum: 120],
      role: [type: :string, required: false, enum: ["user", "admin", "moderator"]]
    }
  end
  
  @impl true
  def rest_config() do
    %{
      method: :post,
      path: "/api/v1/users",
      summary: "Create a new user",
      parameters: [
        %{name: :name, type: :string, location: :body, required: true},
        %{name: :email, type: :string, location: :body, required: true},
        %{name: :age, type: :integer, location: :body, required: false},
        %{name: :role, type: :string, location: :body, required: false}
      ],
      responses: %{
        201 => %{description: "User created successfully"},
        400 => %{description: "Invalid user data"},
        409 => %{description: "User already exists"}
      }
    }
  end
  
  @impl true
  def validate_params(params) do
    with {:ok, name} <- validate_name(params["name"]),
         {:ok, email} <- validate_email(params["email"]),
         {:ok, age} <- validate_age(params["age"]),
         {:ok, role} <- validate_role(params["role"]) do
      
      user_data = %{name: name, email: email}
      user_data = if age, do: Map.put(user_data, :age, age), else: user_data
      user_data = if role, do: Map.put(user_data, :role, role), else: Map.put(user_data, :role, "user")
      
      {:ok, user_data}
    end
  end
  
  @impl true
  def execute(user_data) do
    try do
      # Check if user exists
      existing_users = Examples.BasicOperations.UserManagement.list_users()
      if Enum.any?(existing_users, &(&1.email == user_data.email)) do
        {:error, {:conflict, "User with this email already exists"}}
      else
        user = Examples.BasicOperations.UserManagement.create_user(user_data)
        {:ok, user}
      end
    rescue
      error ->
        {:error, {:execution_error, inspect(error)}}
    end
  end
  
  @impl true
  def format_response(user) do
    %{
      status: "created",
      data: %{
        id: user.id,
        name: user.name,
        email: user.email,
        age: Map.get(user, :age),
        role: user.role,
        created_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end
  
  # Validation helpers
  defp validate_name(nil), do: {:error, "Name is required"}
  defp validate_name(name) when is_binary(name) do
    cond do
      String.length(name) < 2 -> {:error, "Name must be at least 2 characters"}
      String.length(name) > 50 -> {:error, "Name must be less than 50 characters"}
      true -> {:ok, String.trim(name)}
    end
  end
  defp validate_name(_), do: {:error, "Name must be a string"}
  
  defp validate_email(nil), do: {:error, "Email is required"}
  defp validate_email(email) when is_binary(email) do
    if Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/, email) do
      {:ok, String.downcase(String.trim(email))}
    else
      {:error, "Invalid email format"}
    end
  end
  defp validate_email(_), do: {:error, "Email must be a string"}
  
  defp validate_age(nil), do: {:ok, nil}
  defp validate_age(age) when is_integer(age) do
    cond do
      age < 13 -> {:error, "Age must be at least 13"}
      age > 120 -> {:error, "Age must be less than 120"}
      true -> {:ok, age}
    end
  end
  defp validate_age(age) when is_binary(age) do
    case Integer.parse(age) do
      {int_age, ""} -> validate_age(int_age)
      _ -> {:error, "Age must be a valid integer"}
    end
  end
  defp validate_age(_), do: {:error, "Age must be an integer"}
  
  defp validate_role(nil), do: {:ok, nil}
  defp validate_role(role) when role in ["user", "admin", "moderator"], do: {:ok, role}
  defp validate_role(_), do: {:error, "Role must be one of: user, admin, moderator"}
end

defmodule Examples.BasicOperations.GetUser do
  use Arsenal.Operation
  
  @impl true
  def name(), do: :get_user
  
  @impl true
  def category(), do: :user_management
  
  @impl true
  def description(), do: "Get user by ID"
  
  @impl true
  def params_schema() do
    %{
      id: [type: :integer, required: true, minimum: 1]
    }
  end
  
  @impl true
  def rest_config() do
    %{
      method: :get,
      path: "/api/v1/users/:id",
      summary: "Get user by ID",
      parameters: [
        %{name: :id, type: :integer, location: :path, required: true}
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
      {int_id, ""} when int_id > 0 -> {:ok, %{id: int_id}}
      _ -> {:error, "ID must be a positive integer"}
    end
  end
  
  def validate_params(%{"id" => id}) when is_integer(id) and id > 0 do
    {:ok, %{id: id}}
  end
  
  def validate_params(_), do: {:error, "Valid ID is required"}
  
  @impl true
  def execute(%{id: id}) do
    case Examples.BasicOperations.UserManagement.get_user(id) do
      nil -> {:error, {:not_found, "User not found"}}
      user -> {:ok, user}
    end
  end
  
  @impl true
  def format_response(user) do
    %{
      status: "success",
      data: user
    }
  end
end

defmodule Examples.BasicOperations.ListUsers do
  use Arsenal.Operation
  
  @impl true
  def name(), do: :list_users
  
  @impl true
  def category(), do: :user_management
  
  @impl true
  def description(), do: "List all users with optional filtering"
  
  @impl true
  def params_schema() do
    %{
      role: [type: :string, required: false, enum: ["user", "admin", "moderator"]],
      limit: [type: :integer, required: false, default: 50, minimum: 1, maximum: 100]
    }
  end
  
  @impl true
  def rest_config() do
    %{
      method: :get,
      path: "/api/v1/users",
      summary: "List users",
      parameters: [
        %{name: :role, type: :string, location: :query, required: false},
        %{name: :limit, type: :integer, location: :query, required: false}
      ],
      responses: %{
        200 => %{description: "Users listed successfully"}
      }
    }
  end
  
  @impl true
  def execute(params) do
    users = Examples.BasicOperations.UserManagement.list_users()
    
    filtered_users = 
      users
      |> filter_by_role(Map.get(params, :role))
      |> limit_results(Map.get(params, :limit, 50))
    
    {:ok, %{
      users: filtered_users,
      total: length(users),
      filtered: length(filtered_users)
    }}
  end
  
  @impl true
  def format_response(%{users: users, total: total, filtered: filtered}) do
    %{
      status: "success",
      data: users,
      meta: %{
        total_users: total,
        returned_users: filtered,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end
  
  defp filter_by_role(users, nil), do: users
  defp filter_by_role(users, role), do: Enum.filter(users, &(&1.role == role))
  
  defp limit_results(users, limit), do: Enum.take(users, limit)
end