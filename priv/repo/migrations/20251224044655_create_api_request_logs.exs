defmodule Playground.Repo.Migrations.CreateApiRequestLogs do
  use Ecto.Migration

  def change do
    create table(:api_request_logs) do
      add :service, :string, null: false
      add :method, :string, null: false
      add :path, :string, null: false
      add :status, :string
      add :duration_ms, :integer, null: false
      add :success, :boolean, default: true, null: false
      add :request_id, :string, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:api_request_logs, [:service])
    create index(:api_request_logs, [:inserted_at])
    create index(:api_request_logs, [:service, :inserted_at])
  end
end
