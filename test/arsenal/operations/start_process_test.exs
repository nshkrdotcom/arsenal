defmodule Arsenal.Operations.StartProcessTest do
  use ExUnit.Case, async: true

  alias Arsenal.Operations.StartProcess

  # Helper module for testing
  defmodule TestWorker do
    def start_link(arg) do
      spawn_link(__MODULE__, :init, [arg])
    end

    def init(arg) do
      receive do
        :stop ->
          :ok

        msg ->
          send(arg[:reply_to], {:received, msg})
          init(arg)
      end
    end

    def simple_function do
      :ok
    end

    def function_with_args(x, y) do
      x + y
    end
  end

  describe "operation definition" do
    test "has correct name" do
      assert StartProcess.name() == :start_process
    end

    test "has correct category" do
      assert StartProcess.category() == :process
    end

    test "has valid params schema" do
      schema = StartProcess.params_schema()
      assert schema.module[:required] == true
      assert schema.function[:required] == true
      assert schema.args[:default] == []
      assert schema.link[:default] == false
    end

    test "has appropriate metadata" do
      metadata = StartProcess.metadata()
      assert metadata.requires_authentication == true
      assert metadata.minimum_role == :operator
      assert metadata.idempotent == false
    end
  end

  describe "parameter validation" do
    test "requires module and function" do
      assert {:error, %{module: "is required"}} =
               StartProcess.validate_params(%{function: :init})

      assert {:error, %{function: "is required"}} =
               StartProcess.validate_params(%{module: TestWorker})
    end

    test "accepts valid parameters" do
      params = %{
        module: TestWorker,
        function: :init,
        args: [%{reply_to: self()}]
      }

      assert {:ok, validated} = StartProcess.validate_params(params)
      assert validated.module == TestWorker
      assert validated.function == :init
      assert validated.link == false
      assert validated.monitor == false
    end

    test "converts string atoms when needed" do
      params = %{
        module: "Elixir.Process",
        function: "sleep",
        args: [1000]
      }

      assert {:ok, validated} = StartProcess.validate_params(params)
      assert validated.module == Process
      assert validated.function == :sleep
    end
  end

  describe "execution" do
    test "starts a simple process" do
      params = %{
        module: TestWorker,
        function: :simple_function,
        args: []
      }

      assert {:ok, result} = StartProcess.execute(params)
      assert is_pid(result.pid)
      assert result.linked == false
      assert result.monitored == false
    end

    test "starts a process with arguments" do
      params = %{
        module: TestWorker,
        function: :init,
        args: [%{reply_to: self()}]
      }

      assert {:ok, result} = StartProcess.execute(params)
      assert is_pid(result.pid)

      # Test that the process is alive and responsive
      send(result.pid, :ping)
      assert_receive {:received, :ping}, 1000

      # Clean up
      send(result.pid, :stop)
    end

    test "starts a linked process" do
      params = %{
        module: TestWorker,
        function: :init,
        args: [%{reply_to: self()}],
        link: true
      }

      assert {:ok, result} = StartProcess.execute(params)
      assert result.linked == true

      # Verify process is linked
      {:links, links} = Process.info(self(), :links)
      assert result.pid in links

      # Clean up
      Process.unlink(result.pid)
      send(result.pid, :stop)
    end

    test "starts a monitored process" do
      params = %{
        module: TestWorker,
        function: :init,
        args: [%{reply_to: self()}],
        monitor: true
      }

      assert {:ok, result} = StartProcess.execute(params)
      assert result.monitored == true

      # Kill the process and verify we get a DOWN message
      Process.exit(result.pid, :kill)
      pid = result.pid
      assert_receive {:DOWN, _ref, :process, ^pid, :killed}, 1000
    end

    test "registers a named process" do
      name = :test_registered_process

      params = %{
        module: TestWorker,
        function: :init,
        args: [%{reply_to: self()}],
        name: name
      }

      assert {:ok, result} = StartProcess.execute(params)
      assert result.registered_name == name
      assert Process.whereis(name) == result.pid

      # Clean up
      send(result.pid, :stop)
    end

    test "fails if named process already exists" do
      name = :test_duplicate_process

      params = %{
        module: TestWorker,
        function: :init,
        args: [%{reply_to: self()}],
        name: name
      }

      # Start first process
      assert {:ok, _result1} = StartProcess.execute(params)

      # Try to start duplicate
      assert {:error, reason} = StartProcess.execute(params)
      assert reason =~ "already registered"

      # Clean up
      if pid = Process.whereis(name) do
        send(pid, :stop)
      end
    end

    test "fails for non-existent module" do
      params = %{
        module: NonExistentModule,
        function: :start,
        args: []
      }

      assert {:error, reason} = StartProcess.execute(params)
      assert reason =~ "not loaded"
    end

    test "fails for non-existent function" do
      params = %{
        module: TestWorker,
        function: :non_existent_function,
        args: []
      }

      assert {:error, reason} = StartProcess.execute(params)
      assert reason =~ "not exported"
    end
  end

  describe "response formatting" do
    test "formats successful response" do
      params = %{
        module: TestWorker,
        function: :init,
        args: [%{reply_to: self()}]
      }

      {:ok, result} = StartProcess.execute(params)
      formatted = StartProcess.format_response({:ok, result})

      assert formatted.success == true
      assert formatted.data.pid =~ ~r/^#PID<\d+\.\d+\.\d+>$/
      assert formatted.data.linked == false
      assert formatted.data.monitored == false
      assert is_map(formatted.data.info)

      # Clean up
      send(result.pid, :stop)
    end

    test "formats error response" do
      formatted = StartProcess.format_response({:error, "Something went wrong"})

      assert formatted.success == false
      assert formatted.error.message == "Something went wrong"
      assert formatted.error.class == :execution
    end
  end
end
