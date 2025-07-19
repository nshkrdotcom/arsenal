defmodule Arsenal.Operations.GetProcessInfoTest do
  use ExUnit.Case, async: true

  alias Arsenal.Operations.GetProcessInfo

  describe "params_schema/0" do
    test "returns expected schema" do
      schema = GetProcessInfo.params_schema()

      assert schema.pid[:type] == :pid
      assert schema.pid[:required] == true
      assert schema.keys[:type] == :list
      assert schema.keys[:default] == :all
    end
  end

  describe "execute/1" do
    test "gets process info for alive process" do
      # Use self() as a test process
      pid = self()

      assert {:ok, info} = GetProcessInfo.execute(%{pid: pid})

      assert info.pid == pid
      assert is_integer(info.memory)
      assert is_integer(info.message_queue_len)
      assert is_atom(info.status)
    end

    test "returns error for dead process" do
      # Create and kill a process
      pid = spawn(fn -> :ok end)
      # Ensure process has died
      Process.sleep(10)

      assert {:error, {:process_not_alive, ^pid}} = GetProcessInfo.execute(%{pid: pid})
    end

    test "gets specific keys when requested" do
      pid = self()

      assert {:ok, info} = GetProcessInfo.execute(%{pid: pid, keys: [:memory, :status]})

      assert Map.has_key?(info, :memory)
      assert Map.has_key?(info, :status)
      assert Map.has_key?(info, :pid)
    end
  end

  describe "validate_params/1" do
    test "accepts valid pid" do
      pid = self()
      assert {:ok, %{pid: ^pid, keys: :all}} = GetProcessInfo.validate_params(%{pid: pid})
    end

    test "accepts pid with specific keys" do
      pid = self()
      keys = [:memory, :status]

      assert {:ok, %{pid: ^pid, keys: ^keys}} =
               GetProcessInfo.validate_params(%{pid: pid, keys: keys})
    end

    test "rejects invalid keys" do
      pid = self()

      assert {:error, %{keys: _}} =
               GetProcessInfo.validate_params(%{pid: pid, keys: "not_a_list"})
    end
  end

  describe "format_response/1" do
    test "formats successful response" do
      result = {:ok, %{pid: self(), memory: 1000, status: :running}}
      response = GetProcessInfo.format_response(result)

      assert response.success == true
      assert is_map(response.data)
    end

    test "formats error response" do
      result = {:error, :process_not_alive}
      response = GetProcessInfo.format_response(result)

      assert response.success == false
      assert response.error == :process_not_alive
    end
  end
end
