defmodule PlaygroundWeb.AdminDashboardLive.Index do
  @moduledoc """
  Admin dashboard for system administration.
  """
  use PlaygroundWeb, :live_view

  import PlaygroundWeb.Components.Layout.PageLayout

  # All API services that implement the APIClient behaviour
  @api_services [
    Playground.Services.OpenRouter,
    Playground.Services.WeatherAPI
  ]

  @impl true
  def mount(_params, _session, socket) do
    # Build initial service list with unchecked status
    api_services =
      @api_services
      |> Enum.map(fn service ->
        %{
          module: service,
          name: service.service_name(),
          status: :unchecked,
          latency: nil,
          message: nil,
          loading: false
        }
      end)

    breadcrumbs = [
      %{label: "Admin Dashboard", path: nil}
    ]

    {:ok,
     socket
     |> assign(:page_title, "Admin Dashboard")
     |> assign(:breadcrumbs, breadcrumbs)
     |> assign(:api_services, api_services)
     |> assign(:health_loading, false)}
  end

  @impl true
  def handle_event("check-api-health", _params, socket) do
    # Run all health checks asynchronously
    socket =
      socket
      |> assign(:health_loading, true)
      |> update(:api_services, fn services ->
        Enum.map(services, &Map.put(&1, :loading, true))
      end)

    pid = self()

    Task.start(fn ->
      results =
        @api_services
        |> Enum.map(fn service ->
          {service.service_name(), service.health_check()}
        end)
        |> Map.new()

      send(pid, {:health_check_results, results})
    end)

    {:noreply, socket}
  end

  def handle_event("check-single-api", %{"service" => service_name}, socket) do
    # Mark this service as loading
    socket =
      update(socket, :api_services, fn services ->
        Enum.map(services, fn s ->
          if s.name == service_name, do: Map.put(s, :loading, true), else: s
        end)
      end)

    pid = self()

    Task.start(fn ->
      service = Enum.find(@api_services, fn s -> s.service_name() == service_name end)

      if service do
        result = service.health_check()
        send(pid, {:single_health_check_result, service_name, result})
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:health_check_results, results}, socket) do
    api_services =
      Enum.map(socket.assigns.api_services, fn service ->
        case Map.get(results, service.name) do
          {:ok, %{status: status, latency_ms: latency, message: message}} ->
            %{service | status: status, latency: latency, message: message, loading: false}

          {:error, reason} ->
            %{service | status: :unhealthy, latency: nil, message: inspect(reason), loading: false}

          nil ->
            %{service | loading: false}
        end
      end)

    {:noreply,
     socket
     |> assign(:api_services, api_services)
     |> assign(:health_loading, false)}
  end

  def handle_info({:single_health_check_result, service_name, result}, socket) do
    api_services =
      Enum.map(socket.assigns.api_services, fn service ->
        if service.name == service_name do
          case result do
            {:ok, %{status: status, latency_ms: latency, message: message}} ->
              %{service | status: status, latency: latency, message: message, loading: false}

            {:error, reason} ->
              %{service | status: :unhealthy, latency: nil, message: inspect(reason), loading: false}
          end
        else
          service
        end
      end)

    {:noreply, assign(socket, :api_services, api_services)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_layout>
      <div class="space-y-8">
        <!-- System Administration Section -->
        <.section_card title="System Administration" icon="hero-cog-6-tooth">
          <.quick_link_card
            title="User Management"
            description="Manage user accounts and permissions"
            url="/admin/users"
            icon="hero-users"
          />
          <.quick_link_card
            title="Roles & Permissions"
            description="Manage authorization roles, permissions, and grants"
            url="/admin/roles"
            icon="hero-shield-check"
          />
        </.section_card>

        <!-- Look & Feel Section -->
        <.section_card title="Look & Feel" icon="hero-paint-brush">
          <.quick_link_card
            title="Branding"
            description="Configure site name, logo, and branding"
            url="/admin/settings"
            icon="hero-photo"
          />
          <.quick_link_card
            title="Themes"
            description="Customize UI themes and color schemes"
            url="/admin/themes"
            icon="hero-swatch"
          />
        </.section_card>

        <!-- API Health Checks Section -->
        <.api_health_section api_services={@api_services} health_loading={@health_loading} />

        <!-- Monitoring & Tools Section -->
        <.section_card title="Monitoring & Tools" icon="hero-chart-bar">
          <.quick_link_card
            title="Analytics"
            description="View application usage analytics and metrics"
            url="/admin/analytics"
            icon="hero-chart-bar"
          />
          <.quick_link_card
            title="Oban Dashboard"
            description="Monitor background jobs and queues"
            url="/admin/oban"
            icon="hero-cpu-chip"
          />
          <.quick_link_card
            title="System Metrics"
            description="View application performance metrics"
            url="/admin/dashboard"
            icon="hero-chart-bar"
          />
          <.quick_link_card
            title="Error Tracking"
            description="View application errors and exceptions"
            url="/admin/errors"
            icon="hero-exclamation-triangle"
          />
          <.quick_link_card
            title="Database Backups"
            description="Create and manage database backups"
            url="/admin/backups"
            icon="hero-circle-stack"
          />
          <.quick_link_card
            title="API Request Logs"
            description="Monitor external API requests and responses"
            url="/admin/api-logs"
            icon="hero-signal"
          />
          <.quick_link_card
            title="Dev Mailbox"
            description="Preview emails sent in development"
            url="/dev/mailbox"
            icon="hero-envelope"
          />
        </.section_card>
      </div>
    </.page_layout>
    """
  end

  # Section wrapper with title
  attr :title, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp section_card(assigns) do
    ~H"""
    <section>
      <div class="flex items-center gap-3 mb-4">
        <div class="flex items-center justify-center w-10 h-10 rounded-lg bg-primary/10">
          <.icon name={@icon} class="w-5 h-5 text-primary" />
        </div>
        <h2 class="text-lg font-semibold text-foreground">{@title}</h2>
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  # Quick link card component
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :url, :string, required: true
  attr :icon, :string, required: true
  attr :disabled, :boolean, default: false

  defp quick_link_card(assigns) do
    ~H"""
    <%= if @disabled do %>
      <div class="relative bg-card border border-base rounded-xl p-5 opacity-50 cursor-not-allowed">
        <div class="flex items-start gap-4">
          <div class="flex-shrink-0 w-10 h-10 rounded-lg bg-muted flex items-center justify-center">
            <.icon name={@icon} class="w-5 h-5 text-muted-foreground" />
          </div>
          <div class="flex-1 min-w-0">
            <h3 class="text-sm font-semibold text-muted-foreground">{@title}</h3>
            <p class="text-sm text-muted-foreground mt-1 line-clamp-2">{@description}</p>
            <span class="text-xs text-muted-foreground mt-2 block italic">Coming soon</span>
          </div>
        </div>
      </div>
    <% else %>
      <.link
        navigate={@url}
        class="group relative bg-card border border-base rounded-xl p-5 transition-all duration-200 hover:shadow-lg hover:border-primary/50 hover:-translate-y-0.5 block"
      >
        <div class="flex items-start gap-4">
          <div class="flex-shrink-0 w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center group-hover:bg-primary/20 transition-colors">
            <.icon name={@icon} class="w-5 h-5 text-primary" />
          </div>
          <div class="flex-1 min-w-0">
            <h3 class="text-sm font-semibold text-foreground group-hover:text-primary transition-colors">
              {@title}
            </h3>
            <p class="text-sm text-muted-foreground mt-1 line-clamp-2">{@description}</p>
          </div>
          <.icon
            name="hero-chevron-right"
            class="w-5 h-5 text-muted-foreground group-hover:text-primary group-hover:translate-x-0.5 transition-all flex-shrink-0"
          />
        </div>
      </.link>
    <% end %>
    """
  end

  # API Health Check Section
  attr :api_services, :list, required: true
  attr :health_loading, :boolean, required: true

  defp api_health_section(assigns) do
    ~H"""
    <section>
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-3">
          <div class="flex items-center justify-center w-10 h-10 rounded-lg bg-primary/10">
            <.icon name="hero-heart" class="w-5 h-5 text-primary" />
          </div>
          <h2 class="text-lg font-semibold text-foreground">API Health Checks</h2>
        </div>
        <.button
          variant="outline"
          size="sm"
          phx-click="check-api-health"
          disabled={@health_loading}
        >
          <%= if @health_loading do %>
            <.icon name="hero-arrow-path" class="w-4 h-4 mr-2 animate-spin" />
            Checking All...
          <% else %>
            <.icon name="hero-arrow-path" class="w-4 h-4 mr-2" />
            Check All
          <% end %>
        </.button>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        <%= for service <- @api_services do %>
          <.api_health_card service={service} />
        <% end %>
      </div>
    </section>
    """
  end

  attr :service, :map, required: true

  defp api_health_card(assigns) do
    ~H"""
    <div class={[
      "bg-card border rounded-xl p-5 transition-all",
      status_border_class(@service.status)
    ]}>
      <div class="flex items-start gap-4">
        <div class={[
          "flex-shrink-0 w-10 h-10 rounded-lg flex items-center justify-center",
          status_bg_class(@service.status)
        ]}>
          <%= if @service.loading do %>
            <.icon name="hero-arrow-path" class="w-5 h-5 text-primary animate-spin" />
          <% else %>
            <.icon name={status_icon(@service.status)} class={"w-5 h-5 #{status_icon_class(@service.status)}"} />
          <% end %>
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-sm font-semibold text-foreground capitalize">{@service.name}</h3>
            <%= if @service.latency do %>
              <span class="text-xs font-mono text-muted-foreground">{@service.latency}ms</span>
            <% end %>
          </div>
          <div class="mt-1 flex items-center gap-2">
            <span class={["inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium", status_badge_class(@service.status)]}>
              {format_status(@service.status)}
            </span>
          </div>
          <%= if @service.message do %>
            <p class="mt-2 text-xs text-muted-foreground line-clamp-2">{@service.message}</p>
          <% end %>
        </div>
      </div>
      <div class="mt-4 pt-3 border-t border-base">
        <button
          type="button"
          phx-click="check-single-api"
          phx-value-service={@service.name}
          disabled={@service.loading}
          class="w-full text-center text-xs font-medium text-primary hover:text-primary/80 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          <%= if @service.loading do %>
            Checking...
          <% else %>
            Check Now
          <% end %>
        </button>
      </div>
    </div>
    """
  end

  defp status_icon(:healthy), do: "hero-check-circle"
  defp status_icon(:degraded), do: "hero-exclamation-triangle"
  defp status_icon(:unhealthy), do: "hero-x-circle"
  defp status_icon(:unchecked), do: "hero-question-mark-circle"

  defp status_border_class(:healthy), do: "border-base"
  defp status_border_class(:degraded), do: "border-base"
  defp status_border_class(:unhealthy), do: "border-base"
  defp status_border_class(:unchecked), do: "border-base"

  defp status_bg_class(:healthy), do: "bg-success"
  defp status_bg_class(:degraded), do: "bg-warning"
  defp status_bg_class(:unhealthy), do: "bg-danger"
  defp status_bg_class(:unchecked), do: "bg-muted"

  defp status_icon_class(:healthy), do: "text-success"
  defp status_icon_class(:degraded), do: "text-warning"
  defp status_icon_class(:unhealthy), do: "text-danger"
  defp status_icon_class(:unchecked), do: "text-muted-foreground"

  defp status_badge_class(:healthy), do: "bg-success-soft text-foreground-success-soft border-success"
  defp status_badge_class(:degraded), do: "bg-warning-soft text-foreground-warning-soft border-warning"
  defp status_badge_class(:unhealthy), do: "bg-danger-soft text-foreground-danger-soft border-danger"
  defp status_badge_class(:unchecked), do: "bg-muted text-muted-foreground border-base"

  defp format_status(:healthy), do: "Healthy"
  defp format_status(:degraded), do: "Degraded"
  defp format_status(:unhealthy), do: "Unhealthy"
  defp format_status(:unchecked), do: "Not Checked"
end
