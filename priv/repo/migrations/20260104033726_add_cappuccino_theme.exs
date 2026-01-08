defmodule Playground.Repo.Migrations.AddCappuccinoTheme do
  use Ecto.Migration

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Cappuccino Theme (light mode with warm coffee/brown tones)
    execute """
    INSERT INTO themes (id, name, slug, mode, is_system, tokens, inserted_at, updated_at)
    VALUES (
      gen_random_uuid(),
      'Cappuccino',
      'cappuccino',
      'light',
      true,
      '#{Jason.encode!(%{
        "primary" => "#6f4e37",              # coffee brown
        "primary_soft" => "#f5efe8",         # cream
        "foreground" => "#5c4d3c",           # dark brown
        "foreground_soft" => "#7a6b5a",      # medium brown
        "foreground_softer" => "#998a79",    # light brown
        "foreground_softest" => "#b8a999",   # pale brown
        "foreground_primary" => "#ffffff",   # white
        "background_base" => "#fdf8f3",      # warm white
        "background_accent" => "#f0e8dd",    # beige
        "background_input" => "#ffffff",     # white
        "surface" => "#ffffff",              # white
        "overlay" => "#ffffff",              # white
        "border_base" => "#e8ddd0",          # tan
        "danger" => "#c94c4c",               # warm red
        "success" => "#5a8f5a",              # forest green
        "warning" => "#d4a84b",              # golden
        "info" => "#5a7fa8"                  # slate blue
      })}',
      '#{now}',
      '#{now}'
    )
    """
  end

  def down do
    execute "DELETE FROM themes WHERE slug = 'cappuccino'"
  end
end
