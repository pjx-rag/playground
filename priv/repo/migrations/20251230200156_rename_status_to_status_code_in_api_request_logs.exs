defmodule Playground.Repo.Migrations.RenameStatusToStatusCodeInApiRequestLogs do
  use Ecto.Migration

  def change do
    rename table(:api_request_logs), :status, to: :status_code
  end
end
