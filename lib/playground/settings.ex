defmodule Playground.Settings do
  @moduledoc """
  The Settings context for managing site-wide settings and themes.
  """

  import Ecto.Query
  alias Playground.Repo
  alias Playground.Settings.{Theme, SiteSettings}

  # ============================================================================
  # THEMES
  # ============================================================================

  @doc """
  Returns the list of all themes.
  """
  def list_themes do
    Repo.all(from t in Theme, order_by: [asc: t.mode, asc: t.name])
  end

  @doc """
  Returns themes filtered by mode.
  """
  def list_themes_by_mode(mode) when mode in ["light", "dark"] do
    Repo.all(from t in Theme, where: t.mode == ^mode, order_by: [asc: t.name])
  end

  @doc """
  Gets a single theme by ID.
  """
  def get_theme(id), do: Repo.get(Theme, id)

  @doc """
  Gets a single theme by ID, raises if not found.
  """
  def get_theme!(id), do: Repo.get!(Theme, id)

  @doc """
  Gets a single theme by slug.
  """
  def get_theme_by_slug(slug), do: Repo.get_by(Theme, slug: slug)

  @doc """
  Creates a theme.
  """
  def create_theme(attrs \\ %{}) do
    %Theme{}
    |> Theme.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a theme.
  """
  def update_theme(%Theme{} = theme, attrs) do
    theme
    |> Theme.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a theme.

  System themes cannot be deleted.
  """
  def delete_theme(%Theme{is_system: true}), do: {:error, :cannot_delete_system_theme}

  def delete_theme(%Theme{} = theme) do
    Repo.delete(theme)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking theme changes.
  """
  def change_theme(%Theme{} = theme, attrs \\ %{}) do
    Theme.changeset(theme, attrs)
  end

  # ============================================================================
  # SITE SETTINGS (SINGLETON)
  # ============================================================================

  @doc """
  Gets the site settings singleton, creating it if it doesn't exist.
  """
  def get_site_settings do
    case Repo.one(SiteSettings) do
      nil -> create_site_settings()
      settings -> {:ok, Repo.preload(settings, [:light_theme, :dark_theme])}
    end
  end

  @doc """
  Gets the site settings singleton, raises if something goes wrong.
  """
  def get_site_settings! do
    case get_site_settings() do
      {:ok, settings} -> settings
      {:error, reason} -> raise "Failed to get site settings: #{inspect(reason)}"
    end
  end

  defp create_site_settings do
    # Get default themes if they exist
    light_theme = get_theme_by_slug("fluxon-light")
    dark_theme = get_theme_by_slug("fluxon-dark")

    %SiteSettings{}
    |> SiteSettings.changeset(%{
      light_theme_id: light_theme && light_theme.id,
      dark_theme_id: dark_theme && dark_theme.id
    })
    |> Repo.insert(on_conflict: :nothing)
    |> case do
      {:ok, settings} ->
        {:ok, Repo.preload(settings, [:light_theme, :dark_theme])}

      {:error, %Ecto.Changeset{}} ->
        # Race condition: another process created it, fetch the existing record
        settings = Repo.one(SiteSettings) |> Repo.preload([:light_theme, :dark_theme])
        {:ok, settings}

      error ->
        error
    end
  end

  @doc """
  Updates the site settings.
  """
  def update_site_settings(attrs) do
    {:ok, settings} = get_site_settings()

    settings
    |> SiteSettings.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, settings} ->
        settings = Repo.preload(settings, [:light_theme, :dark_theme], force: true)
        broadcast_theme_change()
        {:ok, settings}

      error ->
        error
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking site settings changes.
  """
  def change_site_settings(%SiteSettings{} = settings, attrs \\ %{}) do
    SiteSettings.changeset(settings, attrs)
  end

  defp broadcast_theme_change do
    Phoenix.PubSub.broadcast(Playground.PubSub, "theme_settings", :theme_changed)
  end

  # ============================================================================
  # THEME TOKENS FOR RENDERING
  # ============================================================================

  @doc """
  Gets the active theme for a given mode ("light" or "dark").
  Returns the theme or nil if not set.
  """
  def get_active_theme(mode) when mode in ["light", "dark"] do
    {:ok, settings} = get_site_settings()

    case mode do
      "light" -> settings.light_theme
      "dark" -> settings.dark_theme
    end
  end

  @doc """
  Gets the active theme tokens for a given mode as CSS variable declarations.
  Returns a string of CSS custom properties.
  """
  def get_theme_css(mode) when mode in ["light", "dark"] do
    case get_active_theme(mode) do
      nil -> ""
      theme -> tokens_to_css(theme.tokens)
    end
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

  # ============================================================================
  # SEEDING
  # ============================================================================

  @doc """
  Seeds the default Fluxon themes.
  Only creates themes that don't already exist (by slug).
  """
  def seed_default_themes do
    default_themes()
    |> Enum.each(fn theme_attrs ->
      case get_theme_by_slug(theme_attrs.slug) do
        nil -> create_theme(theme_attrs)
        _existing -> :ok
      end
    end)

    # Ensure site settings exist with defaults
    get_site_settings()

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
