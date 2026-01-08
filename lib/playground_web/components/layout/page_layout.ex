defmodule PlaygroundWeb.Components.Layout.PageLayout do
  @moduledoc """
  Page layout component with breadcrumbs, title, and actions support.
  """
  use Phoenix.Component
  import PlaygroundWeb.Components.Layout.Breadcrumb

  attr :breadcrumbs, :list, default: []
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :container, :boolean, default: true
  slot :actions
  slot :inner_block, required: true

  def page_layout(assigns) do
    ~H"""
    <div class="bg-background">
      <div class={container_classes(@container)}>
        <%= if @title || (@breadcrumbs && length(@breadcrumbs) > 0) do %>
          <div class="py-4">
            <%= if @title do %>
              <%= if @breadcrumbs && length(@breadcrumbs) > 0 do %>
                <div class="mb-3">
                  <.breadcrumb items={@breadcrumbs} />
                </div>
              <% end %>

              <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
                <div class="min-w-0 flex-1">
                  <h1 class="text-3xl font-bold font-heading text-foreground tracking-tight">
                    {@title}
                  </h1>
                  <%= if @description do %>
                    <p class="mt-2 text-base text-muted-foreground leading-6">
                      {@description}
                    </p>
                  <% end %>
                </div>

                <%= if @actions != [] do %>
                  <div class="flex items-center gap-3 sm:ml-6">
                    {render_slot(@actions)}
                  </div>
                <% end %>
              </div>
            <% else %>
              <!-- Breadcrumbs only (no title) - show actions inline -->
              <div class="flex items-center justify-between">
                <.breadcrumb items={@breadcrumbs} />
                <%= if @actions != [] do %>
                  <div class="flex items-center gap-3">
                    {render_slot(@actions)}
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <div class="border-t border-base"></div>
        <% end %>

        <div class="py-4">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  defp container_classes(true), do: "mx-auto max-w-6xl px-4"
  defp container_classes(false), do: "px-4"
end
