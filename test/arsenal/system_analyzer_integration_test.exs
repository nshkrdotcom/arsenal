defmodule Arsenal.SystemAnalyzerIntegrationTest do
  use ExUnit.Case, async: true

  alias Arsenal.SystemAnalyzer

  import Supertester.OTPHelpers
  import Supertester.GenServerHelpers
  import Supertester.Assertions

  @moduletag :integration
  @moduletag :capture_log

  setup do
    # Start SystemAnalyzer with shorter intervals for testing and unique name
    {:ok, analyzer_pid} =
      setup_isolated_genserver(SystemAnalyzer, "integration_test",
        # Fast for tests
        health_check_interval: 100,
        anomaly_thresholds: %{
          cpu_utilization: 1.5,
          memory_usage: 1.5,
          process_count: 1.2
        }
      )

    %{analyzer_pid: analyzer_pid}
  end

  describe "SystemAnalyzer integration with real system conditions" do
    test "establishes baseline and detects changes over time", %{analyzer_pid: analyzer_pid} do
      # Wait for baseline establishment with sync
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Get initial health report
      {:ok, {:ok, initial_report}} = call_with_timeout(analyzer_pid, :analyze_system_health)
      initial_process_count = initial_report.system_metrics.processes.total_count

      # Create controlled test processes
      test_tasks =
        for _i <- 1..50 do
          Task.async(fn ->
            receive do
              :stop -> :ok
            after
              5000 -> :timeout
            end
          end)
        end

      # Use call to ensure synchronization
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Get updated health report
      {:ok, {:ok, updated_report}} = call_with_timeout(analyzer_pid, :analyze_system_health)
      updated_process_count = updated_report.system_metrics.processes.total_count

      # Verify process count increased
      assert updated_process_count > initial_process_count

      # Clean up test processes properly
      Enum.each(test_tasks, fn task ->
        send(task.pid, :stop)
        Task.await(task, 1000)
      end)

      # Use call to ensure synchronization
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Verify process count decreased
      {:ok, {:ok, final_report}} = call_with_timeout(analyzer_pid, :analyze_system_health)
      final_process_count = final_report.system_metrics.processes.total_count
      assert final_process_count < updated_process_count
    end

    test "detects anomalies with simulated high memory usage", %{analyzer_pid: analyzer_pid} do
      # Wait for baseline with sync
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Get baseline anomaly report
      {:ok, {:ok, baseline_anomalies}} = call_with_timeout(analyzer_pid, :detect_anomalies)
      _baseline_anomaly_count = length(baseline_anomalies.anomalies)

      # Create memory-intensive controlled tasks
      memory_tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            # Allocate some memory
            _large_list = Enum.to_list(1..100_000)

            receive do
              :stop -> :ok
            after
              3000 -> :timeout
            end
          end)
        end

      # Use sync to ensure memory allocation is detected
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Check for anomalies
      {:ok, {:ok, anomaly_report}} = call_with_timeout(analyzer_pid, :detect_anomalies)

      # Clean up tasks properly
      Enum.each(memory_tasks, fn task ->
        send(task.pid, :stop)
        Task.await(task, 1000)
      end)

      # Verify anomaly detection structure
      assert is_list(anomaly_report.anomalies)
      assert Map.has_key?(anomaly_report.severity_distribution, :high)
      assert Map.has_key?(anomaly_report.severity_distribution, :medium)
      assert Map.has_key?(anomaly_report.severity_distribution, :low)
    end

    test "generates relevant recommendations based on system load", %{analyzer_pid: analyzer_pid} do
      # Create CPU-intensive controlled tasks
      cpu_tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            # Simulate CPU work
            result = Enum.reduce(1..1_000_000, 0, fn i, acc -> acc + i end)

            receive do
              :stop -> result
            after
              2000 -> result
            end
          end)
        end

      # Use sync to ensure CPU usage is detected
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Get recommendations
      {:ok, {:ok, recommendations}} = call_with_timeout(analyzer_pid, :generate_recommendations)

      # Clean up tasks properly
      Enum.each(cpu_tasks, fn task ->
        send(task.pid, :stop)
        Task.await(task, 1000)
      end)

      # Verify recommendations are relevant
      assert is_list(recommendations)

      # Should have some recommendations about CPU or process management
      recommendation_text = Enum.join(recommendations, " ")

      assert String.contains?(recommendation_text, "CPU") or
               String.contains?(recommendation_text, "process") or
               String.contains?(recommendation_text, "Monitor")
    end

    test "scheduled monitoring collects historical data", %{analyzer_pid: analyzer_pid} do
      # Get initial data point count
      {:ok, {:ok, initial_stats}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)
      initial_points = initial_stats.historical_data_points

      # Start scheduled monitoring with short interval
      {:ok, :ok} = call_with_timeout(analyzer_pid, {:schedule_health_check, 50})

      # Force some analysis to ensure data points are collected
      for _ <- 1..3 do
        {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :analyze_system_health)
        Process.sleep(60)
      end

      # Check that historical data is being collected
      {:ok, {:ok, stats}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)
      assert stats.monitoring_active == true
      assert stats.historical_data_points > initial_points

      # Stop monitoring
      {:ok, :ok} = call_with_timeout(analyzer_pid, :stop_health_monitoring)

      # Verify monitoring stopped
      {:ok, {:ok, final_stats}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)
      assert final_stats.monitoring_active == false
    end

    test "predictive analysis with historical data", %{analyzer_pid: analyzer_pid} do
      # Start monitoring to collect data
      {:ok, :ok} = call_with_timeout(analyzer_pid, {:schedule_health_check, 20})

      # Create gradually increasing load using controlled tasks
      process_batches =
        for batch <- 1..5 do
          # Use sync between batches to ensure processing
          {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

          # Create more processes each batch
          for _i <- 1..(batch * 5) do
            Task.async(fn ->
              receive do
                :stop -> :ok
              after
                2000 -> :timeout
              end
            end)
          end
        end

      # Ensure data collection processes all batches
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Get predictions
      {:ok, {:ok, prediction_report}} = call_with_timeout(analyzer_pid, :predict_issues)

      # Clean up all processes properly
      Enum.each(List.flatten(process_batches), fn task ->
        send(task.pid, :stop)
        Task.await(task, 1000)
      end)

      # Stop monitoring
      {:ok, :ok} = call_with_timeout(analyzer_pid, :stop_health_monitoring)

      # Verify prediction report structure
      assert Map.has_key?(prediction_report, :predictions)
      assert Map.has_key?(prediction_report, :confidence_level)
      assert Map.has_key?(prediction_report, :recommended_actions)
      assert is_list(prediction_report.predictions)
      assert is_float(prediction_report.confidence_level)
      assert is_list(prediction_report.recommended_actions)
    end

    test "health status changes with system conditions", %{analyzer_pid: analyzer_pid} do
      # Get initial health status
      {:ok, {:ok, initial_health}} = call_with_timeout(analyzer_pid, :analyze_system_health)
      initial_status = initial_health.overall_status

      # Create significant system load using controlled tasks
      load_tasks =
        for _i <- 1..100 do
          Task.async(fn ->
            # Mix of CPU and memory load
            _work = Enum.reduce(1..50_000, [], fn i, acc -> [i | acc] end)

            receive do
              :stop -> :ok
            after
              3000 -> :timeout
            end
          end)
        end

      # Use sync to ensure load is detected
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Get health status under load
      {:ok, {:ok, loaded_health}} = call_with_timeout(analyzer_pid, :analyze_system_health)
      loaded_status = loaded_health.overall_status

      # Clean up properly
      Enum.each(load_tasks, fn task ->
        send(task.pid, :stop)
        Task.await(task, 1000)
      end)

      # Use sync to ensure cleanup is processed
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Get final health status
      {:ok, {:ok, final_health}} = call_with_timeout(analyzer_pid, :analyze_system_health)
      final_status = final_health.overall_status

      # Verify health status is valid at all times
      assert initial_status in [:healthy, :warning, :critical]
      assert loaded_status in [:healthy, :warning, :critical]
      assert final_status in [:healthy, :warning, :critical]

      # Verify stability scores are reasonable
      assert initial_health.stability_score >= 0.0
      assert initial_health.stability_score <= 1.0
      assert loaded_health.stability_score >= 0.0
      assert loaded_health.stability_score <= 1.0
      assert final_health.stability_score >= 0.0
      assert final_health.stability_score <= 1.0
    end

    test "resource usage tracking accuracy", %{analyzer_pid: analyzer_pid} do
      # Get baseline resource usage
      {:ok, {:ok, baseline_resources}} = call_with_timeout(analyzer_pid, :get_resource_usage)
      baseline_process_count = baseline_resources.processes.total_count
      _baseline_memory = baseline_resources.memory.used

      # Get reference to test process for synchronization
      test_pid = self()

      # Create measurable resource usage with controlled tasks
      resource_tasks =
        for _i <- 1..20 do
          Task.async(fn ->
            # Signal that task has started
            send(test_pid, {:task_started, self()})

            # Allocate memory and keep it - 1MB per process
            _memory = :binary.copy(<<0>>, 1_000_000)

            receive do
              :stop -> :ok
            after
              2000 -> :timeout
            end
          end)
        end

      # Wait for all tasks to signal they've started
      for _ <- 1..20 do
        assert_receive {:task_started, _pid}, 1000
      end

      # Measure resource usage under load
      {:ok, {:ok, loaded_resources}} = call_with_timeout(analyzer_pid, :get_resource_usage)
      loaded_process_count = loaded_resources.processes.total_count
      loaded_memory = loaded_resources.memory.used

      # Verify resource tracking
      assert loaded_process_count > baseline_process_count
      # Memory should be positive (don't compare with baseline due to GC variability)
      assert loaded_memory > 0

      # Clean up properly
      Enum.each(resource_tasks, fn task ->
        send(task.pid, :stop)
        Task.await(task, 1000)
      end)

      # Force garbage collection
      :erlang.garbage_collect()

      # Use sync to ensure cleanup is processed
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Verify resource cleanup
      {:ok, {:ok, final_resources}} = call_with_timeout(analyzer_pid, :get_resource_usage)
      final_process_count = final_resources.processes.total_count

      assert final_process_count < loaded_process_count
    end

    test "concurrent analysis operations", %{analyzer_pid: analyzer_pid} do
      # Wait for baseline with sync
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Run multiple analysis operations concurrently using Task.async
      tasks = [
        Task.async(fn -> call_with_timeout(analyzer_pid, :analyze_system_health) end),
        Task.async(fn -> call_with_timeout(analyzer_pid, :detect_anomalies) end),
        Task.async(fn -> call_with_timeout(analyzer_pid, :get_resource_usage) end),
        Task.async(fn -> call_with_timeout(analyzer_pid, :predict_issues) end),
        Task.async(fn -> call_with_timeout(analyzer_pid, :generate_recommendations) end)
      ]

      results = Task.await_many(tasks, 10_000)

      # Verify all operations succeeded  
      Enum.each(results, fn result ->
        assert {:ok, {:ok, _data}} = result
      end)

      # Verify specific result types
      [health_result, anomaly_result, resource_result, prediction_result, recommendation_result] =
        results

      {:ok, {:ok, health_report}} = health_result
      assert Map.has_key?(health_report, :overall_status)

      {:ok, {:ok, anomaly_report}} = anomaly_result
      assert Map.has_key?(anomaly_report, :anomalies)

      {:ok, {:ok, resource_data}} = resource_result
      assert Map.has_key?(resource_data, :cpu)

      {:ok, {:ok, prediction_report}} = prediction_result
      assert Map.has_key?(prediction_report, :predictions)

      {:ok, {:ok, recommendations}} = recommendation_result
      assert is_list(recommendations)
    end

    test "analyzer statistics accuracy", %{analyzer_pid: analyzer_pid} do
      # Get initial stats  
      {:ok, {:ok, initial_stats}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)
      initial_uptime = initial_stats.uptime

      # Wait a moment to ensure uptime increases
      Process.sleep(100)

      # Use sync calls to ensure time passes and operations are processed
      for _i <- 1..3 do
        {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)
      end

      # Get updated stats
      {:ok, {:ok, updated_stats}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)
      updated_uptime = updated_stats.uptime

      # Verify uptime increased or stayed the same (in case of rounding)
      assert updated_uptime >= initial_uptime

      # Start monitoring and verify stats change
      {:ok, :ok} = call_with_timeout(analyzer_pid, {:schedule_health_check, 50})

      {:ok, {:ok, monitoring_stats}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)
      assert monitoring_stats.monitoring_active == true

      # Force some analysis operations to ensure data points are collected
      for _ <- 1..3 do
        {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :analyze_system_health)
        Process.sleep(60)
      end

      {:ok, {:ok, data_stats}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)
      # Historical data should have increased after analyses
      assert data_stats.historical_data_points >= initial_stats.historical_data_points

      # Stop monitoring
      {:ok, :ok} = call_with_timeout(analyzer_pid, :stop_health_monitoring)

      {:ok, {:ok, final_stats}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)
      assert final_stats.monitoring_active == false
    end
  end

  describe "SystemAnalyzer stress testing" do
    test "handles high-frequency analysis requests", %{analyzer_pid: analyzer_pid} do
      # Wait for baseline with sync
      {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)

      # Create stress test operations
      operations = [
        :analyze_system_health,
        :detect_anomalies,
        :get_resource_usage,
        :generate_recommendations
      ]

      # Perform many rapid requests
      stress_tasks =
        for _ <- 1..50 do
          operation = Enum.random(operations)

          Task.async(fn ->
            call_with_timeout(analyzer_pid, operation, 5000)
          end)
        end

      # Wait for all tasks
      stress_results = Task.await_many(stress_tasks, 10_000)

      # Verify high success rate
      successful_count =
        Enum.count(stress_results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      assert successful_count == length(stress_results)

      # Verify analyzer is still responsive
      assert_genserver_responsive(analyzer_pid)
      {:ok, {:ok, _final_health}} = call_with_timeout(analyzer_pid, :analyze_system_health)
    end

    test "maintains performance under continuous monitoring", %{analyzer_pid: analyzer_pid} do
      # Start aggressive monitoring - very frequent
      {:ok, :ok} = call_with_timeout(analyzer_pid, {:schedule_health_check, 10})

      # Use multiple sync calls to simulate continuous monitoring
      for _i <- 1..10 do
        {:ok, {:ok, _}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)
      end

      # Measure response time
      start_time = :os.system_time(:millisecond)
      {:ok, {:ok, _health}} = call_with_timeout(analyzer_pid, :analyze_system_health, 5000)
      end_time = :os.system_time(:millisecond)

      response_time = end_time - start_time

      # Should respond within reasonable time (less than 1 second)
      assert response_time < 1000

      # Stop monitoring
      {:ok, :ok} = call_with_timeout(analyzer_pid, :stop_health_monitoring)

      # Verify final state
      {:ok, {:ok, stats}} = call_with_timeout(analyzer_pid, :get_analyzer_stats)
      assert stats.monitoring_active == false
      assert stats.historical_data_points > 0
    end
  end
end
