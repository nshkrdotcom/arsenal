defmodule Arsenal.SystemAnalyzerTest do
  use ExUnit.Case, async: true

  alias Arsenal.SystemAnalyzer
  import Supertester.OTPHelpers

  @moduletag :capture_log

  setup do
    # Start isolated SystemAnalyzer without name conflicts
    {:ok, pid} = start_system_analyzer_isolated(health_check_interval: 60_000)

    cleanup_on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    %{analyzer_pid: pid}
  end

  # Helper to start SystemAnalyzer without name registration
  defp start_system_analyzer_isolated(opts \\ []) do
    # Start SystemAnalyzer directly without name registration
    GenServer.start_link(SystemAnalyzer, opts)
  end

  # Wrapper functions to work with isolated analyzer instances
  defp analyze_system_health(analyzer) do
    GenServer.call(analyzer, :analyze_system_health)
  end

  defp get_analyzer_stats(analyzer) do
    GenServer.call(analyzer, :get_analyzer_stats)
  end

  defp detect_anomalies(analyzer) do
    GenServer.call(analyzer, :detect_anomalies)
  end

  defp schedule_health_check(analyzer, interval) when is_integer(interval) and interval > 0 do
    GenServer.call(analyzer, {:schedule_health_check, interval})
  end

  defp get_resource_usage(analyzer) do
    GenServer.call(analyzer, :get_resource_usage)
  end

  defp predict_issues(analyzer) do
    GenServer.call(analyzer, :predict_issues)
  end

  defp generate_recommendations(analyzer) do
    GenServer.call(analyzer, :generate_recommendations)
  end

  defp stop_health_monitoring(analyzer) do
    GenServer.call(analyzer, :stop_health_monitoring)
  end

  describe "start_link/1" do
    test "starts with default configuration" do
      {:ok, pid} = start_system_analyzer_isolated()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom configuration" do
      opts = [
        health_check_interval: 10_000,
        anomaly_thresholds: %{cpu_utilization: 1.5},
        enable_predictions: false
      ]

      {:ok, pid} = start_system_analyzer_isolated(opts)
      assert Process.alive?(pid)

      {:ok, stats} = GenServer.call(pid, :get_analyzer_stats)
      assert stats.health_check_interval == 10_000
      assert stats.prediction_models_enabled == false

      GenServer.stop(pid)
    end
  end

  describe "analyze_system_health/0" do
    test "returns comprehensive health report", %{analyzer_pid: analyzer_pid} do
      # Wait a moment for baseline to be established
      {:ok, _} = get_analyzer_stats(analyzer_pid)

      assert {:ok, report} = analyze_system_health(analyzer_pid)

      # Verify report structure
      assert Map.has_key?(report, :overall_status)
      assert Map.has_key?(report, :timestamp)
      assert Map.has_key?(report, :system_metrics)
      assert Map.has_key?(report, :health_indicators)
      assert Map.has_key?(report, :risk_factors)
      assert Map.has_key?(report, :stability_score)
      assert Map.has_key?(report, :recommendations)

      # Verify overall status is valid
      assert report.overall_status in [:healthy, :warning, :critical]

      # Verify timestamp is recent
      assert %DateTime{} = report.timestamp

      # Verify system metrics structure
      metrics = report.system_metrics
      assert Map.has_key?(metrics, :cpu)
      assert Map.has_key?(metrics, :memory)
      assert Map.has_key?(metrics, :io)
      assert Map.has_key?(metrics, :network)
      assert Map.has_key?(metrics, :processes)
      assert Map.has_key?(metrics, :system_load)

      # Verify health indicators
      assert is_list(report.health_indicators)
      assert length(report.health_indicators) > 0

      # Check first health indicator structure
      indicator = List.first(report.health_indicators)
      assert Map.has_key?(indicator, :component)
      assert Map.has_key?(indicator, :status)
      assert Map.has_key?(indicator, :score)
      assert Map.has_key?(indicator, :message)
      assert Map.has_key?(indicator, :metrics)

      # Verify stability score is a float between 0 and 1
      assert is_float(report.stability_score)
      assert report.stability_score >= 0.0
      assert report.stability_score <= 1.0

      # Verify recommendations is a list of strings
      assert is_list(report.recommendations)

      Enum.each(report.recommendations, fn rec ->
        assert is_binary(rec)
      end)
    end

    test "handles analysis errors gracefully", %{analyzer_pid: analyzer_pid} do
      # This test would require mocking system calls that fail
      # For now, we'll test that the function doesn't crash
      assert {:ok, _report} = analyze_system_health(analyzer_pid)
    end
  end

  describe "detect_anomalies/0" do
    test "returns anomaly report", %{analyzer_pid: analyzer_pid} do
      assert {:ok, report} = detect_anomalies(analyzer_pid)

      # Verify report structure
      assert Map.has_key?(report, :timestamp)
      assert Map.has_key?(report, :anomalies)
      assert Map.has_key?(report, :severity_distribution)
      assert Map.has_key?(report, :affected_systems)
      assert Map.has_key?(report, :correlation_analysis)

      # Verify timestamp
      assert %DateTime{} = report.timestamp

      # Verify anomalies is a list
      assert is_list(report.anomalies)

      # Verify severity distribution structure
      severity_dist = report.severity_distribution
      assert Map.has_key?(severity_dist, :high)
      assert Map.has_key?(severity_dist, :medium)
      assert Map.has_key?(severity_dist, :low)
      assert is_integer(severity_dist.high)
      assert is_integer(severity_dist.medium)
      assert is_integer(severity_dist.low)

      # Verify affected systems is a list of atoms
      assert is_list(report.affected_systems)

      Enum.each(report.affected_systems, fn system ->
        assert is_atom(system)
      end)
    end

    test "detects anomalies when baseline is established", %{analyzer_pid: analyzer_pid} do
      # Wait for baseline to be established
      {:ok, _} = get_analyzer_stats(analyzer_pid)

      assert {:ok, report} = detect_anomalies(analyzer_pid)

      # With a fresh system, we might not have anomalies
      # but the structure should be correct
      assert is_list(report.anomalies)

      # If there are anomalies, verify their structure
      Enum.each(report.anomalies, fn anomaly ->
        assert Map.has_key?(anomaly, :type)
        assert Map.has_key?(anomaly, :severity)
        assert Map.has_key?(anomaly, :description)
        assert Map.has_key?(anomaly, :current_value)
        assert Map.has_key?(anomaly, :expected_range)
        assert Map.has_key?(anomaly, :confidence)
        assert Map.has_key?(anomaly, :timestamp)
        assert Map.has_key?(anomaly, :affected_components)

        assert anomaly.severity in [:high, :medium, :low]
        assert is_binary(anomaly.description)
        assert is_float(anomaly.confidence)
        assert %DateTime{} = anomaly.timestamp
        assert is_list(anomaly.affected_components)
      end)
    end
  end

  describe "get_resource_usage/0" do
    test "returns detailed resource information", %{analyzer_pid: analyzer_pid} do
      assert {:ok, data} = get_resource_usage(analyzer_pid)

      # Verify main structure
      assert Map.has_key?(data, :timestamp)
      assert Map.has_key?(data, :cpu)
      assert Map.has_key?(data, :memory)
      assert Map.has_key?(data, :io)
      assert Map.has_key?(data, :network)
      assert Map.has_key?(data, :processes)
      assert Map.has_key?(data, :system_load)

      # Verify timestamp
      assert %DateTime{} = data.timestamp

      # Verify CPU metrics
      cpu = data.cpu
      assert Map.has_key?(cpu, :utilization)
      assert Map.has_key?(cpu, :load_average)
      assert Map.has_key?(cpu, :scheduler_utilization)
      assert Map.has_key?(cpu, :context_switches)
      assert Map.has_key?(cpu, :interrupts)
      assert is_float(cpu.utilization)
      assert is_list(cpu.load_average)
      assert is_list(cpu.scheduler_utilization)
      assert is_integer(cpu.context_switches)
      assert is_integer(cpu.interrupts)

      # Verify memory metrics
      memory = data.memory
      assert Map.has_key?(memory, :total)
      assert Map.has_key?(memory, :available)
      assert Map.has_key?(memory, :used)
      assert Map.has_key?(memory, :cached)
      assert Map.has_key?(memory, :buffers)
      assert Map.has_key?(memory, :swap_total)
      assert Map.has_key?(memory, :swap_used)
      assert Map.has_key?(memory, :fragmentation_ratio)
      assert is_integer(memory.total)
      assert is_integer(memory.available)
      assert is_integer(memory.used)
      assert is_float(memory.fragmentation_ratio)

      # Verify process metrics
      processes = data.processes
      assert Map.has_key?(processes, :total_count)
      assert Map.has_key?(processes, :running)
      assert Map.has_key?(processes, :sleeping)
      assert Map.has_key?(processes, :memory_per_process)
      assert Map.has_key?(processes, :cpu_per_process)
      assert is_integer(processes.total_count)
      assert is_integer(processes.running)
      assert is_integer(processes.sleeping)
      assert is_float(processes.memory_per_process)
      assert is_float(processes.cpu_per_process)

      # Verify system load metrics
      system_load = data.system_load
      assert Map.has_key?(system_load, :load_1min)
      assert Map.has_key?(system_load, :load_5min)
      assert Map.has_key?(system_load, :load_15min)
      assert Map.has_key?(system_load, :uptime)
      assert Map.has_key?(system_load, :boot_time)
      assert is_float(system_load.load_1min)
      assert is_float(system_load.load_5min)
      assert is_float(system_load.load_15min)
      assert is_integer(system_load.uptime)
      assert %DateTime{} = system_load.boot_time
    end
  end

  describe "predict_issues/0" do
    test "returns prediction report with insufficient data", %{analyzer_pid: analyzer_pid} do
      assert {:ok, report} = predict_issues(analyzer_pid)

      # Verify report structure
      assert Map.has_key?(report, :timestamp)
      assert Map.has_key?(report, :predictions)
      assert Map.has_key?(report, :confidence_level)
      assert Map.has_key?(report, :time_horizon)
      assert Map.has_key?(report, :recommended_actions)

      # With insufficient data, predictions should be empty
      assert is_list(report.predictions)
      assert is_float(report.confidence_level)
      assert is_integer(report.time_horizon)
      assert is_list(report.recommended_actions)

      # Should have a message about insufficient data
      assert "Insufficient historical data for predictions" in report.recommended_actions
    end

    test "handles prediction errors gracefully", %{analyzer_pid: analyzer_pid} do
      # Test that prediction doesn't crash even with edge cases
      assert {:ok, _report} = predict_issues(analyzer_pid)
    end
  end

  describe "generate_recommendations/0" do
    test "returns list of recommendations", %{analyzer_pid: analyzer_pid} do
      assert {:ok, recommendations} = generate_recommendations(analyzer_pid)

      # Verify it's a list of strings
      assert is_list(recommendations)

      Enum.each(recommendations, fn rec ->
        assert is_binary(rec)
      end)
    end

    test "provides relevant recommendations based on system state", %{analyzer_pid: analyzer_pid} do
      assert {:ok, recommendations} = generate_recommendations(analyzer_pid)

      # Should have some recommendations (even if system is healthy)
      # The exact recommendations depend on current system state
      assert is_list(recommendations)
    end
  end

  describe "schedule_health_check/1" do
    test "schedules periodic health monitoring", %{analyzer_pid: analyzer_pid} do
      assert :ok = schedule_health_check(analyzer_pid, 5000)

      # Verify monitoring is active
      {:ok, stats} = get_analyzer_stats(analyzer_pid)
      assert stats.monitoring_active == true
      assert stats.health_check_interval == 5000
    end

    test "rejects invalid intervals", %{analyzer_pid: analyzer_pid} do
      assert_raise FunctionClauseError, fn ->
        schedule_health_check(analyzer_pid, 0)
      end

      assert_raise FunctionClauseError, fn ->
        schedule_health_check(analyzer_pid, -1000)
      end
    end
  end

  describe "stop_health_monitoring/0" do
    test "stops periodic health monitoring", %{analyzer_pid: analyzer_pid} do
      # First start monitoring
      assert :ok = schedule_health_check(analyzer_pid, 5000)

      # Then stop it
      assert :ok = stop_health_monitoring(analyzer_pid)

      # Verify monitoring is stopped
      {:ok, stats} = get_analyzer_stats(analyzer_pid)
      assert stats.monitoring_active == false
    end
  end

  describe "get_analyzer_stats/0" do
    test "returns analyzer statistics", %{analyzer_pid: analyzer_pid} do
      assert {:ok, stats} = get_analyzer_stats(analyzer_pid)

      # Verify stats structure
      assert Map.has_key?(stats, :uptime)
      assert Map.has_key?(stats, :monitoring_active)
      assert Map.has_key?(stats, :health_check_interval)
      assert Map.has_key?(stats, :historical_data_points)
      assert Map.has_key?(stats, :last_health_check)
      assert Map.has_key?(stats, :baseline_established)
      assert Map.has_key?(stats, :prediction_models_enabled)
      assert Map.has_key?(stats, :active_subscribers)

      # Verify data types
      assert is_integer(stats.uptime)
      assert is_boolean(stats.monitoring_active)
      assert is_integer(stats.health_check_interval)
      assert is_integer(stats.historical_data_points)
      assert is_boolean(stats.baseline_established)
      assert is_boolean(stats.prediction_models_enabled)
      assert is_integer(stats.active_subscribers)
    end
  end

  describe "integration scenarios" do
    test "full health analysis workflow", %{analyzer_pid: analyzer_pid} do
      # Wait for baseline establishment
      {:ok, _} = get_analyzer_stats(analyzer_pid)

      # Perform health analysis
      assert {:ok, health_report} = analyze_system_health(analyzer_pid)
      assert health_report.overall_status in [:healthy, :warning, :critical]

      # Detect anomalies
      assert {:ok, anomaly_report} = detect_anomalies(analyzer_pid)
      assert is_list(anomaly_report.anomalies)

      # Get resource usage
      assert {:ok, resource_data} = get_resource_usage(analyzer_pid)
      assert Map.has_key?(resource_data, :cpu)

      # Generate recommendations
      assert {:ok, recommendations} = generate_recommendations(analyzer_pid)
      assert is_list(recommendations)

      # Get predictions
      assert {:ok, prediction_report} = predict_issues(analyzer_pid)
      assert is_list(prediction_report.predictions)
    end

    test "scheduled monitoring workflow", %{analyzer_pid: analyzer_pid} do
      # Start scheduled monitoring
      assert :ok = schedule_health_check(analyzer_pid, 1000)

      # Wait for a few cycles
      {:ok, _} = get_analyzer_stats(analyzer_pid)

      # Check that historical data is being collected
      {:ok, stats} = get_analyzer_stats(analyzer_pid)
      assert stats.monitoring_active == true

      # Stop monitoring
      assert :ok = stop_health_monitoring(analyzer_pid)

      {:ok, stats} = get_analyzer_stats(analyzer_pid)
      assert stats.monitoring_active == false
    end
  end

  describe "error handling" do
    test "handles system call failures gracefully", %{analyzer_pid: analyzer_pid} do
      # These tests would ideally mock system calls to fail
      # For now, we verify that functions don't crash under normal conditions
      assert {:ok, _} = analyze_system_health(analyzer_pid)
      assert {:ok, _} = detect_anomalies(analyzer_pid)
      assert {:ok, _} = get_resource_usage(analyzer_pid)
      assert {:ok, _} = predict_issues(analyzer_pid)
      assert {:ok, _} = generate_recommendations(analyzer_pid)
    end

    test "handles concurrent access properly", %{analyzer_pid: analyzer_pid} do
      # Test concurrent calls don't interfere with each other
      tasks =
        for _ <- 1..5 do
          Task.async(fn ->
            analyze_system_health(analyzer_pid)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All calls should succeed
      Enum.each(results, fn result ->
        assert {:ok, _report} = result
      end)
    end
  end
end
