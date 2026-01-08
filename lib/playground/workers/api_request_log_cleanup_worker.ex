defmodule Playground.Workers.APIRequestLogCleanupWorker do
  @moduledoc """
  Oban worker that cleans up old API request logs.

  Runs daily to remove logs older than the configured retention period.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  require Logger
  import Ecto.Query

  alias Playground.Repo
  alias Playground.APIRequestLog

  @default_retention_days 30

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Starting API request log cleanup")
    {:ok, deleted_count} = cleanup_old_logs()
    Logger.info("API request log cleanup completed: #{deleted_count} logs deleted")
    :ok
  end

  defp cleanup_old_logs do
    retention_days =
      Application.get_env(:playground, :api_request_log_retention_days, @default_retention_days)

    cutoff = DateTime.add(DateTime.utc_now(), -retention_days, :day)

    {deleted, _} =
      from(l in APIRequestLog, where: l.inserted_at < ^cutoff)
      |> Repo.delete_all()

    {:ok, deleted}
  end
end
