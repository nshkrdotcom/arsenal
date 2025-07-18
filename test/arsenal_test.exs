defmodule ArsenalTest do
  use ExUnit.Case
  doctest Arsenal

  setup do
    # Ensure Arsenal is started (ignore if already started)
    case Arsenal.start(:normal, []) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
    :ok
  end

  test "registry is running" do
    assert Process.whereis(Arsenal.Registry) != nil
  end

  test "can list operations" do
    operations = Arsenal.list_operations()
    assert is_list(operations)
  end

  test "can execute GetProcessInfo operation" do
    # Test with self() process - extract just the numbers from PID
    pid_string = inspect(self()) |> String.trim_leading("#PID<") |> String.trim_trailing(">")
    result = Arsenal.execute_operation(
      Arsenal.Operations.GetProcessInfo, 
      %{"pid" => pid_string}
    )
    
    assert {:ok, process_info} = result
    assert is_map(process_info)
    assert Map.has_key?(process_info, :pid)
  end

  test "GetProcessInfo operation validates parameters" do
    # Test invalid PID
    result = Arsenal.execute_operation(
      Arsenal.Operations.GetProcessInfo,
      %{"pid" => "invalid"}
    )
    
    assert {:error, _reason} = result
  end

  test "can generate API docs" do
    docs = Arsenal.generate_api_docs()
    assert is_map(docs)
    assert Map.has_key?(docs, :openapi)
    assert Map.has_key?(docs, :paths)
  end
end
