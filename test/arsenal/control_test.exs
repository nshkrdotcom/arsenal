defmodule Arsenal.ControlTest do
  use ExUnit.Case, async: true

  alias Arsenal.Control

  import Supertester.OTPHelpers
  import Supertester.Assertions
  import ExUnit.CaptureLog

  @moduletag :capture_log

  doctest Arsenal.Control

  describe "get_supervisor_tree/1" do
    test "returns supervisor tree for valid supervisor atom" do
      # Use kernel_sup as it's always available
      assert {:ok, tree} = Control.get_supervisor_tree(:kernel_sup)
      assert is_map(tree)
      assert Map.has_key?(tree, :pid)
      assert Map.has_key?(tree, :children)
      assert Map.has_key?(tree, :strategy)
      assert is_list(tree.children)
    end

    test "returns supervisor tree for valid supervisor pid" do
      kernel_sup_pid = Process.whereis(:kernel_sup)
      assert {:ok, tree} = Control.get_supervisor_tree(kernel_sup_pid)
      assert is_map(tree)
      assert tree.pid == kernel_sup_pid
    end

    test "returns error for non-existent supervisor atom" do
      assert {:error, {:supervisor_not_found, :non_existent_sup}} =
               Control.get_supervisor_tree(:non_existent_sup)
    end

    test "returns error for dead process" do
      dead_task = Task.async(fn -> :ok end)
      dead_pid = dead_task.pid

      # Wait for process to die naturally
      Task.await(dead_task, 1000)
      assert_process_dead(dead_pid)

      assert {:error, {:process_not_alive, ^dead_pid}} =
               Control.get_supervisor_tree(dead_pid)
    end

    test "returns error for non-supervisor process" do
      regular_task =
        Task.async(fn ->
          receive do
            :stop -> :ok
          after
            1000 -> :timeout
          end
        end)

      regular_pid = regular_task.pid

      assert {:error, {:not_a_supervisor, ^regular_pid}} =
               Control.get_supervisor_tree(regular_pid)

      # Clean up properly
      send(regular_pid, :stop)
      Task.await(regular_task, 1000)
    end
  end

  describe "get_process_info/1" do
    test "returns enhanced process info for valid process" do
      assert {:ok, info} = Control.get_process_info(self())
      assert is_map(info)

      # Check required fields
      required_fields = [
        :pid,
        :status,
        :memory,
        :message_queue_len,
        :links,
        :monitors,
        :monitored_by,
        :trap_exit,
        :priority,
        :reductions,
        :current_function,
        :initial_call,
        :application,
        :supervisor,
        :restart_count,
        :last_restart
      ]

      Enum.each(required_fields, fn field ->
        assert Map.has_key?(info, field), "Missing field: #{field}"
      end)

      assert info.pid == self()
      assert is_integer(info.memory)
      assert is_integer(info.message_queue_len)
      assert is_list(info.links)
      assert is_list(info.monitors)
    end

    test "returns error for dead process" do
      dead_task = Task.async(fn -> :ok end)
      dead_pid = dead_task.pid

      # Wait for process to die naturally
      Task.await(dead_task, 1000)
      assert_process_dead(dead_pid)

      assert {:error, {:process_not_alive, ^dead_pid}} =
               Control.get_process_info(dead_pid)
    end

    test "includes application information when available" do
      assert {:ok, info} = Control.get_process_info(self())
      # Application might be nil for test processes, but field should exist
      assert Map.has_key?(info, :application)
    end
  end

  describe "restart_child/2" do
    test "handles restart_child with running child" do
      # Create a regular supervisor for this test
      {:ok, regular_sup} = Supervisor.start_link([], strategy: :one_for_one)

      # Create a controlled task for the child
      child_task =
        Task.async(fn ->
          receive do
            :stop -> :ok
          after
            5000 -> :timeout
          end
        end)

      # First, start a child
      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Task.await(child_task, 6000) end]},
        restart: :permanent
      }

      {:ok, _child_pid} = Supervisor.start_child(regular_sup, child_spec)

      # Try to restart a running child - this should return an error
      assert {:error, {:child_already_running, :test_child}} =
               Control.restart_child(regular_sup, :test_child)

      # Clean up the child task
      send(child_task.pid, :stop)

      # Clean up the supervisor
      if Process.alive?(regular_sup), do: Supervisor.stop(regular_sup)
    end

    test "returns error for non-existent child" do
      # Create a regular supervisor for this test
      {:ok, regular_sup} = Supervisor.start_link([], strategy: :one_for_one)

      # Perform the test
      assert {:error, {:child_not_found, :non_existent}} =
               Control.restart_child(regular_sup, :non_existent)

      # Clean up manually
      if Process.alive?(regular_sup), do: Supervisor.stop(regular_sup)
    end

    test "works with supervisor atom name" do
      # Create a regular supervisor and register it with a unique name
      unique_name = :"test_supervisor_#{System.unique_integer([:positive])}"

      {:ok, regular_sup} = Supervisor.start_link([], strategy: :one_for_one, name: unique_name)

      # This should work with the named supervisor
      assert {:error, {:child_not_found, :some_child}} =
               Control.restart_child(unique_name, :some_child)

      # Clean up manually
      if Process.alive?(regular_sup), do: Supervisor.stop(regular_sup)
    end

    test "returns error for non-existent supervisor atom" do
      assert {:error, {:supervisor_not_found, :non_existent}} =
               Control.restart_child(:non_existent, :child)
    end
  end

  describe "kill_process/2" do
    test "terminates regular process successfully" do
      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          after
            5000 -> :timeout
          end
        end)

      log =
        capture_log(fn ->
          assert {:ok, result} = Control.kill_process(test_pid, :kill)

          assert result.pid == test_pid
          assert result.reason == :kill
          assert result.terminated == true
          assert %DateTime{} = result.timestamp
        end)

      # Verify the expected log messages were captured
      assert log =~ "Attempting to terminate process"
      assert log =~ "Successfully terminated process"

      # Verify process is actually dead
      {:ok, _reason} = wait_for_process_death(test_pid, 1000)
      assert_process_dead(test_pid)
    end

    test "returns error for dead process" do
      dead_task = Task.async(fn -> :ok end)
      dead_pid = dead_task.pid

      # Wait for process to die naturally
      Task.await(dead_task, 1000)
      assert_process_dead(dead_pid)

      assert {:error, {:process_not_alive, ^dead_pid}} =
               Control.kill_process(dead_pid, :normal)
    end

    test "protects critical system processes" do
      kernel_sup_pid = Process.whereis(:kernel_sup)

      assert {:error, {:process_protected, ^kernel_sup_pid}} =
               Control.kill_process(kernel_sup_pid, :kill)
    end

    test "allows forced termination of protected processes" do
      # We won't actually test this with real system processes
      # Instead, we'll test the force flag logic with a mock protected process
      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          after
            5000 -> :timeout
          end
        end)

      capture_log(fn ->
        # This should work normally since test_pid is not actually protected
        assert {:ok, _result} = Control.kill_process(test_pid, :kill, force: true)
      end)

      # Verify termination
      {:ok, _reason} = wait_for_process_death(test_pid, 1000)
      assert_process_dead(test_pid)
    end

    test "respects timeout option" do
      # Create a process that traps exits
      test_task =
        Task.async(fn ->
          Process.flag(:trap_exit, true)

          receive do
            # Ignore exit signal initially
            {:EXIT, _from, _reason} ->
              receive do
                :stop -> :ok
              after
                10000 -> :timeout
              end
          end
        end)

      test_pid = test_task.pid

      log =
        capture_log(fn ->
          assert {:ok, result} = Control.kill_process(test_pid, :normal, timeout: 100)
          # With short timeout, process might not be terminated
          assert is_boolean(result.terminated)
        end)

      # Verify the expected log messages were captured
      assert log =~ "Attempting to terminate process"
      assert log =~ "did not terminate within timeout"

      # Clean up properly
      send(test_pid, :stop)
      Task.await(test_task, 1000)
    end
  end

  describe "suspend_process/1 and resume_process/1" do
    test "suspends and resumes process successfully" do
      test_task =
        Task.async(fn ->
          receive do
            :stop -> :ok
          after
            10000 -> :timeout
          end
        end)

      test_pid = test_task.pid

      capture_log(fn ->
        assert :ok = Control.suspend_process(test_pid)
        assert :ok = Control.resume_process(test_pid)
      end)

      # Clean up properly
      send(test_pid, :stop)
      Task.await(test_task, 1000)
    end

    test "returns error for dead process on suspend" do
      dead_task = Task.async(fn -> :ok end)
      dead_pid = dead_task.pid

      # Wait for process to die naturally
      Task.await(dead_task, 1000)
      assert_process_dead(dead_pid)

      assert {:error, {:process_not_alive, ^dead_pid}} =
               Control.suspend_process(dead_pid)
    end

    test "returns error for dead process on resume" do
      dead_task = Task.async(fn -> :ok end)
      dead_pid = dead_task.pid

      # Wait for process to die naturally
      Task.await(dead_task, 1000)
      assert_process_dead(dead_pid)

      assert {:error, {:process_not_alive, ^dead_pid}} =
               Control.resume_process(dead_pid)
    end

    test "protects critical processes from suspension" do
      kernel_sup_pid = Process.whereis(:kernel_sup)

      assert {:error, {:process_protected, ^kernel_sup_pid}} =
               Control.suspend_process(kernel_sup_pid)
    end
  end

  describe "is_protected_process?/1" do
    test "identifies protected system processes" do
      kernel_sup_pid = Process.whereis(:kernel_sup)
      assert Control.is_protected_process?(kernel_sup_pid) == true
    end

    test "identifies regular processes as not protected" do
      test_task =
        Task.async(fn ->
          receive do
            :stop -> :ok
          after
            1000 -> :timeout
          end
        end)

      test_pid = test_task.pid

      assert Control.is_protected_process?(test_pid) == false

      # Clean up properly
      send(test_pid, :stop)
      Task.await(test_task, 1000)
    end

    test "handles processes with registered names" do
      # Test with a known system process
      case Process.whereis(:application_controller) do
        # Not available in test environment
        nil -> :skip
        pid -> assert Control.is_protected_process?(pid) == true
      end
    end
  end
end
