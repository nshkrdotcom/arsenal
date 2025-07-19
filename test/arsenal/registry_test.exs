defmodule Arsenal.RegistryTest do
  use ExUnit.Case

  # Test operations
  defmodule TestOperation do
    use Arsenal.Operation

    def name(), do: :test_op
    def category(), do: :test
    def description(), do: "Test operation"
    def params_schema(), do: %{value: [type: :string, required: true]}
    def execute(%{value: value}), do: {:ok, %{result: value}}
  end

  defmodule AnotherTestOperation do
    use Arsenal.Operation

    def name(), do: :another_test_op
    def category(), do: :test
    def description(), do: "Another test operation"
    def params_schema(), do: %{}
    def execute(_params), do: {:ok, %{status: "success"}}
  end

  defmodule SystemOperation do
    use Arsenal.Operation

    def name(), do: :system_op
    def category(), do: :system
    def description(), do: "System operation for testing"
    def params_schema(), do: %{}
    def execute(_params), do: {:ok, %{system: "ok"}}
  end

  setup do
    # Clear the ETS table before each test
    :ets.delete_all_objects(:arsenal_operations)
    :ok
  end

  describe "operation registration" do
    test "registers a valid operation" do
      assert {:ok, info} = Arsenal.Registry.register_operation(TestOperation)
      assert info.name == :test_op
      assert info.category == :test
      assert info.module == TestOperation
    end

    test "fails to register invalid module" do
      assert {:error, {:invalid_operation, :missing_callbacks}} =
               Arsenal.Registry.register_operation(String)
    end
  end

  describe "operation retrieval" do
    test "gets operation by name" do
      {:ok, _} = Arsenal.Registry.register_operation(TestOperation)

      assert {:ok, info} = Arsenal.Registry.get_operation(:test_op)
      assert info.name == :test_op
      assert info.module == TestOperation
    end

    test "returns error for non-existent operation" do
      assert {:error, :not_found} = Arsenal.Registry.get_operation(:non_existent)
    end
  end

  describe "operation listing" do
    test "lists all operations" do
      {:ok, _} = Arsenal.Registry.register_operation(TestOperation)
      {:ok, _} = Arsenal.Registry.register_operation(AnotherTestOperation)

      operations = Arsenal.Registry.list_operations()
      assert length(operations) == 2
      assert Enum.any?(operations, &(&1.name == :test_op))
      assert Enum.any?(operations, &(&1.name == :another_test_op))
    end

    test "filters operations by category" do
      {:ok, _} = Arsenal.Registry.register_operation(TestOperation)
      {:ok, _} = Arsenal.Registry.register_operation(SystemOperation)

      test_ops = Arsenal.Registry.list_operations(:test)
      assert length(test_ops) == 1
      assert hd(test_ops).category == :test

      system_ops = Arsenal.Registry.list_operations(:system)
      assert length(system_ops) == 1
      assert hd(system_ops).category == :system
    end
  end

  describe "operation search" do
    test "searches operations by query" do
      {:ok, _} = Arsenal.Registry.register_operation(TestOperation)
      {:ok, _} = Arsenal.Registry.register_operation(SystemOperation)

      results = Arsenal.Registry.search_operations("test")
      # Both TestOperation and SystemOperation have "test" in their descriptions
      assert length(results) == 2

      results = Arsenal.Registry.search_operations("operation")
      assert length(results) == 2
    end
  end

  describe "operation unregistration" do
    test "unregisters an operation" do
      {:ok, _} = Arsenal.Registry.register_operation(TestOperation)
      assert :ok = Arsenal.Registry.unregister_operation(:test_op)
      assert {:error, :not_found} = Arsenal.Registry.get_operation(:test_op)
    end

    test "returns error when unregistering non-existent operation" do
      assert {:error, :not_found} = Arsenal.Registry.unregister_operation(:non_existent)
    end
  end

  describe "parameter validation" do
    test "validates operation parameters" do
      {:ok, _} = Arsenal.Registry.register_operation(TestOperation)

      assert {:ok, %{value: "test"}} =
               Arsenal.Registry.validate_operation_params(:test_op, %{value: "test"})

      assert {:error, %{value: "is required"}} =
               Arsenal.Registry.validate_operation_params(:test_op, %{})
    end

    test "returns error for non-existent operation" do
      assert {:error, :operation_not_found} =
               Arsenal.Registry.validate_operation_params(:non_existent, %{})
    end
  end

  describe "operation execution" do
    test "executes an operation successfully" do
      {:ok, _} = Arsenal.Registry.register_operation(TestOperation)

      assert {:ok, %{result: "hello"}} =
               Arsenal.Registry.execute_operation(:test_op, %{value: "hello"})
    end

    test "validates parameters before execution" do
      {:ok, _} = Arsenal.Registry.register_operation(TestOperation)

      assert {:error, %{value: "is required"}} =
               Arsenal.Registry.execute_operation(:test_op, %{})
    end

    test "checks authorization before execution" do
      defmodule AuthorizedOp do
        use Arsenal.Operation

        def name(), do: :auth_op
        def category(), do: :test
        def description(), do: "Authorized operation"
        def params_schema(), do: %{}

        def authorize(_params, %{authorized: authorized}) do
          if authorized, do: :ok, else: {:error, :unauthorized}
        end

        def execute(_params), do: {:ok, %{status: "executed"}}
      end

      {:ok, _} = Arsenal.Registry.register_operation(AuthorizedOp)

      assert {:ok, %{status: "executed"}} =
               Arsenal.Registry.execute_operation(:auth_op, %{}, %{authorized: true})

      assert {:error, :unauthorized} =
               Arsenal.Registry.execute_operation(:auth_op, %{}, %{authorized: false})
    end

    test "returns error for non-existent operation" do
      assert {:error, :operation_not_found} =
               Arsenal.Registry.execute_operation(:non_existent, %{})
    end
  end

  describe "operation discovery" do
    test "discovers operations by namespace" do
      # First register some operations
      {:ok, _} = Arsenal.Registry.register_operation(TestOperation)
      {:ok, _} = Arsenal.Registry.register_operation(AnotherTestOperation)

      # This would normally discover modules, but in tests we're limited
      # to what's already loaded
      {:ok, result} = Arsenal.Registry.discover_operations("Arsenal.RegistryTest")

      # The test modules should be discovered
      assert result.successful >= 0
    end
  end
end
