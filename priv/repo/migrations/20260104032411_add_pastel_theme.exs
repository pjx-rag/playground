defmodule Playground.Repo.Migrations.AddPastelTheme do
  use Ecto.Migration

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Pastel Theme (light mode with soft, muted colors)
    execute """
    INSERT INTO themes (id, name, slug, mode, is_system, tokens, inserted_at, updated_at)
    VALUES (
      gen_random_uuid(),
      'Pastel',
      'pastel',
      'light',
      true,
      '#{Jason.encode!(%{
        "primary" => "oklch(0.68 0.12 285)",              # soft lavender
        "primary_soft" => "oklch(0.75 0.03 285)",         # lighter lavender
        "foreground" => "oklch(0.45 0.06 285)",           # dusty purple
        "foreground_soft" => "oklch(0.55 0.05 285)",      # lighter dusty purple
        "foreground_softer" => "oklch(0.65 0.04 285)",    # even lighter purple
        "foreground_softest" => "oklch(0.75 0.03 285)",   # palest purple
        "foreground_primary" => "oklch(0.98 0.01 285)",   # cloud white
        "background_base" => "oklch(0.98 0.005 300)",     # dreamy white
        "background_accent" => "oklch(0.96 0.01 300)",    # soft accent
        "background_input" => "oklch(0.96 0.01 300)",     # input background
        "surface" => "oklch(0.97 0.008 300)",             # surface white
        "overlay" => "oklch(0.99 0.003 300)",             # overlay white
        "border_base" => "oklch(0.85 0.03 300)",          # soft border
        "danger" => "oklch(0.65 0.15 15)",                # soft rose
        "success" => "oklch(0.72 0.12 150)",              # mint green
        "warning" => "oklch(0.78 0.12 75)",               # butter yellow
        "info" => "oklch(0.7 0.12 220)"                   # sky blue
      })}',
      '#{now}',
      '#{now}'
    )
    """
  end

  def down do
    execute "DELETE FROM themes WHERE slug = 'pastel'"
  end
end
