defmodule PlaygroundWeb.DashboardLive do
  use PlaygroundWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.alert color="warning">
      <p class="font-semibold mb-1">
        <.icon name="hero-wrench-screwdriver" class="size-4 inline mr-1" /> Under Construction
      </p>
      <p class="text-sm">This page is currently being built. Check back soon!</p>
    </.alert>
    """
  end
end
