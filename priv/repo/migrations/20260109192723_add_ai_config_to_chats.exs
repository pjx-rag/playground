defmodule Playground.Repo.Migrations.AddAiConfigToChats do
  use Ecto.Migration

  def change do
    alter table(:chats) do
      add :temperature, :float, default: 0.7
      add :max_tokens, :integer, default: 4096
      add :top_p, :float, default: 1.0
      add :frequency_penalty, :float, default: 0.0
      add :presence_penalty, :float, default: 0.0
    end
  end
end
