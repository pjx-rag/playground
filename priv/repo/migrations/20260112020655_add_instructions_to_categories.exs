defmodule Playground.Repo.Migrations.AddInstructionsToCategories do
  use Ecto.Migration

  def change do
    alter table(:categories) do
      add :instructions, :text
    end
  end
end
