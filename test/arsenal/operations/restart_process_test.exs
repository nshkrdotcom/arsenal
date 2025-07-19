defmodule Arsenal.Operations.RestartProcessTest do
  use ExUnit.Case, async: true

  alias Arsenal.Operations.RestartProcess

  defmodule TestWorker do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      {:ok, opts}
    end
  end

  describe "params_schema/0" do
    test "returns expected schema" do
      schema = RestartProcess.params_schema()

      assert schema.pid[:type] == :pid
      assert schema.pid[:required] == true
      assert schema.reason[:type] == :atom
      assert schema.reason[:default] == :restart
      assert schema.timeout[:type] == :integer
      assert schema.timeout[:default] == 5000
    end
  end

  describe "execute/1" do
    test "restarts a supervised process" do
      # Start a supervisor with a worker
      children = [
        {TestWorker, []}
      ]

      {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)
      [{_, worker_pid, _, _}] = Supervisor.which_children(sup)

      # Restart the worker
      assert {:ok, result} =
               RestartProcess.execute(%{
                 pid: worker_pid,
                 reason: :restart,
                 timeout: 5000
               })

      assert result.old_pid == worker_pid
      assert is_pid(result.new_pid)
      assert result.new_pid != worker_pid
      assert Process.alive?(result.new_pid)

      Supervisor.stop(sup)
    end

    test "returns error for non-supervised process" do
      # Create a standalone process
      pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      assert {:error, :process_not_supervised} =
               RestartProcess.execute(%{
                 pid: pid,
                 reason: :restart,
                 timeout: 1000
               })

      send(pid, :stop)
    end

    test "returns error for dead process" do
      pid = spawn(fn -> :ok end)
      Process.sleep(10)

      assert {:error, :process_not_alive} =
               RestartProcess.execute(%{
                 pid: pid,
                 reason: :restart,
                 timeout: 1000
               })
    end
  end

  describe "metadata/0" do
    test "indicates operation is dangerous" do
      metadata = RestartProcess.metadata()

      assert metadata.dangerous == true
      assert metadata.requires_authentication == true
      assert metadata.idempotent == false
    end
  end
end
