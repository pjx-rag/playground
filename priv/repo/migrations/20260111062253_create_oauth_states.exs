defmodule Playground.Repo.Migrations.CreateOauthStates do
  use Ecto.Migration

  def change do
    create table(:oauth_states, primary_key: false) do
      add :state_id, :string, primary_key: true
      add :user_id, :integer, null: false
      add :connector_id, :integer, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Index for efficient cleanup of expired states
    create index(:oauth_states, [:expires_at])
  end
end
