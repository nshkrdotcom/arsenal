defmodule Examples.PhoenixIntegration.Application do
  @moduledoc """
  Example Application module showing how to integrate Arsenal with Phoenix.
  
  This demonstrates the proper startup sequence and configuration
  for Arsenal in a Phoenix application.
  """
  
  use Application
  
  @impl true
  def start(_type, _args) do
    # Create ETS table for rate limiting
    :ets.new(:rate_limits, [:named_table, :public, :set])
    
    children = [
      # Start Arsenal first
      {Arsenal, []},
      
      # Start the in-memory user storage for examples
      {Examples.BasicOperations.UserManagement, []},
      
      # Phoenix endpoint
      Examples.PhoenixIntegration.Endpoint,
      
      # Add other supervisors here
      {Phoenix.PubSub, name: Examples.PhoenixIntegration.PubSub},
    ]
    
    opts = [strategy: :one_for_one, name: Examples.PhoenixIntegration.Supervisor]
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Register Arsenal operations after startup
        register_operations()
        {:ok, pid}
      
      error ->
        error
    end
  end
  
  @impl true
  def config_change(changed, _new, removed) do
    Examples.PhoenixIntegration.Endpoint.config_change(changed, removed)
    :ok
  end
  
  defp register_operations do
    # Register basic operations
    Arsenal.Registry.register(:factorial, Examples.BasicOperations.SimpleOperation)
    Arsenal.Registry.register(:create_user, Examples.BasicOperations.CreateUser)
    Arsenal.Registry.register(:get_user, Examples.BasicOperations.GetUser)
    Arsenal.Registry.register(:list_users, Examples.BasicOperations.ListUsers)
    
    # Register built-in Arsenal operations
    Arsenal.Registry.register(:list_processes, Arsenal.Operations.ListProcesses)
    Arsenal.Registry.register(:get_process_info, Arsenal.Operations.GetProcessInfo)
    Arsenal.Registry.register(:start_process, Arsenal.Operations.StartProcess)
    Arsenal.Registry.register(:kill_process, Arsenal.Operations.KillProcess)
    Arsenal.Registry.register(:restart_process, Arsenal.Operations.RestartProcess)
    Arsenal.Registry.register(:list_supervisors, Arsenal.Operations.ListSupervisors)
    Arsenal.Registry.register(:trace_process, Arsenal.Operations.TraceProcess)
    Arsenal.Registry.register(:send_message, Arsenal.Operations.SendMessage)
    
    # Register sandbox operations
    Arsenal.Registry.register(:create_sandbox, Arsenal.Operations.CreateSandbox)
    Arsenal.Registry.register(:list_sandboxes, Arsenal.Operations.ListSandboxes)
    Arsenal.Registry.register(:get_sandbox_info, Arsenal.Operations.GetSandboxInfo)
    Arsenal.Registry.register(:restart_sandbox, Arsenal.Operations.RestartSandbox)
    Arsenal.Registry.register(:destroy_sandbox, Arsenal.Operations.DestroySandbox)
    Arsenal.Registry.register(:hot_reload_sandbox, Arsenal.Operations.HotReloadSandbox)
    
    # Register distributed operations (if available)
    if Code.ensure_loaded?(Arsenal.Operations.Distributed.ClusterTopology) do
      Arsenal.Registry.register(:cluster_topology, Arsenal.Operations.Distributed.ClusterTopology)
      Arsenal.Registry.register(:cluster_health, Arsenal.Operations.Distributed.ClusterHealth)
      Arsenal.Registry.register(:node_info, Arsenal.Operations.Distributed.NodeInfo)
      Arsenal.Registry.register(:cluster_processes, Arsenal.Operations.Distributed.ProcessList)
      Arsenal.Registry.register(:cluster_supervision_trees, Arsenal.Operations.Distributed.ClusterSupervisionTrees)
    end
    
    # Log successful registration
    operations_count = Arsenal.list_operations() |> length()
    IO.puts("Arsenal: Registered #{operations_count} operations")
  end
end

defmodule Examples.PhoenixIntegration.Endpoint do
  @moduledoc """
  Example Phoenix Endpoint configuration for Arsenal.
  """
  
  use Phoenix.Endpoint, otp_app: :arsenal_example
  
  # Serve static files and assets
  plug Plug.Static,
    at: "/",
    from: :arsenal_example,
    gzip: false,
    only_matching: ["favicon", "robots"]
  
  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
  end
  
  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  
  # Add Arsenal-specific logging
  plug Examples.PhoenixIntegration.LoggingPlug
  
  plug Examples.PhoenixIntegration.Router
end

defmodule Examples.PhoenixIntegration.LoggingPlug do
  @moduledoc """
  Custom logging plug for Arsenal operations.
  """
  
  require Logger
  import Plug.Conn
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    start_time = :os.system_time(:microsecond)
    
    register_before_send(conn, fn conn ->
      duration = :os.system_time(:microsecond) - start_time
      duration_ms = duration / 1000
      
      Logger.info("Arsenal Request",
        method: conn.method,
        path: conn.request_path,
        status: conn.status,
        duration_ms: Float.round(duration_ms, 2),
        user_id: get_user_id(conn)
      )
      
      conn
    end)
  end
  
  defp get_user_id(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end
end