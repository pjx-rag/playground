defmodule PlaygroundWeb.ThemeHelpers do
  @moduledoc """
  Helper functions for rendering theme-related content in templates.
  """

  alias Playground.Settings
  alias Phoenix.HTML

  @doc """
  Generates a <style> tag with CSS custom properties for the active themes.

  This is injected into the root layout to prevent flash of unstyled content (FOUC).
  It includes both light and dark theme tokens, using CSS media queries and
  the .dark class selector.
  """
  def theme_css_tag(assigns) do
    user_preference = get_user_theme_preference(assigns)

    light_css = Settings.get_theme_css("light")
    dark_css = Settings.get_theme_css("dark")

    # If no themes are set, return empty
    if light_css == "" and dark_css == "" do
      HTML.raw("")
    else
      css = build_theme_css(light_css, dark_css, user_preference)
      HTML.raw(~s(<style id="theme-tokens">#{css}</style>))
    end
  end

  defp get_user_theme_preference(assigns) do
    case assigns[:current_user] do
      nil -> "system"
      user -> Playground.Accounts.User.theme_preference(user)
    end
  end

  defp build_theme_css(light_css, dark_css, preference) do
    case preference do
      "light" ->
        # User forced light mode - only use light theme
        ":root { #{light_css} }"

      "dark" ->
        # User forced dark mode - only use dark theme
        ":root { #{dark_css} }"

      _ ->
        # System preference - use media queries
        """
        :root { #{light_css} }
        .dark { #{dark_css} }
        @media (prefers-color-scheme: dark) {
          :root:not(.light) { #{dark_css} }
        }
        """
    end
  end
end
