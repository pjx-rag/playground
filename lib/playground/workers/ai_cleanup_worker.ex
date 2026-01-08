defmodule Playground.Workers.AICleanupWorker do
  @moduledoc """
  Scheduled Oban worker to clean up old AI request tracking records.

  Runs daily to remove request tracking records older than 25 hours,
  keeping the database lean while maintaining rate limit functionality.

  ## Configuration

  Add to config/config.exs or config/runtime.exs:

      config :playground, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             # Clean up AI request tracking daily at 2 AM
             {"0 2 * * *", Playground.Workers.AICleanupWorker}
           ]}
        ]
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Playground.AI

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting AI request tracking cleanup...")

    count = AI.cleanup_old_request_tracking()

    Logger.info("AI request tracking cleanup completed: deleted #{count} old records")

    :ok
  end
end
