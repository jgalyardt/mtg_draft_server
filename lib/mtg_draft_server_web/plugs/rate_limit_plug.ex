defmodule MtgDraftServerWeb.RateLimitPlug do
    @moduledoc """
    A plug that provides rate limiting for API endpoints.
    
    This plug uses the MtgDraftServer.RateLimit module to enforce
    rate limits based on IP address or user ID (when authenticated).
    """
    
    import Plug.Conn
    require Logger
  
    @doc """
    Initialize the plug with options.
    
    ## Options
      - limit_type: Atom identifying which rate limit to use from config
                    (e.g. :draft_creation, :api_standard)
    """
    def init(opts) do
      limit_type = Keyword.fetch!(opts, :limit_type)
      %{limit_type: limit_type}
    end
  
    @doc """
    Call function that applies rate limiting to the connection.
    """
    def call(conn, %{limit_type: limit_type}) do
      # Get rate limit settings from config
      {limit, scale_ms} = get_limit_settings(limit_type)
      
      # Get identifier (user_id or IP address)
      identifier = get_identifier(conn)
      
      # Create bucket name from rate limit type and identifier
      bucket = "#{limit_type}:#{identifier}"
      
      # Check rate limit
      case MtgDraftServer.RateLimit.check(bucket, scale_ms, limit) do
        {:allow, _count} ->
          # Request is within limits
          conn
          
        {:deny, retry_after} ->
          # Rate limit exceeded
          Logger.warning("Rate limit exceeded for #{identifier} on #{limit_type}")
          
          conn
          |> put_resp_header("retry-after", "#{div(retry_after, 1000)}")
          |> put_status(429)
          |> Phoenix.Controller.json(%{
              error: "Too many requests",
              message: "Rate limit exceeded. Please try again later."
            })
          |> halt()
      end
    end
    
    # Get rate limit settings from config
    defp get_limit_settings(limit_type) do
      case Application.get_env(:mtg_draft_server, :rate_limits)[limit_type] do
        {limit, scale_ms} -> {limit, scale_ms}
        nil -> 
          Logger.warning("No rate limit configured for #{limit_type}, using defaults")
          {60, 60_000} # Default: 60 requests per minute
      end
    end
    
    # Get a unique identifier for the request
    defp get_identifier(conn) do
      # First try to use user_id if authenticated
      case conn.assigns[:current_user] do
        %{"uid" => uid} when is_binary(uid) and uid != "" ->
          "user:#{uid}"
          
        _ ->
          # Fall back to IP address
          ip = get_client_ip(conn)
          "ip:#{ip}"
      end
    end
    
    # Get client IP address, handling potential proxies
    defp get_client_ip(conn) do
      # Try X-Forwarded-For header first
      case get_req_header(conn, "x-forwarded-for") do
        [forwarded_for | _] ->
          String.split(forwarded_for, ",")
          |> List.first()
          |> String.trim()
          
        [] ->
          # Fall back to remote_ip
          conn.remote_ip
          |> Tuple.to_list()
          |> Enum.join(".")
      end
    end
  end