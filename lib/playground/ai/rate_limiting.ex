defmodule Playground.AI.RateLimiting do
  @moduledoc """
  Rate limiting operations for AI chat requests.

  Used by:
  - AI.Messages
  - AIChatLive (for displaying usage stats)
  - AICleanupWorker
  """

  import Ecto.Query, warn: false
  alias Playground.Repo
  alias Playground.AI.RequestTracking
  alias Playground.Settings

  @doc """
  Checks if a user has exceeded their rate limits across multiple time windows.

  Returns {:ok, stats} if under all limits, {:error, {:rate_limit_exceeded, window}} if over.

  Uses a single optimized database query with FILTER clauses for better performance.

  ## Examples

      iex> check_rate_limit(user_id)
      {:ok, %{per_minute: 18, per_hour: 95, per_day: 487}}

      iex> check_rate_limit(user_id)
      {:error, {:rate_limit_exceeded, :per_minute}}

  Used by: AI.Messages
  """
  def check_rate_limit(user_id) do
    now = DateTime.utc_now()
    settings = Settings.get_site_settings!()

    # Calculate time windows
    minute_ago = DateTime.add(now, -60, :second)
    hour_ago = DateTime.add(now, -1, :hour)
    day_ago = DateTime.add(now, -24, :hour)

    # Single query with FILTER clauses to count all windows at once
    counts =
      from(r in RequestTracking,
        where: r.user_id == ^user_id,
        select: %{
          per_minute:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^minute_ago),
          per_hour:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^hour_ago),
          per_day:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^day_ago)
        }
      )
      |> Repo.one()

    # Check each window
    windows = [
      {:per_minute, settings.ai_rate_limit_per_minute, counts.per_minute},
      {:per_hour, settings.ai_rate_limit_per_hour, counts.per_hour},
      {:per_day, settings.ai_rate_limit_per_day, counts.per_day}
    ]

    Enum.reduce_while(windows, {:ok, %{}}, fn {window_name, limit, count}, {:ok, stats} ->
      if count < limit do
        {:cont, {:ok, Map.put(stats, window_name, limit - count)}}
      else
        {:halt, {:error, {:rate_limit_exceeded, window_name}}}
      end
    end)
  end

  @doc """
  Records a new AI request timestamp for rate limiting.

  Note: Cleanup of old tracking records is handled by a scheduled Oban job
  to avoid performance impact during request processing.

  Used by: AI.Messages
  """
  def record_request(user_id) do
    now = DateTime.utc_now()

    # Insert new tracking record
    tracking_attrs = %{
      user_id: user_id,
      requested_at: now
    }

    %RequestTracking{}
    |> RequestTracking.changeset(tracking_attrs)
    |> Repo.insert()
  end

  @doc """
  Cleans up old request tracking records beyond the retention period (25 hours).

  This should be called by a scheduled Oban job, not synchronously during requests.
  Returns the number of records deleted.

  Used by: AICleanupWorker
  """
  def cleanup_old_tracking do
    cutoff = DateTime.add(DateTime.utc_now(), -25, :hour)

    {count, _} =
      from(r in RequestTracking,
        where: r.requested_at < ^cutoff
      )
      |> Repo.delete_all()

    count
  end

  @doc """
  Gets current usage stats for a user across all time windows.

  Returns %{
    per_minute: %{used: integer, limit: integer, remaining: integer},
    per_hour: %{used: integer, limit: integer, remaining: integer},
    per_day: %{used: integer, limit: integer, remaining: integer}
  }

  Uses a single optimized database query with FILTER clauses for better performance.

  Used by: AIChatLive
  """
  def get_usage_stats(user_id) do
    now = DateTime.utc_now()
    settings = Settings.get_site_settings!()

    # Calculate time windows
    minute_ago = DateTime.add(now, -60, :second)
    hour_ago = DateTime.add(now, -1, :hour)
    day_ago = DateTime.add(now, -24, :hour)

    # Single query with FILTER clauses to count all windows at once
    counts =
      from(r in RequestTracking,
        where: r.user_id == ^user_id,
        select: %{
          per_minute:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^minute_ago),
          per_hour:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^hour_ago),
          per_day:
            fragment("COUNT(*) FILTER (WHERE requested_at >= ?)", ^day_ago)
        }
      )
      |> Repo.one()

    # Build stats map
    %{
      per_minute: %{
        used: counts.per_minute,
        limit: settings.ai_rate_limit_per_minute,
        remaining: max(0, settings.ai_rate_limit_per_minute - counts.per_minute)
      },
      per_hour: %{
        used: counts.per_hour,
        limit: settings.ai_rate_limit_per_hour,
        remaining: max(0, settings.ai_rate_limit_per_hour - counts.per_hour)
      },
      per_day: %{
        used: counts.per_day,
        limit: settings.ai_rate_limit_per_day,
        remaining: max(0, settings.ai_rate_limit_per_day - counts.per_day)
      }
    }
  end
end
