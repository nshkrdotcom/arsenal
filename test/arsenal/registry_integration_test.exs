defmodule Arsenal.RegistryIntegrationTest do
  use ExUnit.Case, async: true

  setup do
    # Ensure operations are registered before running tests
    # This makes the test independent of application startup timing
    {:ok, result} = Arsenal.Startup.register_all_operations()

    # Verify registration completed successfully
    assert result.successful > 0

    :ok
  end

  describe "operation registration" do
    test "new operations are registered on startup" do
      # Check that our new operations are registered
      operations = Arsenal.Registry.list_operations()
      operation_names = Enum.map(operations, & &1.name)

      assert :get_process_info in operation_names
      assert :restart_process in operation_names
      assert :kill_process in operation_names

      # Should have registered multiple operations
      assert length(operations) >= 3
    end

    test "can execute get_process_info through registry" do
      pid = self()

      assert {:ok, info} = Arsenal.Registry.execute_operation(:get_process_info, %{pid: pid})

      assert info.pid == pid
      assert is_integer(info.memory)
      assert is_atom(info.status)
    end

    test "can validate params through registry" do
      # Valid params
      assert {:ok, _} =
               Arsenal.Registry.validate_operation_params(:get_process_info, %{pid: self()})

      # Invalid params - missing pid
      assert {:error, _} = Arsenal.Registry.validate_operation_params(:get_process_info, %{})
    end
  end
end
