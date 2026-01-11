defmodule Playground.Settings.Themes do
  @moduledoc """
  Theme management operations.

  Used by:
  - AdminSettingsLive.Themes
  - SiteSettingsManager (for active theme retrieval)
  - RootLayout (for CSS token rendering)
  """

  import Ecto.Query
  alias Playground.Repo
  alias Playground.Settings.Theme

  @doc """
  Returns the list of all themes.
  """
  def list_all do
    Repo.all(from t in Theme, order_by: [asc: t.mode, asc: t.name])
  end

  @doc """
  Returns themes filtered by mode.
  """
  def list_by_mode(mode) when mode in ["light", "dark"] do
    Repo.all(from t in Theme, where: t.mode == ^mode, order_by: [asc: t.name])
  end

  @doc """
  Gets a single theme by ID.
  """
  def get(id), do: Repo.get(Theme, id)

  @doc """
  Gets a single theme by ID, raises if not found.
  """
  def get!(id), do: Repo.get!(Theme, id)

  @doc """
  Gets a single theme by slug.
  """
  def get_by_slug(slug), do: Repo.get_by(Theme, slug: slug)

  @doc """
  Creates a theme.
  """
  def create(attrs \\ %{}) do
    %Theme{}
    |> Theme.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a theme.
  """
  def update(%Theme{} = theme, attrs) do
    theme
    |> Theme.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a theme.

  System themes cannot be deleted.
  """
  def delete(%Theme{is_system: true}), do: {:error, :cannot_delete_system_theme}

  def delete(%Theme{} = theme) do
    Repo.delete(theme)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking theme changes.
  """
  def change(%Theme{} = theme, attrs \\ %{}) do
    Theme.changeset(theme, attrs)
  end

  @doc """
  Converts a theme's tokens map to CSS custom property declarations.
  """
  def tokens_to_css(tokens) when is_map(tokens) do
    tokens
    |> Enum.map(fn {key, value} ->
      css_key = token_key_to_css_var(key)
      "#{css_key}: #{value};"
    end)
    |> Enum.join("\n")
  end

  defp token_key_to_css_var(key) do
    css_name =
      key
      |> String.replace("_", "-")

    "--#{css_name}"
  end

  @doc """
  Seeds the default Fluxon themes.
  Only creates themes that don't already exist (by slug).
  """
  def seed_defaults do
    default_themes()
    |> Enum.each(fn theme_attrs ->
      case get_by_slug(theme_attrs.slug) do
        nil -> create(theme_attrs)
        _existing -> :ok
      end
    end)

    :ok
  end

  defp default_themes do
    [
      %{
        name: "Fluxon Light",
        slug: "fluxon-light",
        mode: "light",
        is_system: true,
        tokens: %{
          "primary" => "#18181b",
          "primary_soft" => "#f4f4f5",
          "foreground" => "#3f3f46",
          "foreground_soft" => "#52525b",
          "foreground_softer" => "#71717a",
          "foreground_softest" => "#a1a1aa",
          "foreground_primary" => "#ffffff",
          "background_base" => "#ffffff",
          "background_accent" => "#f4f4f5",
          "background_input" => "#ffffff",
          "surface" => "#ffffff",
          "overlay" => "#ffffff",
          "border_base" => "#e4e4e7",
          "danger" => "#dc2626",
          "success" => "#16a34a",
          "warning" => "#f59e0b",
          "info" => "#2563eb"
        }
      },
      %{
        name: "Fluxon Dark",
        slug: "fluxon-dark",
        mode: "dark",
        is_system: true,
        tokens: %{
          "primary" => "#ffffff",
          "primary_soft" => "#27272a",
          "foreground" => "#e4e4e7",
          "foreground_soft" => "#d4d4d8",
          "foreground_softer" => "#a1a1aa",
          "foreground_softest" => "#71717a",
          "foreground_primary" => "#18181b",
          "background_base" => "#18181b",
          "background_accent" => "#3f3f46",
          "background_input" => "#18181b",
          "surface" => "#27272a",
          "overlay" => "#27272a",
          "border_base" => "#3f3f46",
          "danger" => "#dc2626",
          "success" => "#16a34a",
          "warning" => "#f59e0b",
          "info" => "#2563eb"
        }
      },
      %{
        name: "Pastel",
        slug: "pastel",
        mode: "light",
        is_system: true,
        tokens: %{
          "primary" => "#8b7ec8",
          "primary_soft" => "#f5f3fa",
          "foreground" => "#5c5470",
          "foreground_soft" => "#6d6580",
          "foreground_softer" => "#8a829d",
          "foreground_softest" => "#b0a8c0",
          "foreground_primary" => "#ffffff",
          "background_base" => "#faf8ff",
          "background_accent" => "#f0ecf8",
          "background_input" => "#ffffff",
          "surface" => "#ffffff",
          "overlay" => "#ffffff",
          "border_base" => "#e8e4f0",
          "danger" => "#e88b9c",
          "success" => "#7ec89e",
          "warning" => "#e8c88b",
          "info" => "#7eb8c8"
        }
      },
      %{
        name: "Cappuccino",
        slug: "cappuccino",
        mode: "light",
        is_system: true,
        tokens: %{
          "primary" => "#6f4e37",
          "primary_soft" => "#f5efe8",
          "foreground" => "#5c4d3c",
          "foreground_soft" => "#7a6b5a",
          "foreground_softer" => "#998a79",
          "foreground_softest" => "#b8a999",
          "foreground_primary" => "#ffffff",
          "background_base" => "#fdf8f3",
          "background_accent" => "#f0e8dd",
          "background_input" => "#ffffff",
          "surface" => "#ffffff",
          "overlay" => "#ffffff",
          "border_base" => "#e8ddd0",
          "danger" => "#c94c4c",
          "success" => "#5a8f5a",
          "warning" => "#d4a84b",
          "info" => "#5a7fa8"
        }
      }
    ]
  end
end
