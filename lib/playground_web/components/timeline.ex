defmodule PlaygroundWeb.Components.Timeline do
  @moduledoc """
  Timeline/activity feed component for displaying chronological events.

  ## Usage

  ```heex
  <.timeline events={@events}>
    <:event :let={event}>
      <.timeline_item
        icon={event_icon(event)}
        icon_color={event_color(event)}
        title={event.title}
        description={event.description}
        timestamp={event.inserted_at}
      />
    </:event>
  </.timeline>
  ```

  Or use the simpler helper:

  ```heex
  <.timeline_item
    icon="hero-check-circle"
    icon_color="success"
    title="Processing Complete"
    description="File successfully chunked into 42 parts"
    timestamp={~U[2024-01-10 12:00:00Z]}
    show_connector={true}
  />
  ```
  """
  use Phoenix.Component
  import PlaygroundWeb.CoreComponents, only: [icon: 1]

  attr :events, :list, required: true, doc: "List of events to display in the timeline"
  attr :class, :string, default: nil, doc: "Additional CSS classes for the timeline container"

  slot :event, required: true do
    attr :let, :any
  end

  def timeline(assigns) do
    ~H"""
    <div class={["flow-root", @class]}>
      <ul role="list" class="-mb-8">
        <%= for {event, index} <- Enum.with_index(@events) do %>
          <li>
            <div class="relative pb-8">
              <%= if index < length(@events) - 1 do %>
                <span
                  aria-hidden="true"
                  class="absolute left-4 top-4 -ml-px h-full w-0.5 bg-border-base"
                >
                </span>
              <% end %>
              <%= render_slot(@event, event) %>
            </div>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  attr :icon, :string, required: true, doc: "Hero icon name (e.g., 'hero-check-circle')"

  attr :icon_color, :string,
    default: "primary",
    doc:
      "Color variant for the icon background: primary, success, warning, danger, info, or custom class"

  attr :title, :string, required: true, doc: "Main title/heading for the timeline item"
  attr :description, :string, default: nil, doc: "Optional description or additional details"
  attr :timestamp, :any, required: true, doc: "DateTime for the event"
  attr :show_connector, :boolean, default: true, doc: "Whether to show the connecting line"
  attr :metadata, :list, default: [], doc: "Additional metadata items to display"

  def timeline_item(assigns) do
    assigns = assign(assigns, :icon_bg_class, icon_background_class(assigns.icon_color))

    ~H"""
    <div class="relative flex space-x-3">
      <div>
        <span class={"flex size-8 items-center justify-center rounded-full ring-8 ring-card #{@icon_bg_class}"}>
          <.icon name={@icon} class="size-4 text-white" />
        </span>
      </div>
      <div class="flex min-w-0 flex-1 justify-between space-x-4 pt-1.5">
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-foreground">
            <%= @title %>
          </p>
          <%= if @description do %>
            <p class="mt-0.5 text-sm text-muted-foreground">
              <%= @description %>
            </p>
          <% end %>
          <%= if @metadata != [] do %>
            <div class="mt-1 flex flex-wrap gap-x-3 gap-y-1">
              <%= for {key, value} <- @metadata do %>
                <span class="text-xs text-muted-foreground">
                  <span class="font-medium"><%= key %>:</span>
                  <%= value %>
                </span>
              <% end %>
            </div>
          <% end %>
        </div>
        <div class="whitespace-nowrap text-right text-sm text-muted-foreground">
          <time datetime={DateTime.to_iso8601(@timestamp)}>
            <%= format_relative_time(@timestamp) %>
          </time>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp icon_background_class("primary"), do: "bg-primary"
  defp icon_background_class("success"), do: "bg-success"
  defp icon_background_class("warning"), do: "bg-warning"
  defp icon_background_class("danger"), do: "bg-danger"
  defp icon_background_class("info"), do: "bg-info"
  defp icon_background_class(custom), do: custom

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
