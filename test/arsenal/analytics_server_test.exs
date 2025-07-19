defmodule Arsenal.AnalyticsServerTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  setup do
    # Start isolated AnalyticsServer without name conflicts
    # We need to start it directly without the registered name to avoid conflicts
    {:ok, pid} =
      GenServer.start_link(Arsenal.AnalyticsServer,
        monitoring_interval: 1000,
        retention_period: 5000
      )

    on_exit(fn ->
      try do
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      catch
        :exit, _ -> :ok
      end
    end)

    %{server: pid}
  end

  # Wrapper functions to work with isolated server instances
  defp track_restart(server, supervisor, child_id, reason) do
    GenServer.cast(server, {:track_restart, supervisor, child_id, reason})
  end

  defp get_restart_statistics(server, supervisor) do
    GenServer.call(server, {:get_restart_statistics, supervisor})
  end

  defp get_server_stats(server) do
    GenServer.call(server, :get_server_stats)
  end

  defp get_historical_data(server, start_time, end_time) do
    GenServer.call(server, {:get_historical_data, start_time, end_time})
  end

  defp force_health_check(server) do
    GenServer.cast(server, :force_health_check)
  end

  defp subscribe_to_events(server, event_types, filter \\ nil) do
    GenServer.call(server, {:subscribe_to_events, self(), event_types, filter})
  end

  defp unsubscribe_from_events(server) do
    GenServer.call(server, {:unsubscribe_from_events, self()})
  end

  defp get_system_health(server) do
    GenServer.call(server, :get_system_health)
  end

  defp get_performance_metrics(server) do
    GenServer.call(server, :get_performance_metrics)
  end

  describe "start_link/1" do
    test "starts with default configuration" do
      {:ok, pid} = GenServer.start_link(Arsenal.AnalyticsServer, [])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom configuration" do
      opts = [monitoring_interval: 1000, retention_period: 10000, anomaly_threshold: 1.5]
      {:ok, pid} = GenServer.start_link(Arsenal.AnalyticsServer, opts)
      assert Process.alive?(pid)

      {:ok, stats} = GenServer.call(pid, :get_server_stats)
      assert stats.monitoring_interval == 1000
      assert stats.retention_period == 10000

      GenServer.stop(pid)
    end
  end

  describe "track_restart/3" do
    test "tracks supervisor restart events", %{server: server} do
      supervisor = :test_supervisor
      child_id = :worker_1
      reason = :normal

      :ok = track_restart(server, supervisor, child_id, reason)

      # Give some time for the cast to be processed
      {:ok, _} = get_server_stats(server)

      {:ok, stats} = get_restart_statistics(server, :all)
      assert stats.total_restarts == 1
      assert Map.has_key?(stats.restart_reasons, :normal)
      assert stats.restart_reasons[:normal] == 1
    end

    test "tracks multiple restart events", %{server: server} do
      # Track multiple restarts
      track_restart(server, :sup1, :worker1, :normal)
      track_restart(server, :sup1, :worker2, :killed)
      track_restart(server, :sup2, :worker1, :normal)

      {:ok, _} = get_server_stats(server)

      {:ok, all_stats} = get_restart_statistics(server, :all)
      assert all_stats.total_restarts == 3

      {:ok, sup1_stats} = get_restart_statistics(server, :sup1)
      assert sup1_stats.total_restarts == 2
    end

    test "tracks restart count for same child", %{server: server} do
      supervisor = :test_supervisor
      child_id = :worker_1

      # Track multiple restarts for the same child
      track_restart(server, supervisor, child_id, :normal)
      track_restart(server, supervisor, child_id, :killed)
      track_restart(server, supervisor, child_id, :normal)

      {:ok, _} = get_server_stats(server)

      {:ok, stats} = get_restart_statistics(server, supervisor)

      # Find the worker in most restarted children
      worker_stats =
        Enum.find(stats.most_restarted_children, fn child ->
          child.child_id == child_id
        end)

      assert worker_stats != nil
      assert worker_stats.count == 3
    end
  end

  describe "get_restart_statistics/1" do
    test "returns empty statistics when no restarts tracked", %{server: server} do
      {:ok, stats} = get_restart_statistics(server, :all)

      assert stats.total_restarts == 0
      assert stats.restart_rate == 0.0
      assert stats.most_restarted_children == []
      assert stats.restart_reasons == %{}
      assert stats.time_between_restarts == []
      assert stats.patterns == []
    end

    test "calculates restart statistics correctly", %{server: server} do
      # Track some restarts
      track_restart(server, :sup1, :worker1, :normal)
      track_restart(server, :sup1, :worker1, :killed)
      track_restart(server, :sup2, :worker2, :normal)

      {:ok, _} = get_server_stats(server)

      {:ok, stats} = get_restart_statistics(server, :all)

      assert stats.total_restarts == 3
      assert is_float(stats.restart_rate)
      assert length(stats.most_restarted_children) > 0
      assert Map.has_key?(stats.restart_reasons, :normal)
      assert Map.has_key?(stats.restart_reasons, :killed)
    end

    test "filters statistics by supervisor", %{server: server} do
      track_restart(server, :sup1, :worker1, :normal)
      track_restart(server, :sup2, :worker2, :killed)

      {:ok, _} = get_server_stats(server)

      {:ok, sup1_stats} = get_restart_statistics(server, :sup1)
      {:ok, sup2_stats} = get_restart_statistics(server, :sup2)

      assert sup1_stats.total_restarts == 1
      assert sup2_stats.total_restarts == 1
      assert sup1_stats.restart_reasons == %{normal: 1}
      assert sup2_stats.restart_reasons == %{killed: 1}
    end
  end

  describe "get_system_health/0" do
    test "returns system health information", %{server: server} do
      {:ok, health} = get_system_health(server)

      assert health.overall_status in [:healthy, :warning, :critical]
      assert is_integer(health.process_count)
      assert health.process_count > 0
      assert is_map(health.memory_usage)
      assert is_float(health.cpu_usage)
      assert is_float(health.restart_rate)
      assert is_map(health.message_queue_lengths)
      assert is_list(health.anomalies)
      assert is_list(health.recommendations)
      assert %DateTime{} = health.last_check
    end

    test "memory usage contains expected fields", %{server: server} do
      {:ok, health} = get_system_health(server)

      memory = health.memory_usage
      assert is_integer(memory.total)
      assert is_integer(memory.processes)
      assert is_integer(memory.system)
      assert is_integer(memory.atom)
      assert is_integer(memory.binary)
      assert is_integer(memory.code)
      assert is_integer(memory.ets)
    end

    test "message queue analysis contains expected fields", %{server: server} do
      {:ok, health} = get_system_health(server)

      queues = health.message_queue_lengths
      assert is_integer(queues.max)
      assert is_float(queues.average)
      assert is_integer(queues.processes_with_long_queues)
    end
  end

  describe "get_performance_metrics/0" do
    test "returns comprehensive performance metrics", %{server: server} do
      {:ok, metrics} = get_performance_metrics(server)

      # Check CPU metrics
      assert is_map(metrics.cpu)
      assert is_float(metrics.cpu.utilization)
      assert is_list(metrics.cpu.load_average)
      assert is_list(metrics.cpu.scheduler_utilization)

      # Check memory metrics
      assert is_map(metrics.memory)
      assert is_integer(metrics.memory.total)
      assert is_integer(metrics.memory.processes)
      assert is_integer(metrics.memory.system)

      # Check process metrics
      assert is_map(metrics.processes)
      assert is_integer(metrics.processes.count)
      assert is_integer(metrics.processes.limit)
      assert is_float(metrics.processes.utilization)

      # Check I/O metrics
      assert is_map(metrics.io)
      assert is_integer(metrics.io.input)
      assert is_integer(metrics.io.output)

      # Check GC metrics
      assert is_map(metrics.gc)
      assert is_integer(metrics.gc.collections)
      assert is_integer(metrics.gc.words_reclaimed)

      # Check timestamp
      assert %DateTime{} = metrics.timestamp
    end

    test "metrics are reasonable values", %{server: server} do
      {:ok, metrics} = get_performance_metrics(server)

      # CPU utilization should be between 0 and 100
      assert metrics.cpu.utilization >= 0
      assert metrics.cpu.utilization <= 100

      # Process count should be positive and less than limit
      assert metrics.processes.count > 0
      assert metrics.processes.count <= metrics.processes.limit

      # Memory values should be positive
      assert metrics.memory.total > 0
      assert metrics.memory.processes > 0
      assert metrics.memory.system > 0
    end
  end

  describe "event subscription system" do
    test "subscribes and receives restart events", %{server: server} do
      # Subscribe to restart events
      :ok = subscribe_to_events(server, [:restart])

      # Track a restart
      track_restart(server, :test_sup, :worker1, :normal)

      # Should receive the event
      assert_receive {:arsenal_analytics_event, :restart, event_data}, 1000

      assert event_data.supervisor == :test_sup
      assert event_data.child_id == :worker1
      assert event_data.reason == :normal
      assert %DateTime{} = event_data.timestamp
    end

    test "subscribes to multiple event types", %{server: server} do
      :ok = subscribe_to_events(server, [:restart, :health_alert])

      # Track a restart
      track_restart(server, :test_sup, :worker1, :normal)

      # Should receive restart event
      assert_receive {:arsenal_analytics_event, :restart, _event_data}, 1000
    end

    test "subscribes to all events", %{server: server} do
      :ok = subscribe_to_events(server, [:all])

      # Track a restart
      track_restart(server, :test_sup, :worker1, :normal)

      # Should receive the event
      assert_receive {:arsenal_analytics_event, :restart, _event_data}, 1000
    end

    test "unsubscribes from events", %{server: server} do
      # Subscribe first
      :ok = subscribe_to_events(server, [:restart])

      # Unsubscribe
      :ok = unsubscribe_from_events(server)

      # Track a restart
      track_restart(server, :test_sup, :worker1, :normal)

      # Should not receive the event
      refute_receive {:arsenal_analytics_event, :restart, _event_data}, 100
    end

    test "filters events with custom filter", %{server: server} do
      # Subscribe with filter for only :normal reason
      filter = fn event -> event.reason == :normal end
      :ok = subscribe_to_events(server, [:restart], filter)

      # Track restarts with different reasons
      track_restart(server, :test_sup, :worker1, :normal)
      track_restart(server, :test_sup, :worker2, :killed)

      # Should only receive the :normal restart
      assert_receive {:arsenal_analytics_event, :restart, event_data}, 1000
      assert event_data.reason == :normal

      # Should not receive the :killed restart
      refute_receive {:arsenal_analytics_event, :restart, %{reason: :killed}}, 100
    end

    test "cleans up subscriptions when subscriber dies", %{server: server} do
      # Spawn a process that subscribes and then dies
      subscriber_pid =
        spawn(fn ->
          subscribe_to_events(server, [:restart])
          {:ok, _} = get_server_stats(server)
        end)

      # Wait for subscriber to die
      ref = Process.monitor(subscriber_pid)
      assert_receive {:DOWN, ^ref, :process, ^subscriber_pid, _reason}, 1000

      # Give the server time to clean up
      {:ok, _} = get_server_stats(server)

      # Check that subscription was cleaned up
      {:ok, stats} = GenServer.call(server, :get_server_stats)
      assert stats.active_subscriptions == 0
    end
  end

  describe "get_historical_data/2" do
    test "returns historical data for time range", %{server: server} do
      # Track some events
      track_restart(server, :sup1, :worker1, :normal)
      {:ok, _} = get_server_stats(server)

      # Force a health check to generate data
      force_health_check(server)
      # Wait for health check to complete
      {:ok, _} = get_server_stats(server)

      # Get historical data
      end_time = DateTime.utc_now()
      start_time = DateTime.add(end_time, -60, :second)

      {:ok, data} = get_historical_data(server, start_time, end_time)

      assert is_map(data)
      assert Map.has_key?(data, :time_range)
      assert Map.has_key?(data, :metrics)
      assert Map.has_key?(data, :restarts)
      assert Map.has_key?(data, :health_checks)
      assert Map.has_key?(data, :events)

      assert data.time_range.start == start_time
      assert data.time_range.end == end_time
      assert is_list(data.metrics)
      assert is_list(data.restarts)
      assert is_list(data.health_checks)
    end

    test "filters data by time range correctly", %{server: server} do
      # Track an event
      track_restart(server, :sup1, :worker1, :normal)
      {:ok, _} = get_server_stats(server)

      # Get historical data for a future time range (should be empty)
      start_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      end_time = DateTime.add(start_time, 60, :second)

      {:ok, data} = get_historical_data(server, start_time, end_time)

      assert length(data.restarts) == 0
      assert length(data.metrics) == 0
      assert length(data.health_checks) == 0
    end
  end

  describe "force_health_check/0" do
    test "triggers immediate health check", %{server: server} do
      # Get initial stats
      {:ok, initial_stats} = get_server_stats(server)
      initial_health_checks = initial_stats.health_checks

      # Force health check
      :ok = force_health_check(server)
      # Wait for health check to complete
      {:ok, _} = get_server_stats(server)

      # Check that health check count increased
      {:ok, new_stats} = get_server_stats(server)
      assert new_stats.health_checks > initial_health_checks
    end
  end

  describe "get_server_stats/0" do
    test "returns server statistics", %{server: server} do
      {:ok, stats} = get_server_stats(server)

      assert is_integer(stats.uptime)
      assert is_integer(stats.restart_events_tracked)
      assert is_integer(stats.performance_samples)
      assert is_integer(stats.health_checks)
      assert is_integer(stats.active_subscriptions)
      assert is_integer(stats.monitoring_interval)
      assert is_integer(stats.retention_period)

      # Uptime should be positive
      assert stats.uptime > 0

      # Initially should have no events tracked
      assert stats.restart_events_tracked == 0
      assert stats.active_subscriptions == 0
    end

    test "tracks events correctly in stats", %{server: server} do
      # Track some restarts
      track_restart(server, :sup1, :worker1, :normal)
      track_restart(server, :sup1, :worker2, :killed)
      {:ok, _} = get_server_stats(server)

      # Subscribe to events
      subscribe_to_events(server, [:restart])

      {:ok, stats} = get_server_stats(server)

      assert stats.restart_events_tracked == 2
      assert stats.active_subscriptions == 1
    end
  end

  describe "anomaly detection" do
    test "detects rapid restart cycles", %{server: server} do
      # Subscribe to anomaly events
      :ok = subscribe_to_events(server, [:anomaly])

      # Trigger rapid restarts for the same child (should trigger anomaly)
      supervisor = :test_supervisor
      child_id = :problematic_worker

      for _i <- 1..5 do
        track_restart(server, supervisor, child_id, :killed)
        # Wait between restarts
        {:ok, _} = get_server_stats(server)
      end

      # Should receive anomaly notification
      assert_receive {:arsenal_analytics_event, :anomaly, anomaly_data}, 1000

      assert anomaly_data.type == :restart_anomaly
      assert anomaly_data.severity == :high
      assert anomaly_data.child_id == child_id
      assert anomaly_data.supervisor == supervisor
    end
  end

  describe "data cleanup" do
    test "handles cleanup messages gracefully", %{server: server} do
      # Track some events
      track_restart(server, :sup1, :worker1, :normal)
      {:ok, _} = get_server_stats(server)

      # Verify event is tracked
      {:ok, stats_before} = get_restart_statistics(server, :all)
      assert stats_before.total_restarts == 1

      # Send cleanup message and verify server remains responsive
      send(server, :cleanup)
      {:ok, _} = get_server_stats(server)

      # Verify server is still functional after cleanup
      {:ok, stats_after} = get_restart_statistics(server, :all)
      assert is_integer(stats_after.total_restarts)

      # Server should still be able to track new events
      track_restart(server, :sup2, :worker2, :killed)
      {:ok, _} = get_server_stats(server)

      {:ok, final_stats} = get_restart_statistics(server, :all)
      assert final_stats.total_restarts >= 1
    end
  end

  describe "error handling" do
    test "handles invalid supervisor in restart tracking gracefully", %{server: server} do
      # This should not crash the server
      :ok = track_restart(server, nil, :worker1, :normal)
      {:ok, _} = get_server_stats(server)

      # Server should still be responsive
      {:ok, _stats} = get_server_stats(server)
    end

    test "handles system info collection errors gracefully", %{server: server} do
      # Even if system info collection fails, the server should continue working
      {:ok, _health} = get_system_health(server)
      {:ok, _metrics} = get_performance_metrics(server)
    end
  end

  describe "integration with real supervisors" do
    test "works with actual supervisor processes" do
      # Start isolated server and test supervisor
      {:ok, server} = GenServer.start_link(Arsenal.AnalyticsServer, [])
      {:ok, sup_pid} = Supervisor.start_link([], strategy: :one_for_one)

      # Track restart for real supervisor
      :ok = track_restart(server, sup_pid, :test_worker, :normal)
      {:ok, _} = get_server_stats(server)

      {:ok, stats} = get_restart_statistics(server, sup_pid)
      assert stats.total_restarts == 1

      Supervisor.stop(sup_pid)
      GenServer.stop(server)
    end
  end
end
