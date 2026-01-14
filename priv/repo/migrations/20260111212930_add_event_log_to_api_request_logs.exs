defmodule Playground.Repo.Migrations.AddEventLogToApiRequestLogs do
  use Ecto.Migration

  def change do
    alter table(:api_request_logs) do
      add :event_log_id, references(:event_logs, on_delete: :nilify_all)
    end

    create index(:api_request_logs, [:event_log_id])
  end
end
