defmodule Arsenal.RegistryIntegrationTest do
  use ExUnit.Case

  describe "operation registration" do
    test "new operations are registered on startup" do
      # Wait a bit for startup registration
      Process.sleep(200)

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
      Process.sleep(200)

      pid = self()

      assert {:ok, info} = Arsenal.Registry.execute_operation(:get_process_info, %{pid: pid})

      assert info.pid == pid
      assert is_integer(info.memory)
      assert is_atom(info.status)
    end

    test "can validate params through registry" do
      Process.sleep(200)

      # Valid params
      assert {:ok, _} =
               Arsenal.Registry.validate_operation_params(:get_process_info, %{pid: self()})

      # Invalid params - missing pid
      assert {:error, _} = Arsenal.Registry.validate_operation_params(:get_process_info, %{})
    end
  end
end
