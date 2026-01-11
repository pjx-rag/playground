defmodule PlaygroundWeb.AdminConnectorsLive.Index do
  use PlaygroundWeb, :live_view

  alias Playground.Connectors

  import PlaygroundWeb.Components.Layout.PageLayout

  @impl true
  def mount(_params, _session, socket) do
    breadcrumbs = [
      %{label: "Admin", path: ~p"/admin"},
      %{label: "Connectors", path: nil}
    ]

    socket =
      socket
      |> assign(:page_title, "Connectors")
      |> assign(:breadcrumbs, breadcrumbs)
      |> assign(:show_add_modal, false)
      |> assign(:selected_connector, nil)

    if connected?(socket) do
      # List all available connector types
      connector_types = Connectors.list_connectors()

      # List organization's connected connectors
      connector_orgs = Connectors.list_organization_connectors(socket.assigns.current_user)

      {:ok,
       socket
       |> assign(:connector_types, connector_types)
       |> assign(:connector_orgs, connector_orgs)}
    else
      {:ok,
       socket
       |> assign(:connector_types, [])
       |> assign(:connector_orgs, [])}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_add_modal", _params, socket) do
    {:noreply, assign(socket, :show_add_modal, true)}
  end

  @impl true
  def handle_event("hide_add_modal", _params, socket) do
    {:noreply, assign(socket, show_add_modal: false, selected_connector: nil)}
  end

  @impl true
  def handle_event("select_connector", %{"key" => key}, socket) do
    connector = Enum.find(socket.assigns.connector_types, &(&1.key == key))

    # Generate OAuth authorization URL
    auth_url =
      case connector.key do
        "google_drive" ->
          state = generate_state(socket.assigns.current_user.id, connector.id)
          Playground.Services.GoogleDrive.authorize_url(state: state)

        _ ->
          nil
      end

    if auth_url do
      {:noreply, redirect(socket, external: auth_url)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Connector not yet implemented")
       |> assign(:show_add_modal, false)}
    end
  end

  @impl true
  def handle_event("test_connection", %{"id" => id}, socket) do
    connector_org = Connectors.get_connector_organization!(id)

    result =
      with {:ok, token} <- Playground.ApiTokens.TokenManager.get_valid_token("connector", connector_org.id),
           {:ok, health} <- Playground.Services.GoogleDrive.health_check_with_token(token) do
        {:ok, health}
      else
        {:error, reason} -> {:error, reason}
      end

    case result do
      {:ok, %{status: :healthy}} ->
        {:noreply, put_flash(socket, :info, "Connection test successful! Google Drive is accessible.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Connection test failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("test_api_health", %{"key" => "google_drive"}, socket) do
    # Test Google Drive API health WITHOUT using customer tokens
    case Playground.Services.GoogleDrive.health_check() do
      {:ok, %{status: :healthy, latency_ms: latency, oauth_configured: oauth_status}} ->
        config_msg =
          case oauth_status do
            :ok -> ""
            {:error, msg} -> " (Warning: #{msg})"
          end

        {:noreply,
         put_flash(
           socket,
           :info,
           "Google Drive API is healthy (#{latency}ms latency)#{config_msg}"
         )}

      {:error, %{message: message, oauth_configured: oauth_status}} ->
        config_msg =
          case oauth_status do
            :ok -> ""
            {:error, msg} -> " OAuth: #{msg}."
          end

        {:noreply, put_flash(socket, :error, "API health check failed: #{message}.#{config_msg}")}
    end
  end

  @impl true
  def handle_event("test_api_health", %{"key" => _other_key}, socket) do
    {:noreply, put_flash(socket, :info, "Health check not yet implemented for this connector")}
  end

  @impl true
  def handle_event("disconnect", %{"id" => id}, socket) do
    connector_org = Connectors.get_connector_organization!(id)

    case Connectors.delete_connector_organization(connector_org) do
      {:ok, _} ->
        # Also delete associated token
        Playground.ApiTokens.TokenManager.revoke_token("connector", connector_org.id)

        connector_orgs = Connectors.list_organization_connectors(socket.assigns.current_user)

        {:noreply,
         socket
         |> put_flash(:info, "Connector disconnected successfully")
         |> assign(:connector_orgs, connector_orgs)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to disconnect connector")}
    end
  end

  defp generate_state(user_id, connector_id) do
    data = "#{user_id}:#{connector_id}"
    signature = :crypto.mac(:hmac, :sha256, state_secret(), data) |> Base.encode64()
    "#{data}:#{signature}"
  end

  defp state_secret do
    Application.fetch_env!(:playground, PlaygroundWeb.Endpoint)[:secret_key_base]
    |> binary_part(0, 32)
  end

  defp status_badge_class(status) do
    case status do
      "active" -> "bg-success-soft text-foreground-success-soft"
      "pending_auth" -> "bg-warning-soft text-foreground-warning-soft"
      "disconnected" -> "bg-muted text-muted-foreground"
      _ -> "bg-muted text-muted-foreground"
    end
  end

  defp status_text(status) do
    case status do
      "active" -> "Active"
      "pending_auth" -> "Pending"
      "disconnected" -> "Disconnected"
      _ -> String.capitalize(status)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_layout>
      <div class="space-y-8">
        <!-- Connected Sources -->
      <section>
        <div class="flex items-center gap-3 mb-4">
          <div class="flex items-center justify-center w-10 h-10 rounded-lg bg-primary/10">
            <.icon name="hero-link" class="w-5 h-5 text-primary" />
          </div>
          <h2 class="text-lg font-semibold text-foreground">Connected Sources</h2>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          <!-- Add Connector Card -->
          <button
            type="button"
            phx-click="show_add_modal"
            class="group bg-card border-2 border-dashed border-base rounded-xl p-6 transition-all duration-200 hover:border-primary hover:bg-primary/5 hover:-translate-y-0.5 flex flex-col items-center justify-center min-h-[180px]"
          >
            <div class="flex items-center justify-center w-12 h-12 rounded-full bg-primary/10 group-hover:bg-primary/20 transition-colors mb-3">
              <.icon name="hero-plus" class="w-6 h-6 text-primary" />
            </div>
            <p class="text-sm font-semibold text-foreground group-hover:text-primary transition-colors">
              Add Connector
            </p>
            <p class="text-xs text-muted-foreground mt-1">
              Connect a data source
            </p>
          </button>

          <!-- Existing Connectors -->
          <%= for conn_org <- @connector_orgs do %>
            <.connector_card conn_org={conn_org} />
          <% end %>
        </div>
      </section>
      </div>

      <!-- Add Connector Modal -->
      <%= if @show_add_modal do %>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
          phx-click="hide_add_modal"
        >
          <div
            class="bg-card rounded-xl shadow-xl max-w-2xl w-full mx-4"
            phx-click="stop_propagation"
          >
            <div class="flex items-center justify-between p-6 border-b border-base">
              <h2 class="text-lg font-semibold text-foreground">Add Connector</h2>
              <button
                type="button"
                phx-click="hide_add_modal"
                class="text-muted-foreground hover:text-foreground transition-colors"
              >
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>
            <div class="p-6">
              <p class="text-sm text-muted-foreground mb-6">
                Select a connector to connect your data source
              </p>
              <div class="grid grid-cols-1 gap-4">
                <%= for connector <- @connector_types do %>
                  <button
                    type="button"
                    phx-click="select_connector"
                    phx-value-key={connector.key}
                    class="group relative bg-card border border-base rounded-xl p-5 transition-all duration-200 hover:shadow-lg hover:border-primary/50 hover:-translate-y-0.5 text-left"
                  >
                    <div class="flex items-center gap-4">
                      <.connector_modal_icon key={connector.key} icon={connector.icon} />
                      <div class="flex-1 min-w-0">
                        <h3 class="text-sm font-semibold text-foreground group-hover:text-primary transition-colors">
                          <%= connector.name %>
                        </h3>
                        <p class="text-sm text-muted-foreground mt-1">
                          <%= connector_description(connector.key) %>
                        </p>
                      </div>
                      <.icon
                        name="hero-chevron-right"
                        class="w-5 h-5 text-muted-foreground group-hover:text-primary group-hover:translate-x-0.5 transition-all flex-shrink-0"
                      />
                    </div>
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </.page_layout>
    """
  end

  attr :conn_org, :map, required: true

  defp connector_card(assigns) do
    ~H"""
    <div class="group bg-card border border-base rounded-xl transition-all duration-200 hover:shadow-lg hover:border-primary/50 hover:-translate-y-0.5 flex flex-col min-h-[180px]">
      <div class="p-6 flex-1">
        <div class="flex flex-col items-center text-center">
          <.connector_logo key={@conn_org.connector.key} />
          <h3 class="text-sm font-semibold text-foreground mt-3">
            <%= @conn_org.connector.name %>
          </h3>
          <p class="text-xs text-muted-foreground mt-1 truncate max-w-full">
            <%= if @conn_org.metadata["email"] do %>
              <%= @conn_org.metadata["email"] %>
            <% else %>
              <%= @conn_org.user.email %>
            <% end %>
          </p>
          <span class={["inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium mt-2", status_badge_class(@conn_org.status)]}>
            <%= status_text(@conn_org.status) %>
          </span>
        </div>
      </div>
      <div class="px-4 py-3 border-t border-base bg-muted/30 rounded-b-xl flex items-center gap-2">
        <.link
          navigate={~p"/admin/connectors/#{@conn_org.id}"}
          class="flex-1 inline-flex items-center justify-center gap-2 px-3 py-1.5 text-sm font-medium text-foreground bg-card border border-base rounded-lg hover:bg-muted/50 transition-colors"
        >
          <.icon name="hero-folder-open" class="w-4 h-4" />
          Browse
        </.link>
        <button
          type="button"
          phx-click="test_api_health"
          phx-value-key={@conn_org.connector.key}
          class="inline-flex items-center justify-center px-3 py-1.5 text-sm font-medium text-foreground bg-card border border-base rounded-lg hover:bg-primary/10 transition-colors"
          title="Test API connectivity"
        >
          <.icon name="hero-signal" class="w-4 h-4" />
        </button>
        <button
          type="button"
          phx-click="disconnect"
          phx-value-id={@conn_org.id}
          data-confirm="Are you sure you want to disconnect this connector? Synced files will remain in the database."
          class="inline-flex items-center justify-center px-3 py-1.5 text-sm font-medium text-danger bg-card border border-base rounded-lg hover:bg-danger/10 transition-colors"
        >
          <.icon name="hero-trash" class="w-4 h-4" />
        </button>
      </div>
    </div>
    """
  end

  attr :key, :string, required: true

  defp connector_logo(%{key: "google_drive"} = assigns) do
    ~H"""
    <div class="w-12 h-12 relative">
      <svg viewBox="0 0 87.3 78" class="w-full h-full">
        <path d="M6.6 66.85l3.85 6.65c.8 1.4 1.95 2.5 3.3 3.3l13.75-23.8H0c0 1.55.4 3.1 1.2 4.5l5.4 9.35z" fill="#0066DA"/>
        <path d="M43.65 25L29.9 1.2C28.55 2 27.4 3.1 26.6 4.5l-20.25 35c-.8 1.4-1.2 2.95-1.2 4.5h27.5l11-19z" fill="#00AC47"/>
        <path d="M73.55 76.8c1.35-.8 2.5-1.9 3.3-3.3l1.6-2.75 7.65-13.25c.8-1.4 1.2-2.95 1.2-4.5H59.85l5.85 10.15L73.55 76.8z" fill="#EA4335"/>
        <path d="M43.65 25L57.4 1.2C56.05.4 54.5 0 52.9 0H34.4c-1.6 0-3.15.45-4.5 1.2L43.65 25z" fill="#00832D"/>
        <path d="M59.85 53H27.5l-13.75 23.8c1.35.8 2.9 1.2 4.5 1.2h50.8c1.6 0 3.15-.45 4.5-1.2L59.85 53z" fill="#2684FC"/>
        <path d="M73.4 26.5l-10.1-17.5c-.8-1.4-1.95-2.5-3.3-3.3L43.65 25l16.2 28h27.45c0-1.55-.4-3.1-1.2-4.5l-12.7-22z" fill="#FFBA00"/>
      </svg>
    </div>
    """
  end

  defp connector_logo(assigns) do
    ~H"""
    <div class="w-12 h-12 rounded-lg bg-primary/10 flex items-center justify-center">
      <.icon name="hero-cloud" class="w-6 h-6 text-primary" />
    </div>
    """
  end

  attr :key, :string, required: true
  attr :icon, :string, required: true

  defp connector_modal_icon(%{key: "google_drive"} = assigns) do
    ~H"""
    <div class="flex-shrink-0 w-12 h-12 relative">
      <svg viewBox="0 0 87.3 78" class="w-full h-full">
        <path d="M6.6 66.85l3.85 6.65c.8 1.4 1.95 2.5 3.3 3.3l13.75-23.8H0c0 1.55.4 3.1 1.2 4.5l5.4 9.35z" fill="#0066DA"/>
        <path d="M43.65 25L29.9 1.2C28.55 2 27.4 3.1 26.6 4.5l-20.25 35c-.8 1.4-1.2 2.95-1.2 4.5h27.5l11-19z" fill="#00AC47"/>
        <path d="M73.55 76.8c1.35-.8 2.5-1.9 3.3-3.3l1.6-2.75 7.65-13.25c.8-1.4 1.2-2.95 1.2-4.5H59.85l5.85 10.15L73.55 76.8z" fill="#EA4335"/>
        <path d="M43.65 25L57.4 1.2C56.05.4 54.5 0 52.9 0H34.4c-1.6 0-3.15.45-4.5 1.2L43.65 25z" fill="#00832D"/>
        <path d="M59.85 53H27.5l-13.75 23.8c1.35.8 2.9 1.2 4.5 1.2h50.8c1.6 0 3.15-.45 4.5-1.2L59.85 53z" fill="#2684FC"/>
        <path d="M73.4 26.5l-10.1-17.5c-.8-1.4-1.95-2.5-3.3-3.3L43.65 25l16.2 28h27.45c0-1.55-.4-3.1-1.2-4.5l-12.7-22z" fill="#FFBA00"/>
      </svg>
    </div>
    """
  end

  defp connector_modal_icon(assigns) do
    ~H"""
    <div class="flex-shrink-0 w-12 h-12 rounded-lg bg-primary/10 flex items-center justify-center group-hover:bg-primary/20 transition-colors">
      <.icon name={@icon} class="w-6 h-6 text-primary" />
    </div>
    """
  end

  defp connector_description("google_drive"),
    do: "Connect your Google Drive to sync files for RAG processing"

  defp connector_description(_), do: "Connect this data source"
end
