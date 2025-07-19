#!/usr/bin/env elixir

# Standalone script to run basic operations examples
# Usage: elixir examples/run_basic_operations.exs

# Add the lib directory to the code path
Code.prepend_path("lib")

# Compile and load the Arsenal modules
Mix.install([
  {:jason, "~> 1.4"},
  {:telemetry, "~> 1.0"}
])

# Load Arsenal modules
Code.require_file("lib/arsenal.ex")
Code.require_file("lib/arsenal/operation.ex")
Code.require_file("lib/arsenal/operation/validator.ex")
Code.require_file("lib/arsenal/registry.ex")
Code.require_file("lib/arsenal/analytics_server.ex")
Code.require_file("lib/arsenal/startup.ex")

# Load example modules
Code.require_file("examples/basic_operations/simple_operation.ex")
Code.require_file("examples/basic_operations/user_management.ex")

defmodule BasicOperationsDemo do
  def run do
    IO.puts("🚀 Arsenal Basic Operations Demo")
    IO.puts("=" <> String.duplicate("=", 40))
    
    # Start Arsenal
    IO.puts("\n1. Starting Arsenal...")
    case Arsenal.start(:normal, []) do
      {:ok, _pid} -> IO.puts("   ✅ Arsenal started successfully")
      {:error, {:already_started, _}} -> IO.puts("   ✅ Arsenal already running")
      error -> 
        IO.puts("   ❌ Failed to start Arsenal: #{inspect(error)}")
        System.halt(1)
    end
    
    # Start user management storage
    IO.puts("\n2. Starting user management storage...")
    case Examples.BasicOperations.UserManagement.start_link([]) do
      {:ok, _pid} -> IO.puts("   ✅ User storage started")
      {:error, {:already_started, _}} -> IO.puts("   ✅ User storage already running")
      error -> 
        IO.puts("   ❌ Failed to start user storage: #{inspect(error)}")
        System.halt(1)
    end
    
    # Register operations
    IO.puts("\n3. Registering operations...")
    register_operations()
    
    # Demo factorial operation
    IO.puts("\n4. Testing Factorial Operation")
    IO.puts("-" <> String.duplicate("-", 30))
    demo_factorial()
    
    # Demo user operations
    IO.puts("\n5. Testing User Management Operations")
    IO.puts("-" <> String.duplicate("-", 40))
    demo_user_management()
    
    IO.puts("\n🎉 Basic Operations Demo Complete!")
    IO.puts("\nTry running the operations manually:")
    IO.puts("  Arsenal.Registry.execute_operation(:factorial, %{\"number\" => 6})")
    IO.puts("  Arsenal.Registry.execute_operation(:list_users, %{})")
  end
  
  defp register_operations do
    operations = [
      Examples.BasicOperations.SimpleOperation,
      Examples.BasicOperations.CreateUser,
      Examples.BasicOperations.GetUser,
      Examples.BasicOperations.ListUsers
    ]
    
    Enum.each(operations, fn module ->
      case Arsenal.Registry.register_operation(module) do
        {:ok, _config} -> IO.puts("   ✅ Registered #{module}")
        {:error, reason} -> IO.puts("   ⚠️  #{module}: #{inspect(reason)}")
      end
    end)
  end
  
  defp demo_factorial do
    test_cases = [
      %{"number" => 5},
      %{"number" => 0},
      %{"number" => "7"},  # String input
      %{"number" => -1},   # Invalid input
      %{"number" => 25}    # Too large
    ]
    
    Enum.each(test_cases, fn params ->
      IO.write("   Testing factorial(#{params["number"]}): ")
      
      case Arsenal.Registry.execute_operation(:factorial, params) do
        {:ok, result} ->
          IO.puts("✅ #{result.factorial}")
        
        {:error, reason} ->
          IO.puts("❌ #{inspect(reason)}")
      end
    end)
  end
  
  defp demo_user_management do
    # Create some users
    IO.puts("   Creating users...")
    
    users_to_create = [
      %{"name" => "Alice Smith", "email" => "alice@example.com", "age" => 30, "role" => "admin"},
      %{"name" => "Bob Jones", "email" => "bob@example.com", "age" => 25},
      %{"name" => "Carol Davis", "email" => "carol@example.com", "role" => "moderator"},
      %{"name" => "Invalid User", "email" => "not-an-email"},  # Invalid email
      %{"name" => "Alice Smith", "email" => "alice@example.com"}  # Duplicate email
    ]
    
    Enum.each(users_to_create, fn user_data ->
      IO.write("     Creating #{user_data["name"]}: ")
      
      case Arsenal.Registry.execute_operation(:create_user, user_data) do
        {:ok, user} ->
          IO.puts("✅ ID #{user.id}")
        
        {:error, reason} ->
          IO.puts("❌ #{inspect(reason)}")
      end
    end)
    
    # List all users
    IO.puts("\n   Listing all users...")
    case Arsenal.Registry.execute_operation(:list_users, %{}) do
      {:ok, result} ->
        IO.puts("     Total users: #{result.total}")
        IO.puts("     Returned: #{result.filtered}")
        
        Enum.each(result.users, fn user ->
          IO.puts("     - #{user.name} (#{user.email}) [#{user.role}]")
        end)
      
      {:error, reason} ->
        IO.puts("     ❌ Failed to list users: #{inspect(reason)}")
    end
    
    # Filter users by role
    IO.puts("\n   Filtering users by role (admin)...")
    case Arsenal.Registry.execute_operation(:list_users, %{"role" => "admin"}) do
      {:ok, result} ->
        IO.puts("     Found #{result.filtered} admin users:")
        Enum.each(result.users, fn user ->
          IO.puts("     - #{user.name} (#{user.role})")
        end)
      
      {:error, reason} ->
        IO.puts("     ❌ Failed to filter users: #{inspect(reason)}")
    end
    
    # Get a specific user (if any were created)
    case Arsenal.Registry.execute_operation(:list_users, %{}) do
      {:ok, %{users: [first_user | _]}} ->
        IO.puts("\n   Getting user by ID (#{first_user.id})...")
        case Arsenal.Registry.execute_operation(:get_user, %{"id" => first_user.id}) do
          {:ok, user} ->
            IO.puts("     ✅ Found: #{user.name} - #{user.email}")
          
          {:error, reason} ->
            IO.puts("     ❌ Failed to get user: #{inspect(reason)}")
        end
      
      _ ->
        IO.puts("\n   Skipping get user test (no users created)")
    end
  end
end

# Run the demo
BasicOperationsDemo.run()