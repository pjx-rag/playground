defmodule PlaygroundWeb.ThemeController do
  @moduledoc """
  API controller for serving theme tokens.

  This is a lightweight public endpoint that returns the active theme's
  CSS variables for a given mode (light/dark).
  """

  use PlaygroundWeb, :controller

  alias Playground.Settings

  @doc """
  Returns the active theme tokens for a given mode as JSON.

  GET /api/theme/:mode

  Response:
  ```json
  {
    "mode": "light",
    "tokens": {
      "primary": "#18181b",
      "primary_foreground": "#ffffff",
      ...
    },
    "css": "--primary: #18181b;\n--primary-foreground: #ffffff;\n..."
  }
  ```
  """
  def show(conn, %{"mode" => mode}) when mode in ["light", "dark"] do
    case Settings.get_active_theme(mode) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "No active theme set for #{mode} mode"})

      theme ->
        json(conn, %{
          mode: mode,
          name: theme.name,
          tokens: theme.tokens,
          css: Settings.tokens_to_css(theme.tokens)
        })
    end
  end

  def show(conn, %{"mode" => _mode}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Mode must be 'light' or 'dark'"})
  end
end
