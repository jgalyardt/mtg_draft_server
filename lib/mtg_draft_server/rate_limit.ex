# lib/mtg_draft_server/rate_limit.ex
defmodule MtgDraftServer.RateLimit do
  @moduledoc """
  Rate limiting functionality for the MTG Draft Server.

  This module leverages Hammer to implement configurable rate limits
  for various API operations.
  """
  use Hammer, backend: :ets

  @doc """
  Check if a request is allowed based on the rate limit settings.

  ## Parameters
    - bucket: String identifying the rate limit bucket (e.g. "login:123.45.67.89")
    - scale_ms: Time window in milliseconds
    - limit: Maximum number of requests allowed in the time window
    
  ## Returns
    - {:allow, count} if allowed
    - {:deny, retry_after} if denied
  """
  def check(bucket, scale_ms, limit) do
    :telemetry.execute(
      [:mtg_draft_server, :rate_limit, :hit],
      %{count: 1},
      %{bucket: bucket}
    )

    case hit(bucket, scale_ms, limit) do
      {:allow, count} = result ->
        result

      {:deny, retry_after} = result ->
        :telemetry.execute(
          [:mtg_draft_server, :rate_limit, :exceeded],
          %{count: 1},
          %{bucket: bucket, retry_after: retry_after}
        )

        result
    end
  end

  @doc """
  Add this to your application supervision tree.
  """
  def child_spec(opts) do
    opts = Keyword.merge([clean_period: :timer.minutes(5)], opts)

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end
end
