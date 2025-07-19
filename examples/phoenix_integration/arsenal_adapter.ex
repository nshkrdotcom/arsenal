defmodule Examples.PhoenixIntegration.ArsenalAdapter do
  @moduledoc """
  Phoenix adapter for Arsenal operations.
  
  This adapter integrates Arsenal with Phoenix web framework, providing:
  - Request/response translation
  - Authentication hooks
  - Error handling
  - Logging and metrics
  """
  
  @behaviour Arsenal.Adapter
  
  require Logger
  
  @impl true
  def extract_method(%Plug.Conn{method: method}) do
    method |> String.downcase() |> String.to_atom()
  end
  
  @impl true
  def extract_path(%Plug.Conn{request_path: path}), do: path
  
  @impl true
  def extract_params(%Plug.Conn{} = conn) do
    # Merge all parameter sources
    conn.params
    |> Map.merge(conn.path_params)
    |> Map.merge(conn.query_params)
    |> stringify_keys()
  end
  
  @impl true
  def send_response(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.put_resp_header("x-arsenal-version", Arsenal.version())
    |> Plug.Conn.put_resp_header("x-request-id", get_request_id(conn))
    |> Plug.Conn.put_status(status)
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
  
  @impl true
  def send_error(conn, status, error) do
    error_body = format_error(error, status)
    
    # Log error for monitoring
    Logger.error("Arsenal operation error", 
      error: error, 
      status: status,
      request_id: get_request_id(conn),
      path: conn.request_path,
      method: conn.method
    )
    
    send_response(conn, status, error_body)
  end
  
  @impl true
  def before_process(conn) do
    # Add request tracking
    conn = put_request_id(conn)
    
    with :ok <- authenticate(conn),
         :ok <- authorize(conn),
         :ok <- check_rate_limit(conn) do
      
      Logger.info("Arsenal operation started",
        request_id: get_request_id(conn),
        path: conn.request_path,
        method: conn.method,
        user_id: get_user_id(conn)
      )
      
      {:ok, conn}
    else
      {:error, :authentication_failed} ->
        {:error, {:unauthorized, "Authentication required"}}
      
      {:error, :authorization_failed} ->
        {:error, {:forbidden, "Insufficient permissions"}}
      
      {:error, :rate_limit_exceeded} ->
        {:error, {:rate_limit, "Rate limit exceeded"}}
      
      error ->
        {:error, error}
    end
  end
  
  @impl true
  def after_process(conn, response) do
    # Add response headers
    conn = 
      conn
      |> add_cors_headers()
      |> add_performance_headers(response)
    
    # Log successful completion
    Logger.info("Arsenal operation completed",
      request_id: get_request_id(conn),
      status: "success",
      duration_ms: get_request_duration(conn)
    )
    
    # Emit metrics
    emit_metrics(conn, response)
    
    conn
  end
  
  # Private helper functions
  
  defp stringify_keys(map) when is_map(map) do
    for {key, val} <- map, into: %{} do
      {to_string(key), val}
    end
  end
  
  defp format_error(error, status) do
    base_error = %{
      error: %{
        status: status,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
    
    case error do
      {:validation_error, details} ->
        put_in(base_error, [:error, :code], "VALIDATION_ERROR")
        |> put_in([:error, :message], "Request validation failed")
        |> put_in([:error, :details], details)
      
      {:not_found, message} ->
        put_in(base_error, [:error, :code], "NOT_FOUND")
        |> put_in([:error, :message], message || "Resource not found")
      
      {:unauthorized, message} ->
        put_in(base_error, [:error, :code], "UNAUTHORIZED")
        |> put_in([:error, :message], message || "Authentication required")
      
      {:forbidden, message} ->
        put_in(base_error, [:error, :code], "FORBIDDEN")
        |> put_in([:error, :message], message || "Access denied")
      
      {:rate_limit, message} ->
        put_in(base_error, [:error, :code], "RATE_LIMIT_EXCEEDED")
        |> put_in([:error, :message], message || "Rate limit exceeded")
      
      {:execution_error, reason} ->
        put_in(base_error, [:error, :code], "EXECUTION_ERROR")
        |> put_in([:error, :message], "Operation execution failed")
        |> put_in([:error, :reason], sanitize_error_reason(reason))
      
      _other ->
        put_in(base_error, [:error, :code], "INTERNAL_ERROR")
        |> put_in([:error, :message], "An unexpected error occurred")
    end
  end
  
  defp sanitize_error_reason(reason) do
    # Don't expose internal details in production
    if Application.get_env(:your_app, :environment) == :production do
      "Internal server error"
    else
      inspect(reason)
    end
  end
  
  defp authenticate(conn) do
    # Check for API key or JWT token
    case get_auth_token(conn) do
      nil ->
        # Allow unauthenticated access to public operations
        if public_operation?(conn) do
          :ok
        else
          {:error, :authentication_failed}
        end
      
      token ->
        case verify_token(token) do
          {:ok, claims} ->
            conn = Plug.Conn.assign(conn, :current_user, claims)
            :ok
          
          {:error, _reason} ->
            {:error, :authentication_failed}
        end
    end
  end
  
  defp authorize(conn) do
    # Check if user has permission for this operation
    user = conn.assigns[:current_user]
    operation = get_operation_name(conn)
    
    if has_permission?(user, operation) do
      :ok
    else
      {:error, :authorization_failed}
    end
  end
  
  defp check_rate_limit(conn) do
    # Implement rate limiting based on user or IP
    user_id = get_user_id(conn) || get_client_ip(conn)
    operation = get_operation_name(conn)
    
    case check_rate_limit_for_user(user_id, operation) do
      :ok -> :ok
      {:error, :rate_limit_exceeded} -> {:error, :rate_limit_exceeded}
    end
  end
  
  defp get_auth_token(conn) do
    # Check Authorization header
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> 
        # Check API key header
        case Plug.Conn.get_req_header(conn, "x-api-key") do
          [api_key] -> api_key
          _ -> nil
        end
    end
  end
  
  defp verify_token(token) do
    # Implement JWT verification or API key lookup
    # This is a placeholder implementation
    case token do
      "valid-token" -> {:ok, %{user_id: 123, role: "admin"}}
      "user-token" -> {:ok, %{user_id: 456, role: "user"}}
      _ -> {:error, :invalid_token}
    end
  end
  
  defp public_operation?(conn) do
    # Define which operations don't require authentication
    public_operations = [:factorial, :list_users]
    operation = get_operation_name(conn)
    operation in public_operations
  end
  
  defp has_permission?(nil, _operation), do: false
  defp has_permission?(%{role: "admin"}, _operation), do: true
  defp has_permission?(%{role: "user"}, operation) do
    # Users can only access certain operations
    allowed_operations = [:factorial, :list_users, :get_user]
    operation in allowed_operations
  end
  
  defp get_operation_name(conn) do
    # Extract operation name from path or params
    # This would depend on your routing strategy
    case conn.path_info do
      ["api", "v1", "math", "factorial"] -> :factorial
      ["api", "v1", "users"] when conn.method == "GET" -> :list_users
      ["api", "v1", "users"] when conn.method == "POST" -> :create_user
      ["api", "v1", "users", _id] when conn.method == "GET" -> :get_user
      _ -> :unknown
    end
  end
  
  defp check_rate_limit_for_user(user_id, operation) do
    # Implement rate limiting logic
    # This is a placeholder - you'd typically use a rate limiting library
    # like Hammer or implement with Redis/ETS
    :ok
  end
  
  defp put_request_id(conn) do
    request_id = 
      Plug.Conn.get_req_header(conn, "x-request-id")
      |> List.first()
      |> case do
        nil -> generate_request_id()
        id -> id
      end
    
    conn
    |> Plug.Conn.assign(:request_id, request_id)
    |> Plug.Conn.put_resp_header("x-request-id", request_id)
  end
  
  defp get_request_id(conn) do
    conn.assigns[:request_id] || "unknown"
  end
  
  defp get_user_id(conn) do
    case conn.assigns[:current_user] do
      %{user_id: user_id} -> user_id
      _ -> nil
    end
  end
  
  defp get_client_ip(conn) do
    # Get real IP considering proxies
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      _ -> 
        {ip, _port} = conn.remote_ip
        ip |> :inet.ntoa() |> to_string()
    end
  end
  
  defp generate_request_id do
    System.unique_integer([:positive])
    |> Integer.to_string(36)
  end
  
  defp add_cors_headers(conn) do
    conn
    |> Plug.Conn.put_resp_header("access-control-allow-origin", "*")
    |> Plug.Conn.put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
    |> Plug.Conn.put_resp_header("access-control-allow-headers", "content-type, authorization, x-api-key, x-request-id")
  end
  
  defp add_performance_headers(conn, _response) do
    duration = get_request_duration(conn)
    
    conn
    |> Plug.Conn.put_resp_header("x-response-time", "#{duration}ms")
    |> Plug.Conn.put_resp_header("x-arsenal-operation", to_string(get_operation_name(conn)))
  end
  
  defp get_request_duration(conn) do
    start_time = conn.assigns[:start_time] || :os.system_time(:millisecond)
    :os.system_time(:millisecond) - start_time
  end
  
  defp emit_metrics(conn, _response) do
    # Emit Telemetry events for monitoring
    :telemetry.execute(
      [:arsenal, :adapter, :request],
      %{
        duration: get_request_duration(conn),
        status: 200
      },
      %{
        operation: get_operation_name(conn),
        method: conn.method,
        user_id: get_user_id(conn)
      }
    )
  end
end