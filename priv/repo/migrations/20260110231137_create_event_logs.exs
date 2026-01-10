defmodule Playground.Repo.Migrations.CreateEventLogs do
  use Ecto.Migration

  def change do
    create table(:event_logs) do
      add :file_id, references(:files, on_delete: :delete_all), null: false

      add :event, :string, null: false
      add :from_status, :string
      add :to_status, :string
      add :success, :boolean, null: false
      add :error_message, :text
      add :error_type, :string
      add :duration_ms, :integer
      add :metadata, :map, default: %{}

      # Correlate events to a specific run/revision
      add :claim_id, :uuid
      add :revision, :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:event_logs, [:file_id, :revision, :inserted_at])
    create index(:event_logs, [:event])
    create index(:event_logs, [:success])
  end
end
