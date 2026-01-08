defmodule PlaygroundWeb.Components.Layout.Breadcrumb do
  @moduledoc """
  Breadcrumb navigation component with dark mode support.
  """
  use Phoenix.Component

  @doc """
  Renders breadcrumbs.

  ## Examples

      <.breadcrumb items={[
        %{label: "Home", path: "/"},
        %{label: "Users", path: "/admin/users"},
        %{label: "Edit", path: nil}
      ]} />
  """
  attr :items, :list, default: []

  def breadcrumb(assigns) do
    ~H"""
    <nav class="flex" aria-label="Breadcrumb">
      <ol class="inline-flex items-center space-x-1 md:space-x-2">
        <%= for {item, index} <- Enum.with_index(@items) do %>
          <%= if index == 0 do %>
            <li class="inline-flex items-center">
              <%= if item.path && index < length(@items) - 1 do %>
                <.link
                  navigate={item.path}
                  class="inline-flex items-center text-sm font-medium text-muted-foreground hover:text-primary transition-colors duration-200"
                >
                  <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M10.707 2.293a1 1 0 00-1.414 0l-7 7a1 1 0 001.414 1.414L4 10.414V17a1 1 0 001 1h2a1 1 0 001-1v-2a1 1 0 011-1h2a1 1 0 011 1v2a1 1 0 001 1h2a1 1 0 001-1v-6.586l.293.293a1 1 0 001.414-1.414l-7-7z" />
                  </svg>
                  {item.label}
                </.link>
              <% else %>
                <span class="inline-flex items-center text-sm font-medium text-muted-foreground">
                  <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M10.707 2.293a1 1 0 00-1.414 0l-7 7a1 1 0 001.414 1.414L4 10.414V17a1 1 0 001 1h2a1 1 0 001-1v-2a1 1 0 011-1h2a1 1 0 011 1v2a1 1 0 001 1h2a1 1 0 001-1v-6.586l.293.293a1 1 0 001.414-1.414l-7-7z" />
                  </svg>
                  {item.label}
                </span>
              <% end %>
            </li>
          <% else %>
            <li>
              <div class="flex items-center">
                <svg class="w-3 h-3 mx-2 text-muted-foreground" fill="none" viewBox="0 0 6 10">
                  <path
                    stroke="currentColor"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="m1 9 4-4-4-4"
                  />
                </svg>
                <%= if item.path && index < length(@items) - 1 do %>
                  <.link
                    navigate={item.path}
                    class="ml-1 text-sm font-medium text-muted-foreground hover:text-primary md:ml-2 transition-colors duration-200"
                  >
                    {item.label}
                  </.link>
                <% else %>
                  <span class="ml-1 text-sm font-medium text-muted-foreground md:ml-2">
                    {item.label}
                  </span>
                <% end %>
              </div>
            </li>
          <% end %>
        <% end %>
      </ol>
    </nav>
    """
  end
end
