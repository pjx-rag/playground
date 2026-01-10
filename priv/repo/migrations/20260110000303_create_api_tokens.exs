defmodule Playground.Repo.Migrations.CreateApiTokens do
  use Ecto.Migration

  def change do
    # Generic polymorphic OAuth token storage
    # Works for connectors, integrations, or any OAuth resource
    create table(:api_tokens) do
      add :resource_type, :string, null: false
      add :resource_id, :integer, null: false
      add :access_token, :text, null: false
      add :refresh_token, :text
      add :expires_at, :utc_datetime
      add :token_type, :string, default: "Bearer"
      add :scope, :text

      timestamps(type: :utc_datetime)
    end

    # One active token per resource
    create unique_index(:api_tokens, [:resource_type, :resource_id])
    # For finding tokens that need refresh
    create index(:api_tokens, [:expires_at])
  end
end
