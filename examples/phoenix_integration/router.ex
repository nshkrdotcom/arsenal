defmodule Examples.PhoenixIntegration.Router do
  @moduledoc """
  Example Phoenix router configuration for Arsenal integration.
  
  This demonstrates how to set up routing for Arsenal operations
  in a Phoenix application.
  """
  
  use Phoenix.Router
  
  alias Examples.PhoenixIntegration.ArsenalController
  
  # Pipeline for API requests
  pipeline :api do
    plug :accepts, ["json"]
    plug :put_secure_browser_headers
    plug CORSPlug, origin: "*"
  end
  
  # Pipeline for Arsenal operations with authentication
  pipeline :arsenal_auth do
    plug Examples.PhoenixIntegration.AuthPlug
    plug Examples.PhoenixIntegration.RateLimitPlug
  end
  
  # Arsenal API routes
  scope "/api/v1", Examples.PhoenixIntegration do
    pipe_through [:api]
    
    # Health and status endpoints (no auth required)
    get "/health", ArsenalController, :health
    get "/docs", ArsenalController, :docs
    get "/operations", ArsenalController, :operations
    
    # Handle CORS preflight
    options "/*path", ArsenalController, :options
  end
  
  # Protected Arsenal operations
  scope "/api/v1", Examples.PhoenixIntegration do
    pipe_through [:api, :arsenal_auth]
    
    # Route all Arsenal operations through the main handler
    # This will match patterns like:
    # POST /api/v1/math/factorial
    # GET /api/v1/users
    # GET /api/v1/users/:id
    # POST /api/v1/processes
    # etc.
    match :*, "/*path", ArsenalController, :handle
  end
end

defmodule Examples.PhoenixIntegration.AuthPlug do
  @moduledoc """
  Authentication plug for Arsenal operations.
  """
  
  import Plug.Conn
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case verify_token(token) do
          {:ok, user} ->
            assign(conn, :current_user, user)
          
          {:error, _reason} ->
            conn
            |> put_status(401)
            |> Phoenix.Controller.json(%{error: "Invalid token"})
            |> halt()
        end
      
      _ ->
        # Check for API key
        case get_req_header(conn, "x-api-key") do
          [api_key] ->
            case verify_api_key(api_key) do
              {:ok, user} ->
                assign(conn, :current_user, user)
              
              {:error, _reason} ->
                conn
                |> put_status(401)
                |> Phoenix.Controller.json(%{error: "Invalid API key"})
                |> halt()
            end
          
          _ ->
            conn
            |> put_status(401)
            |> Phoenix.Controller.json(%{error: "Authentication required"})
            |> halt()
        end
    end
  end
  
  defp verify_token(token) do
    # Implement your JWT verification logic here
    case token do
      "valid-admin-token" -> {:ok, %{id: 1, role: "admin"}}
      "valid-user-token" -> {:ok, %{id: 2, role: "user"}}
      _ -> {:error, :invalid_token}
    end
  end
  
  defp verify_api_key(api_key) do
    # Implement your API key verification logic here
    case api_key do
      "admin-api-key" -> {:ok, %{id: 1, role: "admin", type: "api_key"}}
      "user-api-key" -> {:ok, %{id: 2, role: "user", type: "api_key"}}
      _ -> {:error, :invalid_api_key}
    end
  end
end

defmodule Examples.PhoenixIntegration.RateLimitPlug do
  @moduledoc """
  Rate limiting plug for Arsenal operations.
  """
  
  import Plug.Conn
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    user_id = get_user_id(conn)
    
    case check_rate_limit(user_id) do
      :ok ->
        conn
      
      {:error, :rate_limit_exceeded} ->
        conn
        |> put_status(429)
        |> put_resp_header("retry-after", "60")
        |> Phoenix.Controller.json(%{
          error: "Rate limit exceeded",
          message: "Please wait before making another request"
        })
        |> halt()
    end
  end
  
  defp get_user_id(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      _ -> get_client_ip(conn)
    end
  end
  
  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      _ -> 
        {ip, _port} = conn.remote_ip
        ip |> :inet.ntoa() |> to_string()
    end
  end
  
  defp check_rate_limit(identifier) do
    # Implement rate limiting logic
    # This is a placeholder - you'd typically use a library like Hammer
    # or implement with Redis/ETS
    
    # Example: 100 requests per minute
    case :ets.lookup(:rate_limits, identifier) do
      [] ->
        :ets.insert(:rate_limits, {identifier, 1, :os.system_time(:second)})
        :ok
      
      [{^identifier, count, timestamp}] ->
        current_time = :os.system_time(:second)
        
        if current_time - timestamp > 60 do
          # Reset counter
          :ets.insert(:rate_limits, {identifier, 1, current_time})
          :ok
        else
          if count >= 100 do
            {:error, :rate_limit_exceeded}
          else
            :ets.insert(:rate_limits, {identifier, count + 1, timestamp})
            :ok
          end
        end
    end
  end
end