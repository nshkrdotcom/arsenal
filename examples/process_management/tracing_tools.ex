defmodule Examples.ProcessManagement.TracingTools do
  @moduledoc """
  Advanced process tracing and debugging tools.
  
  This module demonstrates:
  - Safe process tracing with automatic cleanup
  - Message flow analysis
  - Performance profiling
  - Call stack analysis
  - Distributed tracing across nodes
  """
  
  use GenServer
  require Logger
  
  defmodule TraceSession do
    @moduledoc "Structure for active trace sessions"
    
    defstruct [
      :id,
      :pid,
      :flags,
      :start_time,
      :duration_seconds,
      :message_count,
      :events,
      :filters,
      :status
    ]
  end
  
  @doc """
  Start the tracing tools manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Start tracing a process with specified flags.
  """
  def start_trace(pid, opts \\ []) do
    GenServer.call(__MODULE__, {:start_trace, pid, opts})
  end
  
  @doc """
  Stop tracing a process.
  """
  def stop_trace(trace_id) do
    GenServer.call(__MODULE__, {:stop_trace, trace_id})
  end
  
  @doc """
  Get active trace sessions.
  """
  def list_traces do
    GenServer.call(__MODULE__, :list_traces)
  end
  
  @doc """
  Get trace results for a session.
  """
  def get_trace_results(trace_id) do
    GenServer.call(__MODULE__, {:get_trace_results, trace_id})
  end
  
  @doc """
  Analyze message flow between processes.
  """
  def analyze_message_flow(pids, duration_seconds \\ 10) do
    GenServer.call(__MODULE__, {:analyze_message_flow, pids, duration_seconds}, 
                   (duration_seconds + 5) * 1000)
  end
  
  @doc """
  Profile a process for performance analysis.
  """
  def profile_process(pid, duration_seconds \\ 30) do
    GenServer.call(__MODULE__, {:profile_process, pid, duration_seconds},
                   (duration_seconds + 5) * 1000)
  end
  
  @doc """
  Trace function calls in a process.
  """
  def trace_calls(pid, module_pattern \\ '_', function_pattern \\ '_') do
    GenServer.call(__MODULE__, {:trace_calls, pid, module_pattern, function_pattern})
  end
  
  @doc """
  Stop all active traces (emergency cleanup).
  """
  def stop_all_traces do
    GenServer.call(__MODULE__, :stop_all_traces)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    # Set up trace message handling
    :erlang.trace_pattern({:_, :_, :_}, false, [:local])
    
    # Schedule cleanup of expired traces
    schedule_cleanup()
    
    state = %{
      active_traces: %{},
      trace_events: %{},
      next_trace_id: 1
    }
    
    Logger.info("TracingTools started")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:start_trace, pid, opts}, _from, state) do
    case validate_trace_request(pid, opts) do
      :ok ->
        trace_id = state.next_trace_id
        flags = Keyword.get(opts, :flags, [:send, :receive, :call, :return])
        duration = Keyword.get(opts, :duration_seconds, 60)
        filters = Keyword.get(opts, :filters, [])
        
        # Start erlang tracing
        case start_erlang_trace(pid, flags) do
          :ok ->
            trace_session = %TraceSession{
              id: trace_id,
              pid: pid,
              flags: flags,
              start_time: DateTime.utc_now(),
              duration_seconds: duration,
              message_count: 0,
              events: [],
              filters: filters,
              status: :active
            }
            
            active_traces = Map.put(state.active_traces, trace_id, trace_session)
            trace_events = Map.put(state.trace_events, trace_id, [])
            
            # Schedule automatic cleanup
            schedule_trace_cleanup(trace_id, duration)
            
            Logger.info("Started trace session", 
              trace_id: trace_id, 
              pid: pid, 
              flags: flags
            )
            
            {:reply, {:ok, trace_id}, %{state | 
              active_traces: active_traces,
              trace_events: trace_events,
              next_trace_id: trace_id + 1
            }}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:stop_trace, trace_id}, _from, state) do
    case Map.get(state.active_traces, trace_id) do
      nil ->
        {:reply, {:error, :trace_not_found}, state}
      
      trace_session ->
        # Stop erlang tracing
        stop_erlang_trace(trace_session.pid)
        
        # Mark as completed
        completed_session = %{trace_session | status: :completed}
        active_traces = Map.put(state.active_traces, trace_id, completed_session)
        
        Logger.info("Stopped trace session", trace_id: trace_id)
        
        {:reply, :ok, %{state | active_traces: active_traces}}
    end
  end
  
  @impl true
  def handle_call(:list_traces, _from, state) do
    traces = Enum.map(state.active_traces, fn {id, session} ->
      %{
        id: id,
        pid: inspect(session.pid),
        flags: session.flags,
        start_time: DateTime.to_iso8601(session.start_time),
        duration_seconds: session.duration_seconds,
        message_count: session.message_count,
        status: session.status
      }
    end)
    
    {:reply, traces, state}
  end
  
  @impl true
  def handle_call({:get_trace_results, trace_id}, _from, state) do
    case {Map.get(state.active_traces, trace_id), Map.get(state.trace_events, trace_id)} do
      {nil, _} ->
        {:reply, {:error, :trace_not_found}, state}
      
      {trace_session, events} ->
        results = %{
          session: trace_session,
          events: events || [],
          summary: generate_trace_summary(events || [], trace_session)
        }
        
        {:reply, {:ok, results}, state}
    end
  end
  
  @impl true
  def handle_call({:analyze_message_flow, pids, duration_seconds}, _from, state) do
    # Start message flow analysis
    analysis_id = start_message_flow_analysis(pids, duration_seconds)
    
    # Wait for analysis to complete
    receive do
      {:message_flow_complete, ^analysis_id, results} ->
        {:reply, {:ok, results}, state}
    after
      (duration_seconds + 2) * 1000 ->
        {:reply, {:error, :analysis_timeout}, state}
    end
  end
  
  @impl true
  def handle_call({:profile_process, pid, duration_seconds}, _from, state) do
    case start_process_profiling(pid, duration_seconds) do
      {:ok, profile_results} ->
        {:reply, {:ok, profile_results}, state}
      
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:trace_calls, pid, module_pattern, function_pattern}, _from, state) do
    case start_call_tracing(pid, module_pattern, function_pattern) do
      {:ok, trace_id} ->
        # This would be managed similar to regular traces
        {:reply, {:ok, trace_id}, state}
      
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call(:stop_all_traces, _from, state) do
    # Emergency cleanup - stop all active traces
    Enum.each(state.active_traces, fn {_id, session} ->
      if session.status == :active do
        stop_erlang_trace(session.pid)
      end
    end)
    
    # Clear all tracing patterns
    :erlang.trace_pattern({:_, :_, :_}, false, [:local])
    :erlang.trace(:all, false, [:all])
    
    Logger.warning("Emergency stop of all traces")
    
    {:reply, :ok, %{state | active_traces: %{}, trace_events: %{}}}
  end
  
  @impl true
  def handle_info({:trace, pid, type, data}, state) do
    # Handle trace messages from Erlang
    new_state = process_trace_message(pid, type, data, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:trace_cleanup, trace_id}, state) do
    case Map.get(state.active_traces, trace_id) do
      nil ->
        {:noreply, state}
      
      trace_session ->
        if trace_session.status == :active do
          stop_erlang_trace(trace_session.pid)
          
          completed_session = %{trace_session | status: :expired}
          active_traces = Map.put(state.active_traces, trace_id, completed_session)
          
          Logger.info("Trace session expired", trace_id: trace_id)
          
          {:noreply, %{state | active_traces: active_traces}}
        else
          {:noreply, state}
        end
    end
  end
  
  @impl true
  def handle_info(:cleanup_old_traces, state) do
    # Clean up old completed traces
    cutoff_time = DateTime.add(DateTime.utc_now(), -3600, :second)  # 1 hour ago
    
    {active_traces, trace_events} = cleanup_old_traces(
      state.active_traces, 
      state.trace_events, 
      cutoff_time
    )
    
    schedule_cleanup()
    
    {:noreply, %{state | active_traces: active_traces, trace_events: trace_events}}
  end
  
  # Private functions
  
  defp validate_trace_request(pid, opts) do
    cond do
      not is_pid(pid) ->
        {:error, :invalid_pid}
      
      not Process.alive?(pid) ->
        {:error, :process_not_alive}
      
      Keyword.get(opts, :duration_seconds, 60) > 300 ->
        {:error, :duration_too_long}
      
      true ->
        :ok
    end
  end
  
  defp start_erlang_trace(pid, flags) do
    try do
      case :erlang.trace(pid, true, flags ++ [:timestamp]) do
        1 -> :ok
        0 -> {:error, :trace_failed}
        error -> {:error, error}
      end
    rescue
      error -> {:error, error}
    end
  end
  
  defp stop_erlang_trace(pid) do
    try do
      :erlang.trace(pid, false, [:all])
      :ok
    rescue
      _ -> :ok  # Ignore errors during cleanup
    end
  end
  
  defp process_trace_message(pid, type, data, state) do
    # Find which trace session this message belongs to
    matching_trace = Enum.find(state.active_traces, fn {_id, session} ->
      session.pid == pid && session.status == :active
    end)
    
    case matching_trace do
      nil ->
        state  # No active trace for this process
      
      {trace_id, trace_session} ->
        # Apply filters
        if should_include_event?(type, data, trace_session.filters) do
          event = format_trace_event(type, data)
          
          # Add event to trace
          events = Map.get(state.trace_events, trace_id, [])
          updated_events = [event | events]
          
          # Update session message count
          updated_session = %{trace_session | message_count: trace_session.message_count + 1}
          
          # Update state
          active_traces = Map.put(state.active_traces, trace_id, updated_session)
          trace_events = Map.put(state.trace_events, trace_id, updated_events)
          
          %{state | active_traces: active_traces, trace_events: trace_events}
        else
          state
        end
    end
  end
  
  defp should_include_event?(type, data, filters) do
    if length(filters) == 0 do
      true
    else
      Enum.any?(filters, fn filter ->
        apply_filter(filter, type, data)
      end)
    end
  end
  
  defp apply_filter({:type, filter_type}, type, _data) do
    type == filter_type
  end
  
  defp apply_filter({:module, module_name}, :call, {module, _function, _args}) do
    module == module_name
  end
  
  defp apply_filter({:function, function_name}, :call, {_module, function, _args}) do
    function == function_name
  end
  
  defp apply_filter(_filter, _type, _data) do
    true
  end
  
  defp format_trace_event(type, data) do
    %{
      type: type,
      data: data,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp generate_trace_summary(events, trace_session) do
    event_counts = Enum.group_by(events, & &1.type)
                   |> Enum.map(fn {type, events} -> {type, length(events)} end)
                   |> Enum.into(%{})
    
    %{
      total_events: length(events),
      event_counts: event_counts,
      duration_seconds: DateTime.diff(DateTime.utc_now(), trace_session.start_time, :second),
      events_per_second: length(events) / max(1, DateTime.diff(DateTime.utc_now(), trace_session.start_time, :second))
    }
  end
  
  defp start_message_flow_analysis(pids, duration_seconds) do
    analysis_id = make_ref()
    
    # Start a task to analyze message flow
    Task.start(fn ->
      # Set up tracing for all specified processes
      Enum.each(pids, fn pid ->
        :erlang.trace(pid, true, [:send, :receive, :timestamp])
      end)
      
      # Collect messages for the specified duration
      messages = collect_messages_for_duration(duration_seconds)
      
      # Stop tracing
      Enum.each(pids, fn pid ->
        :erlang.trace(pid, false, [:all])
      end)
      
      # Analyze the collected messages
      analysis_results = analyze_message_patterns(messages, pids)
      
      # Send results back
      send(self(), {:message_flow_complete, analysis_id, analysis_results})
    end)
    
    analysis_id
  end
  
  defp collect_messages_for_duration(duration_seconds) do
    end_time = :erlang.monotonic_time(:millisecond) + (duration_seconds * 1000)
    collect_messages_until(end_time, [])
  end
  
  defp collect_messages_until(end_time, messages) do
    current_time = :erlang.monotonic_time(:millisecond)
    
    if current_time >= end_time do
      messages
    else
      receive do
        {:trace, _pid, _type, _data} = trace_msg ->
          collect_messages_until(end_time, [trace_msg | messages])
      after
        100 ->
          collect_messages_until(end_time, messages)
      end
    end
  end
  
  defp analyze_message_patterns(messages, _pids) do
    # Analyze the collected trace messages
    send_events = Enum.filter(messages, fn 
      {:trace, _pid, :send, _msg, _to} -> true
      _ -> false
    end)
    
    receive_events = Enum.filter(messages, fn
      {:trace, _pid, :receive, _msg} -> true
      _ -> false
    end)
    
    %{
      total_messages: length(messages),
      send_events: length(send_events),
      receive_events: length(receive_events),
      message_flow: build_message_flow_graph(send_events, receive_events),
      analysis_timestamp: DateTime.utc_now()
    }
  end
  
  defp build_message_flow_graph(send_events, receive_events) do
    # Build a graph showing message flow between processes
    # This is a simplified version - a full implementation would
    # correlate send/receive events and build a proper graph
    
    senders = Enum.map(send_events, fn {:trace, pid, :send, _msg, to} ->
      %{from: pid, to: to}
    end)
    
    %{
      connections: senders,
      send_count: length(send_events),
      receive_count: length(receive_events)
    }
  end
  
  defp start_process_profiling(pid, duration_seconds) do
    # Use Arsenal's TraceProcess operation for profiling
    case Arsenal.Operations.TraceProcess.execute(%{
      pid: pid,
      flags: [:call, :return, :timestamp],
      duration: duration_seconds * 1000
    }) do
      {:ok, trace_result} ->
        # Analyze the trace result for performance insights
        profile_data = analyze_performance_trace(trace_result)
        {:ok, profile_data}
      
      error ->
        error
    end
  end
  
  defp analyze_performance_trace(trace_result) do
    # Analyze trace data for performance metrics
    %{
      function_calls: length(trace_result.events),
      hot_functions: identify_hot_functions(trace_result.events),
      call_tree: build_call_tree(trace_result.events),
      execution_summary: summarize_execution(trace_result.events)
    }
  end
  
  defp identify_hot_functions(events) do
    # Identify frequently called functions
    events
    |> Enum.filter(&match?(%{type: :call}, &1))
    |> Enum.group_by(fn event -> {event.module, event.function} end)
    |> Enum.map(fn {mf, calls} -> {mf, length(calls)} end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(10)
  end
  
  defp build_call_tree(events) do
    # Build a call tree from trace events
    # This is a simplified version
    %{
      total_calls: length(events),
      depth_analysis: "Call tree analysis would go here"
    }
  end
  
  defp summarize_execution(events) do
    %{
      total_events: length(events),
      call_events: Enum.count(events, &match?(%{type: :call}, &1)),
      return_events: Enum.count(events, &match?(%{type: :return}, &1))
    }
  end
  
  defp start_call_tracing(pid, module_pattern, function_pattern) do
    # Set up call tracing for specific module/function patterns
    try do
      :erlang.trace_pattern({module_pattern, function_pattern, :_}, true, [:local])
      :erlang.trace(pid, true, [:call, :return, :timestamp])
      
      trace_id = :erlang.unique_integer([:positive])
      {:ok, trace_id}
    rescue
      error ->
        {:error, error}
    end
  end
  
  defp cleanup_old_traces(active_traces, trace_events, cutoff_time) do
    # Remove traces older than cutoff time
    {keep_traces, remove_traces} = Enum.split_with(active_traces, fn {_id, session} ->
      DateTime.compare(session.start_time, cutoff_time) == :gt
    end)
    
    remove_ids = Enum.map(remove_traces, &elem(&1, 0))
    
    filtered_active = Enum.into(keep_traces, %{})
    filtered_events = Map.drop(trace_events, remove_ids)
    
    if length(remove_ids) > 0 do
      Logger.info("Cleaned up old traces", removed_count: length(remove_ids))
    end
    
    {filtered_active, filtered_events}
  end
  
  defp schedule_trace_cleanup(trace_id, duration_seconds) do
    Process.send_after(self(), {:trace_cleanup, trace_id}, duration_seconds * 1000)
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_old_traces, 300_000)  # Every 5 minutes
  end
end