defmodule Playground.OAuth.CleanupExpiredStatesWorker do
  @moduledoc """
  Cleans up expired OAuth states from the database.

  Runs hourly via Oban cron to prevent table bloat.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias Playground.OAuth

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {count, _} = OAuth.cleanup_expired_states()

    if count > 0 do
      Logger.info("Cleaned up expired OAuth states", count: count)
    end

    :ok
  end
end
