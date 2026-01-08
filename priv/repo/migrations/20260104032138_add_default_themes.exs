defmodule Playground.Repo.Migrations.AddDefaultThemes do
  use Ecto.Migration

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Default Light Theme (based on Fluxon's light mode colors)
    execute """
    INSERT INTO themes (id, name, slug, mode, is_system, tokens, inserted_at, updated_at)
    VALUES (
      gen_random_uuid(),
      'Fluxon Light',
      'fluxon-light',
      'light',
      true,
      '#{Jason.encode!(%{
        "primary" => "#18181b",              # zinc-900
        "primary_soft" => "#fafafa",         # zinc-50
        "foreground" => "#3f3f46",           # zinc-700
        "foreground_soft" => "#52525b",      # zinc-600
        "foreground_softer" => "#71717a",    # zinc-500
        "foreground_softest" => "#a1a1aa",   # zinc-400
        "foreground_primary" => "#ffffff",   # white
        "background_base" => "#ffffff",      # white
        "background_accent" => "#f4f4f5",    # zinc-100
        "background_input" => "#ffffff",     # white
        "surface" => "#ffffff",              # white
        "overlay" => "#ffffff",              # white
        "border_base" => "#e4e4e7",          # zinc-200
        "danger" => "#dc2626",               # red-600
        "success" => "#16a34a",              # green-600
        "warning" => "#fbbf24",              # amber-400
        "info" => "#2563eb"                  # blue-600
      })}',
      '#{now}',
      '#{now}'
    )
    """

    # Default Dark Theme (based on Fluxon's dark mode colors)
    execute """
    INSERT INTO themes (id, name, slug, mode, is_system, tokens, inserted_at, updated_at)
    VALUES (
      gen_random_uuid(),
      'Fluxon Dark',
      'fluxon-dark',
      'dark',
      true,
      '#{Jason.encode!(%{
        "primary" => "#ffffff",              # white
        "primary_soft" => "#27272a",         # zinc-800
        "foreground" => "#e4e4e7",           # zinc-200
        "foreground_soft" => "#d4d4d8",      # zinc-300
        "foreground_softer" => "#a1a1aa",    # zinc-400
        "foreground_softest" => "#71717a",   # zinc-500
        "foreground_primary" => "#27272a",   # zinc-800
        "background_base" => "#18181b",      # zinc-900
        "background_accent" => "#3f3f46",    # zinc-700
        "background_input" => "#18181b",     # zinc-900
        "surface" => "#27272a",              # zinc-800
        "overlay" => "#27272a",              # zinc-800
        "border_base" => "#3f3f46",          # zinc-700
        "danger" => "#dc2626",               # red-600
        "success" => "#16a34a",              # green-600
        "warning" => "#fbbf24",              # amber-400
        "info" => "#2563eb"                  # blue-600
      })}',
      '#{now}',
      '#{now}'
    )
    """
  end

  def down do
    execute "DELETE FROM themes WHERE slug IN ('fluxon-light', 'fluxon-dark')"
  end
end
