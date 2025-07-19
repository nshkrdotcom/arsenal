defmodule Arsenal.MessageTracer do
  @moduledoc """
  Advanced OTP message tracing system for real-time message flow analysis.

  This module provides comprehensive message tracing capabilities with minimal performance impact,
  advanced filtering, pattern analysis, and multiple export formats. It's designed to integrate
  seamlessly with Arsenal's debugging operations while providing production-ready tracing.

  ## Features

  - Real-time message tracing with configurable options
  - Advanced filtering by process, message type, and content
  - Message pattern analysis and anomaly detection
  - Multiple export formats (JSON, CSV, binary)
  - Minimal performance impact with efficient data structures
  - Integration with existing Arsenal debug operations

  ## Usage

      # Start tracing a process
      {:ok, trace_id} = Arsenal.MessageTracer.start_trace(pid, %{
        flags: [:send, :receive],
        max_events: 1000,
        duration_ms: 30_000,
        filters: %{message_types: [:call, :cast]}
      })

      # Get trace data
      {:ok, trace_data} = Arsenal.MessageTracer.get_trace_data(trace_id)

      # Analyze patterns
      {:ok, analysis} = Arsenal.MessageTracer.analyze_message_patterns(trace_data)

      # Export trace
      {:ok, exported} = Arsenal.MessageTracer.export_trace(trace_id, :json)

      # Stop tracing
      :ok = Arsenal.MessageTracer.stop_trace(trace_id)
  """

  use GenServer
  require Logger

  @type trace_id :: String.t()
  @type trace_options :: %{
          optional(:flags) => [atom()],
          optional(:max_events) => pos_integer(),
          optional(:duration_ms) => pos_integer(),
          optional(:filters) => map(),
          optional(:buffer_size) => pos_integer(),
          optional(:sampling_rate) => float()
        }
  @type trace_data :: %{
          trace_id: trace_id(),
          pid: pid(),
          events: [trace_event()],
          metadata: map()
        }
  @type trace_event :: %{
          timestamp: integer(),
          type: atom(),
          from: pid() | atom(),
          to: pid() | atom(),
          message: term(),
          metadata: map()
        }
  @type filter_options :: %{
          optional(:message_types) => [atom()],
          optional(:processes) => [pid()],
          optional(:time_range) => {integer(), integer()},
          optional(:message_patterns) => [term()],
          optional(:size_limit) => pos_integer()
        }
  @type export_format :: :json | :csv | :binary | :erlang_term

  # Client API

  @doc """
  Start the MessageTracer server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start tracing a process with configurable options.

  ## Parameters
  - `pid`: Process to trace
  - `options`: Trace configuration options

  ## Options
  - `:flags` - List of trace flags (default: [:send, :receive])
  - `:max_events` - Maximum events to collect (default: 1000)
  - `:duration_ms` - Trace duration in milliseconds (default: 60000)
  - `:filters` - Filtering options (default: %{})
  - `:buffer_size` - Internal buffer size (default: 10000)
  - `:sampling_rate` - Sampling rate 0.0-1.0 (default: 1.0)

  ## Returns
  - `{:ok, trace_id}` if tracing started successfully
  - `{:error, reason}` if tracing failed
  """
  @spec start_trace(pid(), trace_options()) :: {:ok, trace_id()} | {:error, term()}
  def start_trace(pid, options \\ %{}) do
    GenServer.call(__MODULE__, {:start_trace, pid, options})
  end

  @doc """
  Stop tracing for a specific trace session.

  ## Parameters
  - `trace_id`: The trace session identifier

  ## Returns
  - `:ok` if tracing stopped successfully
  - `{:error, reason}` if stopping failed
  """
  @spec stop_trace(trace_id()) :: :ok | {:error, term()}
  def stop_trace(trace_id) do
    GenServer.call(__MODULE__, {:stop_trace, trace_id})
  end

  @doc """
  Get trace data for a specific trace session.

  ## Parameters
  - `trace_id`: The trace session identifier

  ## Returns
  - `{:ok, trace_data}` if trace data retrieved successfully
  - `{:error, reason}` if retrieval failed
  """
  @spec get_trace_data(trace_id()) :: {:ok, trace_data()} | {:error, term()}
  def get_trace_data(trace_id) do
    GenServer.call(__MODULE__, {:get_trace_data, trace_id})
  end

  @doc """
  Filter messages from trace data based on specified criteria.

  ## Parameters
  - `trace_data`: The trace data to filter
  - `filter_options`: Filtering criteria

  ## Filter Options
  - `:message_types` - List of message types to include
  - `:processes` - List of processes to include
  - `:time_range` - Tuple of {start_time, end_time}
  - `:message_patterns` - List of message patterns to match
  - `:size_limit` - Maximum number of events to return

  ## Returns
  - `{:ok, filtered_data}` if filtering succeeded
  - `{:error, reason}` if filtering failed
  """
  @spec filter_messages(trace_data(), filter_options()) :: {:ok, trace_data()} | {:error, term()}
  def filter_messages(trace_data, filter_options) do
    GenServer.call(__MODULE__, {:filter_messages, trace_data, filter_options})
  end

  @doc """
  Analyze message patterns in trace data for anomaly detection.

  ## Parameters
  - `trace_data`: The trace data to analyze

  ## Returns
  - `{:ok, analysis}` containing pattern analysis results
  - `{:error, reason}` if analysis failed
  """
  @spec analyze_message_patterns(trace_data()) :: {:ok, map()} | {:error, term()}
  def analyze_message_patterns(trace_data) do
    GenServer.call(__MODULE__, {:analyze_message_patterns, trace_data})
  end

  @doc """
  Export trace data in the specified format.

  ## Parameters
  - `trace_id`: The trace session identifier
  - `format`: Export format (:json, :csv, :binary, :erlang_term)

  ## Returns
  - `{:ok, exported_data}` if export succeeded
  - `{:error, reason}` if export failed
  """
  @spec export_trace(trace_id(), export_format()) :: {:ok, binary() | term()} | {:error, term()}
  def export_trace(trace_id, format) do
    GenServer.call(__MODULE__, {:export_trace, trace_id, format})
  end

  @doc """
  List all active trace sessions.

  ## Returns
  - `{:ok, [trace_info]}` list of active trace sessions
  """
  @spec list_active_traces() :: {:ok, [map()]}
  def list_active_traces do
    GenServer.call(__MODULE__, :list_active_traces)
  end

  @doc """
  Get statistics about the message tracer.

  ## Returns
  - `{:ok, stats}` containing tracer statistics
  """
  @spec get_tracer_stats() :: {:ok, map()}
  def get_tracer_stats do
    GenServer.call(__MODULE__, :get_tracer_stats)
  end

  # GenServer Implementation

  def init(_opts) do
    # Create ETS table for storing trace sessions
    traces_table =
      :ets.new(:message_traces, [
        :named_table,
        :public,
        :set,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

    # Create ETS table for storing trace events
    events_table =
      :ets.new(:trace_events, [
        :named_table,
        :public,
        :bag,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

    # Schedule periodic cleanup
    :timer.send_interval(30_000, self(), :cleanup_expired_traces)

    state = %{
      traces_table: traces_table,
      events_table: events_table,
      active_traces: %{},
      stats: %{
        traces_started: 0,
        traces_completed: 0,
        events_collected: 0,
        errors: 0
      }
    }

    {:ok, state}
  end

  def handle_call({:start_trace, pid, options}, _from, state) do
    case validate_trace_options(options) do
      {:ok, validated_options} ->
        case start_trace_internal(pid, validated_options, state) do
          {:ok, trace_id, new_state} ->
            {:reply, {:ok, trace_id}, new_state}

          {:error, reason} ->
            new_stats = update_stats(state.stats, :errors, 1)
            {:reply, {:error, reason}, %{state | stats: new_stats}}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:stop_trace, trace_id}, _from, state) do
    case stop_trace_internal(trace_id, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_trace_data, trace_id}, _from, state) do
    case get_trace_data_internal(trace_id, state) do
      {:ok, trace_data} ->
        {:reply, {:ok, trace_data}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:filter_messages, trace_data, filter_options}, _from, state) do
    case filter_messages_internal(trace_data, filter_options) do
      {:ok, filtered_data} ->
        {:reply, {:ok, filtered_data}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:analyze_message_patterns, trace_data}, _from, state) do
    case analyze_patterns_internal(trace_data) do
      {:ok, analysis} ->
        {:reply, {:ok, analysis}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:export_trace, trace_id, format}, _from, state) do
    case export_trace_internal(trace_id, format, state) do
      {:ok, exported_data} ->
        {:reply, {:ok, exported_data}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:list_active_traces, _from, state) do
    traces = :ets.tab2list(state.traces_table)

    trace_info =
      Enum.map(traces, fn {trace_id, info} ->
        Map.put(info, :trace_id, trace_id)
      end)

    {:reply, {:ok, trace_info}, state}
  end

  def handle_call(:get_tracer_stats, _from, state) do
    enhanced_stats =
      Map.merge(state.stats, %{
        active_traces: map_size(state.active_traces),
        total_events_stored: :ets.info(state.events_table, :size)
      })

    {:reply, {:ok, enhanced_stats}, state}
  end

  def handle_info(:cleanup_expired_traces, state) do
    new_state = cleanup_expired_traces_internal(state)
    {:noreply, new_state}
  end

  def handle_info({:trace_timeout, trace_id}, state) do
    case stop_trace_internal(trace_id, state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Internal Implementation Functions

  defp validate_trace_options(options) do
    defaults = %{
      flags: [:send, :receive],
      max_events: 1000,
      duration_ms: 60_000,
      filters: %{},
      buffer_size: 10_000,
      sampling_rate: 1.0
    }

    validated = Map.merge(defaults, options)

    with :ok <- validate_flags(validated.flags),
         :ok <- validate_max_events(validated.max_events),
         :ok <- validate_duration(validated.duration_ms),
         :ok <- validate_sampling_rate(validated.sampling_rate) do
      {:ok, validated}
    end
  end

  defp validate_flags(flags) when is_list(flags) do
    valid_flags = [:send, :receive, :call, :procs, :garbage_collection, :running, :set_on_spawn]

    case Enum.all?(flags, &(&1 in valid_flags)) do
      true -> :ok
      false -> {:error, {:invalid_flags, flags}}
    end
  end

  defp validate_flags(_), do: {:error, {:invalid_flags, "must be list"}}

  defp validate_max_events(max) when is_integer(max) and max > 0 and max <= 100_000, do: :ok
  defp validate_max_events(_), do: {:error, {:invalid_max_events, "must be 1-100000"}}

  defp validate_duration(duration)
       when is_integer(duration) and duration > 0 and duration <= 600_000,
       do: :ok

  defp validate_duration(_), do: {:error, {:invalid_duration, "must be 1-600000 ms"}}

  defp validate_sampling_rate(rate) when is_float(rate) and rate > 0.0 and rate <= 1.0, do: :ok
  defp validate_sampling_rate(_), do: {:error, {:invalid_sampling_rate, "must be 0.0-1.0"}}

  defp start_trace_internal(pid, options, state) do
    if Process.alive?(pid) do
      trace_id = generate_trace_id()

      # Start trace collector
      case start_trace_collector(trace_id, options, state) do
        {:ok, collector_pid} ->
          # Enable tracing
          case enable_tracing(pid, options.flags, collector_pid) do
            :ok ->
              # Store trace info
              trace_info = %{
                pid: pid,
                collector: collector_pid,
                options: options,
                start_time: System.monotonic_time(:millisecond),
                status: :active
              }

              :ets.insert(state.traces_table, {trace_id, trace_info})

              # Schedule automatic stop
              Process.send_after(self(), {:trace_timeout, trace_id}, options.duration_ms)

              new_active_traces = Map.put(state.active_traces, trace_id, collector_pid)
              new_stats = update_stats(state.stats, :traces_started, 1)

              new_state = %{state | active_traces: new_active_traces, stats: new_stats}
              {:ok, trace_id, new_state}

            {:error, reason} ->
              GenServer.stop(collector_pid)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :process_not_alive}
    end
  end

  defp stop_trace_internal(trace_id, state) do
    case :ets.lookup(state.traces_table, trace_id) do
      [{^trace_id, trace_info}] ->
        # Disable tracing
        :erlang.trace(trace_info.pid, false, [:all])

        # Stop collector
        if Map.has_key?(state.active_traces, trace_id) do
          collector_pid = state.active_traces[trace_id]
          GenServer.stop(collector_pid, :normal)
        end

        # Update trace info
        updated_info = %{
          trace_info
          | status: :stopped,
            end_time: System.monotonic_time(:millisecond)
        }

        :ets.insert(state.traces_table, {trace_id, updated_info})

        # Update state
        new_active_traces = Map.delete(state.active_traces, trace_id)
        new_stats = update_stats(state.stats, :traces_completed, 1)

        new_state = %{state | active_traces: new_active_traces, stats: new_stats}
        {:ok, new_state}

      [] ->
        {:error, :trace_not_found}
    end
  end

  defp get_trace_data_internal(trace_id, state) do
    case :ets.lookup(state.traces_table, trace_id) do
      [{^trace_id, trace_info}] ->
        events = :ets.lookup(state.events_table, trace_id)
        event_data = Enum.map(events, fn {_trace_id, event} -> event end)

        trace_data = %{
          trace_id: trace_id,
          pid: trace_info.pid,
          events: Enum.sort_by(event_data, & &1.timestamp),
          metadata: %{
            start_time: trace_info.start_time,
            end_time: Map.get(trace_info, :end_time),
            status: trace_info.status,
            options: trace_info.options,
            event_count: length(event_data)
          }
        }

        {:ok, trace_data}

      [] ->
        {:error, :trace_not_found}
    end
  end

  defp filter_messages_internal(trace_data, filter_options) do
    try do
      filtered_events =
        trace_data.events
        |> filter_by_message_types(Map.get(filter_options, :message_types))
        |> filter_by_processes(Map.get(filter_options, :processes))
        |> filter_by_time_range(Map.get(filter_options, :time_range))
        |> filter_by_patterns(Map.get(filter_options, :message_patterns))
        |> limit_size(Map.get(filter_options, :size_limit))

      filtered_data = %{trace_data | events: filtered_events}
      {:ok, filtered_data}
    rescue
      error -> {:error, {:filter_error, error}}
    end
  end

  defp analyze_patterns_internal(trace_data) do
    try do
      events = trace_data.events

      analysis = %{
        total_events: length(events),
        message_types: analyze_message_types(events),
        communication_patterns: analyze_communication_patterns(events),
        timing_analysis: analyze_timing_patterns(events),
        anomalies: detect_anomalies(events),
        recommendations: generate_recommendations(events)
      }

      {:ok, analysis}
    rescue
      error -> {:error, {:analysis_error, error}}
    end
  end

  defp export_trace_internal(trace_id, format, state) do
    case get_trace_data_internal(trace_id, state) do
      {:ok, trace_data} ->
        case format do
          :json -> export_as_json(trace_data)
          :csv -> export_as_csv(trace_data)
          :binary -> export_as_binary(trace_data)
          :erlang_term -> export_as_erlang_term(trace_data)
          _ -> {:error, {:unsupported_format, format}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper Functions

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp start_trace_collector(trace_id, options, state) do
    collector_opts = %{
      trace_id: trace_id,
      max_events: options.max_events,
      filters: options.filters,
      sampling_rate: options.sampling_rate,
      events_table: state.events_table
    }

    case GenServer.start_link(__MODULE__.TraceCollector, collector_opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, {:collector_start_failed, reason}}
    end
  end

  defp enable_tracing(pid, flags, collector_pid) do
    try do
      case :erlang.trace(pid, true, [:timestamp | flags] ++ [{:tracer, collector_pid}]) do
        1 -> :ok
        0 -> {:error, :trace_setup_failed}
      end
    rescue
      error -> {:error, {:trace_enable_failed, error}}
    end
  end

  defp update_stats(stats, key, increment) do
    Map.update(stats, key, increment, &(&1 + increment))
  end

  defp cleanup_expired_traces_internal(state) do
    current_time = System.monotonic_time(:millisecond)

    expired_traces =
      :ets.tab2list(state.traces_table)
      |> Enum.filter(fn {_trace_id, trace_info} ->
        is_trace_expired?(trace_info, current_time)
      end)

    Enum.each(expired_traces, fn {trace_id, _trace_info} ->
      stop_trace_internal(trace_id, state)
      :ets.delete(state.traces_table, trace_id)
      :ets.delete(state.events_table, trace_id)
    end)

    state
  end

  defp is_trace_expired?(trace_info, current_time) do
    case trace_info.status do
      :active ->
        duration = trace_info.options.duration_ms
        current_time - trace_info.start_time > duration

      :stopped ->
        # Keep stopped traces for 5 minutes
        end_time = Map.get(trace_info, :end_time, trace_info.start_time)
        current_time - end_time > 300_000

      _ ->
        false
    end
  end

  # Filtering Functions

  defp filter_by_message_types(events, nil), do: events

  defp filter_by_message_types(events, types) when is_list(types) do
    Enum.filter(events, fn event -> event.type in types end)
  end

  defp filter_by_processes(events, nil), do: events

  defp filter_by_processes(events, processes) when is_list(processes) do
    Enum.filter(events, fn event ->
      event.from in processes or event.to in processes
    end)
  end

  defp filter_by_time_range(events, nil), do: events

  defp filter_by_time_range(events, {start_time, end_time}) do
    Enum.filter(events, fn event ->
      event.timestamp >= start_time and event.timestamp <= end_time
    end)
  end

  defp filter_by_patterns(events, nil), do: events

  defp filter_by_patterns(events, patterns) when is_list(patterns) do
    Enum.filter(events, fn event ->
      Enum.any?(patterns, fn pattern ->
        match_pattern?(event.message, pattern)
      end)
    end)
  end

  defp limit_size(events, nil), do: events

  defp limit_size(events, size_limit) when is_integer(size_limit) do
    Enum.take(events, size_limit)
  end

  defp match_pattern?(message, pattern) do
    try do
      case pattern do
        {:match, _pattern_expr} ->
          # Pattern matching with variables is complex, defaulting to false for now
          # TODO: Implement proper pattern matching
          false

        {:contains, term} ->
          contains_term?(message, term)

        {:regex, regex} ->
          Regex.match?(regex, inspect(message))

        _ ->
          false
      end
    rescue
      _ -> false
    end
  end

  defp contains_term?(message, term) do
    inspect(message) |> String.contains?(inspect(term))
  end

  # Analysis Functions

  defp analyze_message_types(events) do
    events
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, type_events} ->
      {type,
       %{count: length(type_events), percentage: length(type_events) / length(events) * 100}}
    end)
    |> Enum.into(%{})
  end

  defp analyze_communication_patterns(events) do
    patterns =
      events
      |> Enum.group_by(fn event -> {event.from, event.to} end)
      |> Enum.map(fn {{from, to}, pattern_events} ->
        %{
          from: from,
          to: to,
          count: length(pattern_events),
          message_types: Enum.map(pattern_events, & &1.type) |> Enum.uniq()
        }
      end)
      |> Enum.sort_by(& &1.count, :desc)

    %{
      total_patterns: length(patterns),
      top_patterns: Enum.take(patterns, 10),
      unique_processes: get_unique_processes(events)
    }
  end

  defp analyze_timing_patterns(events) do
    if length(events) < 2 do
      %{intervals: [], average_interval: 0, pattern_detected: false}
    else
      intervals =
        events
        |> Enum.sort_by(& &1.timestamp)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [event1, event2] -> event2.timestamp - event1.timestamp end)

      average = if length(intervals) > 0, do: Enum.sum(intervals) / length(intervals), else: 0

      %{
        intervals: intervals,
        average_interval: average,
        pattern_detected: detect_timing_pattern(intervals)
      }
    end
  end

  defp detect_anomalies(events) do
    anomalies = []

    # Detect message bursts
    burst_anomalies = detect_message_bursts(events)

    # Detect unusual message types
    type_anomalies = detect_unusual_message_types(events)

    # Detect communication anomalies
    comm_anomalies = detect_communication_anomalies(events)

    anomalies ++ burst_anomalies ++ type_anomalies ++ comm_anomalies
  end

  defp generate_recommendations(events) do
    recommendations = []

    # Performance recommendations
    perf_recs = generate_performance_recommendations(events)

    # Pattern recommendations
    pattern_recs = generate_pattern_recommendations(events)

    recommendations ++ perf_recs ++ pattern_recs
  end

  defp get_unique_processes(events) do
    events
    |> Enum.flat_map(fn event -> [event.from, event.to] end)
    |> Enum.uniq()
    |> length()
  end

  defp detect_timing_pattern(intervals) do
    # Simple pattern detection - could be more sophisticated
    if length(intervals) > 5 do
      variance = calculate_variance(intervals)
      # Low variance indicates regular pattern
      variance < 1000
    else
      false
    end
  end

  defp calculate_variance(numbers) do
    mean = Enum.sum(numbers) / length(numbers)
    variance_sum = Enum.reduce(numbers, 0, fn x, acc -> acc + :math.pow(x - mean, 2) end)
    variance_sum / length(numbers)
  end

  defp detect_message_bursts(events) do
    # Detect periods of high message activity
    # 1 second windows
    time_windows = group_events_by_time_window(events, 1000)

    burst_threshold = calculate_burst_threshold(time_windows)

    Enum.filter(time_windows, fn {_window, window_events} ->
      length(window_events) > burst_threshold
    end)
    |> Enum.map(fn {window, window_events} ->
      %{
        type: :message_burst,
        window: window,
        event_count: length(window_events),
        severity: :medium
      }
    end)
  end

  defp detect_unusual_message_types(_events) do
    # Placeholder for message type anomaly detection
    []
  end

  defp detect_communication_anomalies(_events) do
    # Placeholder for communication anomaly detection
    []
  end

  defp generate_performance_recommendations(events) do
    base_recommendations = []

    # Check for excessive message passing
    recommendations =
      if length(events) > 10000 do
        [
          %{
            type: :performance,
            message:
              "High message volume detected. Consider batching messages or reducing frequency.",
            severity: :medium
          }
          | base_recommendations
        ]
      else
        base_recommendations
      end

    recommendations
  end

  defp generate_pattern_recommendations(_events) do
    # Placeholder for pattern-based recommendations
    []
  end

  defp group_events_by_time_window(events, window_size_ms) do
    events
    |> Enum.group_by(fn event ->
      div(event.timestamp, window_size_ms) * window_size_ms
    end)
    |> Enum.to_list()
  end

  defp calculate_burst_threshold(time_windows) do
    if length(time_windows) > 0 do
      counts = Enum.map(time_windows, fn {_window, events} -> length(events) end)
      average = Enum.sum(counts) / length(counts)
      # 3x average as threshold
      round(average * 3)
    else
      # Default threshold
      100
    end
  end

  # Export Functions

  defp export_as_json(trace_data) do
    try do
      json_data = Jason.encode!(trace_data)
      {:ok, json_data}
    rescue
      error -> {:error, {:json_export_failed, error}}
    end
  end

  defp export_as_csv(trace_data) do
    try do
      headers = "timestamp,type,from,to,message\n"

      rows =
        Enum.map(trace_data.events, fn event ->
          [
            Integer.to_string(event.timestamp),
            Atom.to_string(event.type),
            inspect(event.from),
            inspect(event.to),
            inspect(event.message)
          ]
          |> Enum.join(",")
        end)
        |> Enum.join("\n")

      csv_data = headers <> rows
      {:ok, csv_data}
    rescue
      error -> {:error, {:csv_export_failed, error}}
    end
  end

  defp export_as_binary(trace_data) do
    try do
      binary_data = :erlang.term_to_binary(trace_data)
      {:ok, binary_data}
    rescue
      error -> {:error, {:binary_export_failed, error}}
    end
  end

  defp export_as_erlang_term(trace_data) do
    {:ok, trace_data}
  end
