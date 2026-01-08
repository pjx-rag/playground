defmodule Playground.Repo.Migrations.CreateAiChatSystem do
  use Ecto.Migration

  def change do
    # ========================================================================
    # AI Chat Tables
    # ========================================================================

    # Chats table - stores AI conversation threads
    create table(:chats) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :model, :string, null: false
      add :is_processing, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chats, [:user_id, :updated_at])
    create index(:chats, [:is_processing])

    # Messages table - stores individual messages in chats
    create table(:messages) do
      add :chat_id, references(:chats, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :tokens_used, :integer
      add :cost_usd, :decimal, precision: 10, scale: 6
      add :api_request_log_id, references(:api_request_logs, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:messages, [:chat_id, :inserted_at])
    create index(:messages, [:api_request_log_id])

    # Request tracking table - for sliding window rate limiting
    create table(:ai_request_tracking) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :requested_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ai_request_tracking, [:user_id, :requested_at])
    create index(:ai_request_tracking, [:requested_at])

    # ========================================================================
    # Extend API Request Logs for Cost Tracking
    # ========================================================================

    alter table(:api_request_logs) do
      add :cost_usd, :decimal, precision: 10, scale: 6
      add :tokens_prompt, :integer
      add :tokens_completion, :integer
      add :tokens_total, :integer
    end

    # ========================================================================
    # Site Settings for AI Configuration
    # ========================================================================

    alter table(:site_settings) do
      add :ai_rate_limit_per_minute, :integer, default: 20
      add :ai_rate_limit_per_hour, :integer, default: 100
      add :ai_rate_limit_per_day, :integer, default: 500
    end
  end
end
