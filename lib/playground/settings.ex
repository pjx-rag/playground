defmodule Playground.Settings do
  @moduledoc """
  The Settings context facade.

  Delegates to domain-specific mini-contexts:
  - `Settings.AppSettingsManager` - Key-value app settings
  - `Settings.Themes` - Theme management
  - `Settings.SiteSettingsManager` - Site-wide singleton settings
  """

  alias Playground.Settings.{AppSettingsManager, SiteSettingsManager, Themes}

  # ============================================================================
  # APP SETTINGS (KEY-VALUE STORE)
  # ============================================================================

  defdelegate list_app_settings(), to: AppSettingsManager, as: :list_all
  defdelegate get_app_setting!(id), to: AppSettingsManager, as: :get!
  defdelegate get_app_setting_by_key(key), to: AppSettingsManager, as: :get_by_key
  defdelegate get_app_setting_value(key, default \\ nil), to: AppSettingsManager, as: :get_value
  defdelegate create_app_setting(attrs \\ %{}), to: AppSettingsManager, as: :create
  defdelegate update_app_setting(app_setting, attrs), to: AppSettingsManager, as: :update
  defdelegate set_app_setting(key, value), to: AppSettingsManager, as: :set
  defdelegate delete_app_setting(app_setting), to: AppSettingsManager, as: :delete
  defdelegate change_app_setting(app_setting, attrs \\ %{}), to: AppSettingsManager, as: :change
  defdelegate seed_default_app_settings(), to: AppSettingsManager, as: :seed_defaults

  # ============================================================================
  # THEMES
  # ============================================================================

  defdelegate list_themes(), to: Themes, as: :list_all
  defdelegate list_themes_by_mode(mode), to: Themes, as: :list_by_mode
  defdelegate get_theme(id), to: Themes, as: :get
  defdelegate get_theme!(id), to: Themes, as: :get!
  defdelegate get_theme_by_slug(slug), to: Themes, as: :get_by_slug
  defdelegate create_theme(attrs \\ %{}), to: Themes, as: :create
  defdelegate update_theme(theme, attrs), to: Themes, as: :update
  defdelegate delete_theme(theme), to: Themes, as: :delete
  defdelegate change_theme(theme, attrs \\ %{}), to: Themes, as: :change
  defdelegate tokens_to_css(tokens), to: Themes
  defdelegate seed_default_themes(), to: Themes, as: :seed_defaults

  # ============================================================================
  # SITE SETTINGS (SINGLETON)
  # ============================================================================

  defdelegate get_site_settings(), to: SiteSettingsManager, as: :get
  defdelegate get_site_settings!(), to: SiteSettingsManager, as: :get!
  defdelegate update_site_settings(attrs), to: SiteSettingsManager, as: :update
  defdelegate change_site_settings(settings, attrs \\ %{}), to: SiteSettingsManager, as: :change

  # ============================================================================
  # THEME TOKENS FOR RENDERING
  # ============================================================================

  defdelegate get_active_theme(mode), to: SiteSettingsManager
  defdelegate get_theme_css(mode), to: SiteSettingsManager
end
