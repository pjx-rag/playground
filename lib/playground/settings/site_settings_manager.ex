defmodule Playground.Settings.SiteSettingsManager do
  @moduledoc """
  Site settings management operations (singleton pattern).

  Manages the global site settings including active theme selection
  and broadcasts theme changes via PubSub.

  Used by:
  - AdminSettingsLive.SiteSettings
  - RootLayout (for active theme retrieval)
  """

  alias Playground.Repo
  alias Playground.Settings.SiteSettings

  @doc """
  Gets the site settings singleton, creating it if it doesn't exist.
  """
  def get do
    case Repo.one(SiteSettings) do
      nil -> create()
      settings -> {:ok, Repo.preload(settings, [:light_theme, :dark_theme])}
    end
  end

  @doc """
  Gets the site settings singleton, raises if something goes wrong.
  """
  def get! do
    case get() do
      {:ok, settings} -> settings
      {:error, reason} -> raise "Failed to get site settings: #{inspect(reason)}"
    end
  end

  defp create do
    # Get default themes if they exist
    light_theme = Playground.Settings.Themes.get_by_slug("fluxon-light")
    dark_theme = Playground.Settings.Themes.get_by_slug("fluxon-dark")

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
  def update(attrs) do
    {:ok, settings} = get()

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
  def change(%SiteSettings{} = settings, attrs \\ %{}) do
    SiteSettings.changeset(settings, attrs)
  end

  defp broadcast_theme_change do
    Phoenix.PubSub.broadcast(Playground.PubSub, "theme_settings", :theme_changed)
  end

  @doc """
  Gets the active theme for a given mode ("light" or "dark").
  Returns the theme or nil if not set.
  """
  def get_active_theme(mode) when mode in ["light", "dark"] do
    {:ok, settings} = get()

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
      theme -> Playground.Settings.Themes.tokens_to_css(theme.tokens)
    end
  end

  @doc """
  Ensures site settings exist with default themes.
  Called during theme seeding.
  """
  def ensure_defaults do
    get()
    :ok
  end
end
