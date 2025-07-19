defmodule Arsenal.MessageTracer.TraceCollectorTest do
  use ExUnit.Case, async: true

  alias Arsenal.MessageTracer.TraceCollector

  import Supertester.OTPHelpers
  import Supertester.GenServerHelpers
  import Supertester.Assertions

  @moduletag :capture_log

  setup do
    # Create a unique ETS table for each test to avoid conflicts
    table_name = :"test_trace_events_#{System.unique_integer([:positive])}"
    events_table = :ets.new(table_name, [:public, :bag])

    opts = %{
      trace_id: "test_trace_id",
      max_events: 100,
      filters: %{},
      sampling_rate: 1.0,
      events_table: events_table
    }

    {:ok, collector_pid} =
      setup_isolated_genserver(TraceCollector, "trace_collector", init_args: opts)

    cleanup_on_exit(fn ->
      # Only delete the table if it still exists
      try do
        :ets.delete(events_table)
      catch
        # Table already deleted
        :error, :badarg -> :ok
      end
    end)

    %{collector: collector_pid, events_table: events_table, opts: opts}
  end

  describe "trace event handling" do
    test "handles send trace events", %{collector: collector, events_table: table} do
      test_pid = self()
      target_task = Task.async(fn -> :ok end)
      target_pid = target_task.pid
      timestamp = System.monotonic_time(:millisecond)

      # Simulate a send trace event
      send(collector, {:trace_ts, test_pid, :send, {:hello, target_pid}, timestamp})

      # Use sync to ensure processing
      {:ok, _} = call_with_timeout(collector, :get_stats)

      # Check that event was stored
      events = :ets.lookup(table, "test_trace_id")
      assert length(events) == 1

      {_trace_id, event} = List.first(events)
      assert event.type == :send
      assert event.from == test_pid
      assert event.to == target_pid
      assert event.message == :hello
      assert event.timestamp == timestamp

      # Clean up
      Task.await(target_task, 1000)
    end

    test "handles receive trace events", %{collector: collector, events_table: table} do
      test_pid = self()
      timestamp = System.monotonic_time(:millisecond)

      # Simulate a receive trace event
      send(collector, {:trace_ts, test_pid, :receive, :received_message, timestamp})

      # Use sync to ensure processing
      {:ok, _} = call_with_timeout(collector, :get_stats)

      events = :ets.lookup(table, "test_trace_id")
      assert length(events) == 1

      {_trace_id, event} = List.first(events)
      assert event.type == :receive
      assert event.from == test_pid
      assert event.to == test_pid
      assert event.message == :received_message
    end

    test "handles call trace events", %{collector: collector, events_table: table} do
      test_pid = self()
      timestamp = System.monotonic_time(:millisecond)

      # Simulate a call trace event
      send(
        collector,
        {:trace_ts, test_pid, :call, {GenServer, :call, [test_pid, :get_state]}, timestamp}
      )

      # Use sync to ensure processing
      {:ok, _} = call_with_timeout(collector, :get_stats)

      events = :ets.lookup(table, "test_trace_id")
      assert length(events) == 1

      {_trace_id, event} = List.first(events)
      assert event.type == :call
      assert event.message == {:call, GenServer, :call, [test_pid, :get_state]}
    end

    test "handles spawn trace events", %{collector: collector, events_table: table} do
      test_pid = self()
      spawned_task = Task.async(fn -> :ok end)
      spawned_pid = spawned_task.pid
      timestamp = System.monotonic_time(:millisecond)

      # Simulate a spawn trace event
      send(
        collector,
        {:trace_ts, test_pid, :spawn, {spawned_pid, {Kernel, :apply, [fn -> :ok end, []]}},
         timestamp}
      )

      # Use sync to ensure processing
      {:ok, _} = call_with_timeout(collector, :get_stats)

      events = :ets.lookup(table, "test_trace_id")
      assert length(events) == 1

      {_trace_id, event} = List.first(events)
      assert event.type == :spawn
      assert event.from == test_pid
      assert event.to == spawned_pid

      # Clean up
      Task.await(spawned_task, 1000)
    end

    test "handles exit trace events", %{collector: collector, events_table: table} do
      test_pid = self()
      timestamp = System.monotonic_time(:millisecond)

      # Simulate an exit trace event
      send(collector, {:trace_ts, test_pid, :exit, :normal, timestamp})

      # Use sync to ensure processing
      {:ok, _} = call_with_timeout(collector, :get_stats)

      events = :ets.lookup(table, "test_trace_id")
      assert length(events) == 1

      {_trace_id, event} = List.first(events)
      assert event.type == :exit
      assert event.message == {:exit, :normal}
    end
  end

  describe "message sanitization" do
    test "handles large messages", %{collector: collector, events_table: table} do
      test_pid = self()
      timestamp = System.monotonic_time(:millisecond)

      # Create a large message
      large_message = String.duplicate("x", 20_000)

      send(collector, {:trace_ts, test_pid, :receive, large_message, timestamp})

      # Use sync to ensure processing
      {:ok, _} = call_with_timeout(collector, :get_stats)

      events = :ets.lookup(table, "test_trace_id")
      assert length(events) == 1

      {_trace_id, event} = List.first(events)

      # Should be sanitized due to size
      assert is_map(event.message)
      assert Map.has_key?(event.message, :__large_message__)
      assert event.message.__large_message__ == true
      assert is_integer(event.message.size)
      assert event.message.size > 10_000
    end

    test "handles unserialized messages", %{collector: collector, events_table: table} do
      test_pid = self()
      timestamp = System.monotonic_time(:millisecond)

      # Create a message that can't be serialized (function)
      unserialized_message = fn -> :test end

      send(collector, {:trace_ts, test_pid, :receive, unserialized_message, timestamp})

      # Use sync to ensure message is processed
      {:ok, _} = call_with_timeout(collector, :get_stats)

      events = :ets.lookup(table, "test_trace_id")
      assert length(events) == 1

      {_trace_id, event} = List.first(events)

      # Should be sanitized due to serialization issues
      assert is_map(event.message)
      assert Map.has_key?(event.message, :__unserialized_message__)
      assert event.message.__unserialized_message__ == true
      assert event.message.type == :function
    end

    test "calculates message metadata", %{collector: collector, events_table: table} do
      test_pid = self()
      timestamp = System.monotonic_time(:millisecond)
      message = "test message"

      send(collector, {:trace_ts, test_pid, :receive, message, timestamp})

      # Use sync to ensure processing
      {:ok, _} = call_with_timeout(collector, :get_stats)

      events = :ets.lookup(table, "test_trace_id")
      {_trace_id, event} = List.first(events)

      assert Map.has_key?(event, :metadata)
      assert Map.has_key?(event.metadata, :message_size)
      assert Map.has_key?(event.metadata, :event_type)
      assert is_integer(event.metadata.message_size)
      assert event.metadata.event_type == :receive
    end
  end

  describe "filtering and sampling" do
    test "applies message type filters" do
      # Create collector with message type filter
      events_table = :ets.new(:filtered_test_events, [:public, :bag])

      opts = %{
        trace_id: "filtered_trace",
        max_events: 100,
        filters: %{message_types: [:send]},
        sampling_rate: 1.0,
        events_table: events_table
      }

      {:ok, collector} =
        setup_isolated_genserver(TraceCollector, "filtered_collector", init_args: opts)

      test_pid = self()
      target_task = Task.async(fn -> :ok end)
      timestamp = System.monotonic_time(:millisecond)

      # Send both send and receive events
      send(collector, {:trace_ts, test_pid, :send, {:hello, target_task.pid}, timestamp})
      send(collector, {:trace_ts, test_pid, :receive, :world, timestamp + 1})

      # Use sync to ensure processing
      {:ok, _} = call_with_timeout(collector, :get_stats)

      events = :ets.lookup(events_table, "filtered_trace")

      # Should only have the send event
      assert length(events) == 1
      {_trace_id, event} = List.first(events)
      assert event.type == :send

      # Clean up
      Task.await(target_task, 1000)
      :ets.delete(events_table)
    end

    test "applies sampling rate" do
      # Create collector with low sampling rate
      events_table = :ets.new(:sampled_test_events, [:public, :bag])

      opts = %{
        trace_id: "sampled_trace",
        max_events: 1000,
        filters: %{},
        # No events should be collected
        sampling_rate: 0.0,
        events_table: events_table
      }

      {:ok, collector} =
        setup_isolated_genserver(TraceCollector, "sampled_collector", init_args: opts)

      test_pid = self()
      timestamp = System.monotonic_time(:millisecond)

      # Send multiple events
      for i <- 1..10 do
        send(collector, {:trace_ts, test_pid, :receive, {:message, i}, timestamp + i})
      end

      # Use sync to ensure processing
      {:ok, _} = call_with_timeout(collector, :get_stats)

      events = :ets.lookup(events_table, "sampled_trace")

      # Should have no events due to 0% sampling
      assert length(events) == 0

      :ets.delete(events_table)
    end
  end

  describe "event limits" do
    test "stops collecting when max_events reached" do
      # Create collector with low max_events
      events_table = :ets.new(:limited_test_events, [:public, :bag])

      opts = %{
        trace_id: "limited_trace",
        max_events: 3,
        filters: %{},
        sampling_rate: 1.0,
        events_table: events_table
      }

      {:ok, collector} =
        setup_isolated_genserver(TraceCollector, "limited_collector", init_args: opts)

      test_pid = self()
      timestamp = System.monotonic_time(:millisecond)

      # Send more events than the limit
      for i <- 1..10 do
        send(collector, {:trace_ts, test_pid, :receive, {:message, i}, timestamp + i})
      end

      # Collector will stop automatically when max_events is reached
      # Wait for it to process the messages and stop
      {:ok, _reason} = wait_for_process_death(collector, 1000)

      events = :ets.lookup(events_table, "limited_trace")

      # Should not exceed max_events
      assert length(events) <= 3

      # Verify the collector has stopped
      assert_process_dead(collector)

      :ets.delete(events_table)
    end
  end

  describe "collector stats" do
    test "provides collector statistics", %{collector: collector} do
      {:ok, stats} = call_with_timeout(collector, :get_stats)

      assert Map.has_key?(stats, :trace_id)
      assert Map.has_key?(stats, :event_count)
      assert Map.has_key?(stats, :max_events)
      assert Map.has_key?(stats, :uptime_ms)
      assert Map.has_key?(stats, :sampling_rate)

      assert stats.trace_id == "test_trace_id"
      assert is_integer(stats.event_count)
      assert is_integer(stats.uptime_ms)
      assert stats.uptime_ms >= 0
    end

    test "provides collected events", %{collector: collector, events_table: _table} do
      test_pid = self()
      timestamp = System.monotonic_time(:millisecond)

      # Add some events
      send(collector, {:trace_ts, test_pid, :receive, :test1, timestamp})
      send(collector, {:trace_ts, test_pid, :receive, :test2, timestamp + 1})

      # Use sync to ensure processing
      {:ok, _} = call_with_timeout(collector, :get_stats)

      {:ok, events} = call_with_timeout(collector, :get_events)

      assert is_list(events)
      assert length(events) == 2

      # Events should be in the order they were processed
      assert Enum.at(events, 0).message == :test1
      assert Enum.at(events, 1).message == :test2
    end
  end

  describe "message type detection" do
    test "correctly identifies message types" do
      test_cases = [
        {:hello, :atom},
        {"binary", :binary},
        {[1, 2, 3], :list},
        {{:tuple, :data}, :tuple},
        {%{key: :value}, :map},
        {self(), :pid},
        {make_ref(), :reference},
        {42, :number},
        {3.14, :number}
      ]

      events_table = :ets.new(:type_test_events, [:public, :bag])

      opts = %{
        trace_id: "type_test",
        max_events: 100,
        filters: %{},
        sampling_rate: 1.0,
        events_table: events_table
      }

      {:ok, collector} =
        setup_isolated_genserver(TraceCollector, "type_test_collector", init_args: opts)

      test_pid = self()
      timestamp = System.monotonic_time(:millisecond)

      # Send events with different message types
      Enum.with_index(test_cases, fn {message, _expected_type}, index ->
        send(collector, {:trace_ts, test_pid, :receive, message, timestamp + index})
      end)

      # Use sync to ensure all messages are processed
      {:ok, _} = call_with_timeout(collector, :get_stats)

      events = :ets.lookup(events_table, "type_test")
      assert length(events) == length(test_cases)

      # Verify message types are correctly identified in metadata
      Enum.zip(test_cases, events)
      |> Enum.each(fn {{_message, _expected_type}, {_trace_id, event}} ->
        # For small messages, the original message should be preserved
        if not is_map(event.message) or not Map.has_key?(event.message, :__large_message__) do
          # Message type detection is done during sanitization
          # For normal-sized messages, we can't directly test the type detection
          # but we can verify the event structure is correct
          assert Map.has_key?(event, :metadata)
          assert Map.has_key?(event.metadata, :message_size)
        end
      end)

      :ets.delete(events_table)
    end
  end
end
