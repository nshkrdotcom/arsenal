defmodule Examples.PhoenixIntegration.ArsenalController do
  @moduledoc """
  Phoenix controller for Arsenal operations.
  
  This controller demonstrates how to integrate Arsenal with Phoenix
  by routing all Arsenal operations through a single controller endpoint.
  """
  
  use Phoenix.Controller
  
  alias Examples.PhoenixIntegration.ArsenalAdapter
  
  @doc """
  Main handler for all Arsenal operations.
  
  This action uses the Arsenal adapter to process requests and handles
  all operation routing automatically based on the request method and path.
  """
  def handle(conn, _params) do
    # Add request start time for performance tracking
    conn = Plug.Conn.assign(conn, :start_time, :os.system_time(:millisecond))
    
    # Process the request through Arsenal
    Arsenal.Adapter.process_request(ArsenalAdapter, conn)
  end
  
  @doc """
  Handle OPTIONS requests for CORS preflight.
  """
  def options(conn, _params) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, authorization, x-api-key, x-request-id")
    |> put_resp_header("access-control-max-age", "86400")
    |> send_resp(200, "")
  end
  
  @doc """
  Health check endpoint for monitoring.
  """
  def health(conn, _params) do
    health_data = %{
      status: "healthy",
      version: Arsenal.version(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      operations: Arsenal.list_operations() |> length(),
      uptime: get_uptime()
    }
    
    json(conn, health_data)
  end
  
  @doc """
  API documentation endpoint that returns OpenAPI spec.
  """
  def docs(conn, _params) do
    case Arsenal.generate_api_docs() do
      {:ok, docs} ->
        json(conn, docs)
      
      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Failed to generate documentation", reason: inspect(reason)})
    end
  end
  
  @doc """
  List all available operations with their metadata.
  """
  def operations(conn, _params) do
    operations = 
      Arsenal.list_operations()
      |> Enum.map(fn operation ->
        metadata = Arsenal.Registry.get_metadata(operation.name)
        
        %{
          name: operation.name,
          category: operation.category,
          description: operation.description,
          method: operation.rest_config.method,
          path: operation.rest_config.path,
          metadata: metadata
        }
      end)
    
    json(conn, %{
      operations: operations,
      total: length(operations)
    })
  end
  
  # Private helper functions
  
  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end
end