defmodule PlaygroundWeb.UnauthorizedLive do
  @moduledoc """
  LiveView for displaying an access denied page (HTTP 403 equivalent).

  Shown when a user attempts to access a route or perform an action
  they don't have permission for.
  """

  use PlaygroundWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Access Denied")}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center px-4">
      <div class="max-w-md w-full text-center">
        <div class="mx-auto flex items-center justify-center h-16 w-16 rounded-full bg-danger/10">
          <.icon name="hero-lock-closed" class="h-8 w-8 text-danger" />
        </div>
        <h1 class="mt-6 text-3xl font-bold text-foreground">Access Denied</h1>
        <p class="mt-4 text-base text-muted-foreground">
          You don't have permission to access this page.
        </p>
        <div class="mt-8">
          <.button navigate={~p"/dashboard"} variant="solid" color="primary">
            <.icon name="hero-home" class="w-4 h-4 mr-2" />
            Go to Dashboard
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
