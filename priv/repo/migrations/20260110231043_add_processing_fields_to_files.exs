defmodule Playground.Repo.Migrations.AddProcessingFieldsToFiles do
  use Ecto.Migration

  def change do
    alter table(:files) do
      add :processing_status, :string, default: "draft", null: false
      add :processing_claim_id, :uuid
      add :processing_claimed_at, :utc_datetime
      add :processing_attempt, :integer, default: 0, null: false
      add :processing_revision, :integer, default: 1, null: false
    end

    # Composite index for pipeline queries
    create index(:files, [:sync_status, :processing_status, :mime_type])
    create index(:files, [:processing_claimed_at])
  end
end
