defmodule Playground.ApiTokens.Workers.TokenRefreshWorker do
  @moduledoc """
  Oban worker for proactive OAuth token refresh.

  This worker runs periodically to find tokens that are expiring soon and
  refreshes them BEFORE they expire, preventing API failures.

  ## How It Works

  1. Query `api_tokens` table for tokens expiring within 10 minutes
  2. For each token, use TokenManager.get_valid_token/2 to refresh
  3. TokenManager handles race conditions via database locking
  4. Worker logs success/failure for monitoring

  ## Scheduling

  This worker should be scheduled to run every 5 minutes via Oban cron:

      config :playground, Oban,
        queues: [default: 10],
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"*/5 * * * *", Playground.ApiTokens.Workers.TokenRefreshWorker}
           ]}
        ]

  ## Monitoring

  Check Oban dashboard for:
  - Failed jobs (token refresh failures)
  - Job execution time (should be < 30s typically)
  - Queue backlog (should be near zero)

  ## Manual Trigger

  To manually refresh all expiring tokens:

      Oban.insert(Playground.ApiTokens.Workers.TokenRefreshWorker.new(%{}))

  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  require Logger

  alias Playground.ApiTokens
  alias Playground.ApiTokens.TokenManager

  @doc """
  Finds and refreshes all tokens expiring within the threshold.

  ## Args
    - `%{"threshold_minutes" => integer}` - Optional threshold in minutes (default: 10)

  ## Returns
    - `:ok` - All tokens processed successfully
    - `{:error, reason}` - One or more tokens failed to refresh
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    threshold_minutes = Map.get(args, "threshold_minutes", 10)

    Logger.info("Starting token refresh worker", threshold_minutes: threshold_minutes)

    expiring_tokens = ApiTokens.find_expiring_tokens(threshold_minutes)

    if Enum.empty?(expiring_tokens) do
      Logger.debug("No tokens need refresh")
      :ok
    else
      Logger.info("Found tokens needing refresh", count: length(expiring_tokens))

      results =
        Enum.map(expiring_tokens, fn token ->
          refresh_token(token)
        end)

      successes = Enum.count(results, &match?(:ok, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      Logger.info("Token refresh completed",
        total: length(expiring_tokens),
        successes: successes,
        failures: failures
      )

      if failures > 0 do
        # Return error to trigger Oban retry
        {:error, "#{failures} tokens failed to refresh"}
      else
        :ok
      end
    end
  end

  ## Private Functions

  defp refresh_token(api_token) do
    Logger.debug("Refreshing token",
      resource_type: api_token.resource_type,
      resource_id: api_token.resource_id,
      expires_at: api_token.expires_at
    )

    case TokenManager.get_valid_token(api_token.resource_type, api_token.resource_id) do
      {:ok, _new_token} ->
        Logger.info("Token refreshed successfully",
          resource_type: api_token.resource_type,
          resource_id: api_token.resource_id
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to refresh token",
          resource_type: api_token.resource_type,
          resource_id: api_token.resource_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end
end