end

defmodule Arsenal.MessageTracer.TraceCollector do
  @moduledoc """
  GenServer that collects and processes trace events for a specific trace session.

  This collector is responsible for:
  - Receiving trace events from the Erlang trace system
  - Applying filters and sampling
  - Storing events efficiently
  - Managing memory usage and event limits
  """

  use GenServer
  require Logger

  def init(opts) do
    state = %{
      trace_id: opts.trace_id,
      max_events: opts.max_events,
      filters: opts.filters,
      sampling_rate: opts.sampling_rate,
      events_table: opts.events_table,
      event_count: 0,
      start_time: System.monotonic_time(:millisecond),
      last_sample_decision: true
    }

    {:ok, state}
  end

  # Handle trace events from Erlang trace system
  def handle_info({:trace_ts, pid, event_type, data, timestamp}, state) do
    handle_trace_event(pid, event_type, data, timestamp, state)
  end

  def handle_info({:trace_ts, pid, event_type, data1, data2, timestamp}, state) do
    # Handle trace events with two data elements (e.g., send events)
    combined_data = {data1, data2}
    handle_trace_event(pid, event_type, combined_data, timestamp, state)
  end

  def handle_info({:trace_ts, pid, event_type, data1, data2, data3, timestamp}, state) do
    # Handle trace events with three data elements
    combined_data = {data1, data2, data3}
    handle_trace_event(pid, event_type, combined_data, timestamp, state)
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      trace_id: state.trace_id,
      event_count: state.event_count,
      max_events: state.max_events,
      uptime_ms: System.monotonic_time(:millisecond) - state.start_time,
      sampling_rate: state.sampling_rate
    }

    {:reply, stats, state}
  end

  def handle_call(:get_events, _from, state) do
    events = :ets.lookup(state.events_table, state.trace_id)
    event_data = Enum.map(events, fn {_trace_id, event} -> event end)
    {:reply, event_data, state}
  end

  defp handle_trace_event(pid, event_type, data, timestamp, state) do
    # Check if we should collect this event
    if should_collect_event?(event_type, data, state) and should_sample?(state) do
      case create_trace_event(pid, event_type, data, timestamp) do
        {:ok, trace_event} ->
          # Store the event
          :ets.insert(state.events_table, {state.trace_id, trace_event})

          new_count = state.event_count + 1

          # Check if we've reached the maximum events
          if new_count >= state.max_events do
            Logger.info("Trace #{state.trace_id} reached maximum events (#{state.max_events})")
            {:stop, :normal, state}
          else
            {:noreply, %{state | event_count: new_count}}
          end

        {:error, reason} ->
          Logger.warning("Failed to create trace event: #{inspect(reason)}")
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp should_collect_event?(event_type, _data, state) do
    filters = state.filters

    # Apply message type filters
    case Map.get(filters, :message_types) do
      nil -> true
      types when is_list(types) -> event_type in types
      _ -> true
    end
  end

  defp should_sample?(state) do
    if state.sampling_rate >= 1.0 do
      true
    else
      # Simple sampling based on random number
      :rand.uniform() <= state.sampling_rate
    end
  end

  defp create_trace_event(pid, event_type, data, timestamp) do
    try do
      {from, to, message} = extract_message_info(pid, event_type, data)

      trace_event = %{
        timestamp: timestamp,
        type: event_type,
        from: from,
        to: to,
        message: sanitize_message(message),
        metadata: %{
          message_size: calculate_message_size(message),
          event_type: event_type
        }
      }

      {:ok, trace_event}
    rescue
      error -> {:error, {:event_creation_failed, error}}
    end
  end

  defp extract_message_info(pid, event_type, data) do
    case event_type do
      :send ->
        # data is {message, to_pid}
        case data do
          {message, to_pid} -> {pid, to_pid, message}
          message -> {pid, :unknown, message}
        end

      :receive ->
        # data is the received message
        {pid, pid, data}

      :call ->
        # data is {module, function, args}
        case data do
          {m, f, a} -> {pid, pid, {:call, m, f, a}}
          other -> {pid, pid, {:call, other}}
        end

      :return_from ->
        # data is {module, function, arity}
        case data do
          {m, f, a} -> {pid, pid, {:return_from, m, f, a}}
          other -> {pid, pid, {:return_from, other}}
        end

      :return_to ->
        # data is {module, function, arity}
        case data do
          {m, f, a} -> {pid, pid, {:return_to, m, f, a}}
          other -> {pid, pid, {:return_to, other}}
        end

      :spawn ->
        # data is {spawned_pid, {module, function, args}}
        case data do
          {spawned_pid, mfa} -> {pid, spawned_pid, {:spawn, mfa}}
          other -> {pid, :unknown, {:spawn, other}}
        end

      :exit ->
        # data is the exit reason
        {pid, pid, {:exit, data}}

      :link ->
        # data is the linked pid
        {pid, data, :link}

      :unlink ->
        # data is the unlinked pid
        {pid, data, :unlink}

      :getting_linked ->
        # data is the pid that's linking to this process
        {data, pid, :getting_linked}

      :getting_unlinked ->
        # data is the pid that's unlinking from this process
        {data, pid, :getting_unlinked}

      :register ->
        # data is the registered name
        {pid, pid, {:register, data}}

      :unregister ->
        # data is the unregistered name
        {pid, pid, {:unregister, data}}

      :in ->
        # data is {module, function, arity}
        case data do
          {m, f, a} -> {pid, pid, {:in, m, f, a}}
          other -> {pid, pid, {:in, other}}
        end

      :out ->
        # data is {module, function, arity}
        case data do
          {m, f, a} -> {pid, pid, {:out, m, f, a}}
          other -> {pid, pid, {:out, other}}
        end

      :gc_start ->
        {pid, pid, {:gc_start, data}}

      :gc_end ->
        {pid, pid, {:gc_end, data}}

      _ ->
        # Generic handling for other event types
        {pid, pid, {event_type, data}}
    end
  end

  defp sanitize_message(message) do
    # Check if message contains types that shouldn't be stored
    if should_sanitize_message?(message) do
      %{
        __unserialized_message__: true,
        type: get_message_type(message),
        summary: safe_inspect(message, 100)
      }
    else
      try do
        # Limit message size to prevent memory issues
        case :erlang.external_size(message) do
          size when size > 10_000 ->
            # Replace large messages with a summary
            %{
              __large_message__: true,
              size: size,
              type: get_message_type(message),
              summary: get_message_summary(message)
            }

          _ ->
            message
        end
      rescue
        _ ->
          # If we can't serialize the message, create a safe representation
          %{
            __unserialized_message__: true,
            type: get_message_type(message),
            summary: safe_inspect(message, 100)
          }
      end
    end
  end

  defp should_sanitize_message?(message) when is_function(message), do: true
  defp should_sanitize_message?(message) when is_pid(message), do: true
  defp should_sanitize_message?(message) when is_port(message), do: true
  defp should_sanitize_message?(message) when is_reference(message), do: true
  defp should_sanitize_message?(_message), do: false

  defp calculate_message_size(message) do
    try do
      :erlang.external_size(message)
    rescue
      _ -> 0
    end
  end

  defp get_message_type(message) do
    cond do
      is_atom(message) -> :atom
      is_binary(message) -> :binary
      is_list(message) -> :list
      is_tuple(message) -> :tuple
      is_map(message) -> :map
      is_pid(message) -> :pid
      is_reference(message) -> :reference
      is_function(message) -> :function
      is_number(message) -> :number
      true -> :unknown
    end
  end

  defp get_message_summary(message) do
    case message do
      msg when is_atom(msg) -> msg
      msg when is_binary(msg) -> binary_summary(msg)
      msg when is_list(msg) -> list_summary(msg)
      msg when is_tuple(msg) -> tuple_summary(msg)
      msg when is_map(msg) -> map_summary(msg)
      _ -> safe_inspect(message, 50)
    end
  end

  defp binary_summary(bin) when byte_size(bin) > 100 do
    <<prefix::binary-size(50), _::binary>> = bin
    "#{prefix}... (#{byte_size(bin)} bytes)"
  end

  defp binary_summary(bin), do: bin

  defp list_summary(list) when length(list) > 10 do
    preview = Enum.take(list, 5)
    "#{inspect(preview)}... (#{length(list)} items)"
  end

  defp list_summary(list), do: list

  defp tuple_summary(tuple) when tuple_size(tuple) > 10 do
    preview = tuple |> Tuple.to_list() |> Enum.take(5) |> List.to_tuple()
    "#{inspect(preview)}... (#{tuple_size(tuple)} elements)"
  end

  defp tuple_summary(tuple), do: tuple

  defp map_summary(map) when map_size(map) > 10 do
    preview = map |> Enum.take(5) |> Enum.into(%{})
    "#{inspect(preview)}... (#{map_size(map)} keys)"
  end

  defp map_summary(map), do: map

  defp safe_inspect(term, limit) do
    try do
      inspect(term, limit: limit, printable_limit: limit)
    rescue
      _ -> "#<uninspectable>"
    end
  end
end
