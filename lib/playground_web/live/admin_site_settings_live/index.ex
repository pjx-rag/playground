defmodule PlaygroundWeb.AdminSiteSettingsLive.Index do
  @moduledoc """
  Admin page for managing site-wide settings.
  """
  use PlaygroundWeb, :live_view

  alias Playground.Settings
  import PlaygroundWeb.Components.Layout.PageLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok, site_settings} = Settings.get_site_settings()

    breadcrumbs = [
      %{label: "Admin", path: ~p"/admin"},
      %{label: "Site Settings", path: nil}
    ]

    {:ok,
     socket
     |> assign(:page_title, "Site Settings")
     |> assign(:breadcrumbs, breadcrumbs)
     |> assign(:site_settings, site_settings)
     |> assign(:form, to_form(Settings.change_site_settings(site_settings)))}
  end

  @impl true
  def handle_event("validate", %{"site_settings" => params}, socket) do
    changeset =
      socket.assigns.site_settings
      |> Settings.change_site_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"site_settings" => params}, socket) do
    case Settings.update_site_settings(params) do
      {:ok, site_settings} ->
        {:noreply,
         socket
         |> assign(:site_settings, site_settings)
         |> assign(:form, to_form(Settings.change_site_settings(site_settings)))
         |> put_flash(:info, "Site settings updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_layout>
      <div class="space-y-6">
        <p class="text-sm text-muted-foreground">
          Configure general settings for your site.
        </p>

        <div class="bg-card shadow rounded-lg border border-base overflow-hidden">
          <div class="px-4 py-4 border-b border-base bg-muted">
            <h2 class="text-lg font-semibold text-foreground">Branding</h2>
            <p class="text-sm text-muted-foreground mt-1">
              Customize how your site appears to users.
            </p>
          </div>

          <.form for={@form} phx-change="validate" phx-submit="save" class="p-6 space-y-6">
            <div class="max-w-xl space-y-6">
              <div>
                <.input
                  field={@form[:logo_url]}
                  type="text"
                  label="Logo URL"
                  placeholder="https://example.com/logo.svg or /images/logo.svg"
                />
                <p class="mt-1.5 text-sm text-muted-foreground">
                  Enter a URL to your logo image. This will appear in the sidebar and on authentication pages.
                  Use an SVG for best results as it will adapt to light and dark themes.
                </p>
              </div>

              <%= if @form[:logo_url].value && @form[:logo_url].value != "" do %>
                <div class="space-y-2">
                  <p class="text-sm font-medium text-foreground">Preview</p>
                  <div class="flex items-center gap-4">
                    <div class="flex flex-col items-center gap-1">
                      <div class="p-4 bg-white rounded-lg border border-zinc-200">
                        <img
                          src={@form[:logo_url].value}
                          alt="Logo preview (light)"
                          class="h-8 w-auto invert"
                          onerror="this.style.display='none'"
                        />
                      </div>
                      <span class="text-xs text-muted-foreground">Light mode</span>
                    </div>
                    <div class="flex flex-col items-center gap-1">
                      <div class="p-4 bg-zinc-900 rounded-lg border border-zinc-700">
                        <img
                          src={@form[:logo_url].value}
                          alt="Logo preview (dark)"
                          class="h-8 w-auto"
                          onerror="this.style.display='none'"
                        />
                      </div>
                      <span class="text-xs text-muted-foreground">Dark mode</span>
                    </div>
                  </div>
                  <p class="text-xs text-muted-foreground">
                    White logos are automatically inverted to black in light mode.
                  </p>
                </div>
              <% end %>
            </div>

            <div class="flex justify-end pt-4 border-t border-base">
              <.button type="submit" variant="solid">
                Save Settings
              </.button>
            </div>
          </.form>
        </div>
      </div>
    </.page_layout>
    """
  end
end
