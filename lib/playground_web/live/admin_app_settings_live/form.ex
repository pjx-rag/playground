defmodule PlaygroundWeb.AdminAppSettingsLive.Form do
  @moduledoc """
  LiveView for creating and editing app settings.
  """

  use PlaygroundWeb, :live_view

  alias Playground.Settings
  alias Playground.Settings.AppSetting

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    setting = %AppSetting{}

    breadcrumbs = [
      %{label: "Admin", path: ~p"/admin"},
      %{label: "App Settings", path: ~p"/admin/app-settings"},
      %{label: "New Setting", path: nil}
    ]

    socket
    |> assign(:page_title, "New Setting")
    |> assign(:breadcrumbs, breadcrumbs)
    |> assign(:setting, setting)
    |> assign(:form, to_form(Settings.change_app_setting(setting)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    setting = Settings.get_app_setting!(id)

    breadcrumbs = [
      %{label: "Admin", path: ~p"/admin"},
      %{label: "App Settings", path: ~p"/admin/app-settings"},
      %{label: "Edit Setting", path: nil}
    ]

    socket
    |> assign(:page_title, "Edit Setting")
    |> assign(:breadcrumbs, breadcrumbs)
    |> assign(:setting, setting)
    |> assign(:form, to_form(Settings.change_app_setting(setting)))
  end

  @impl true
  def handle_event("validate", %{"app_setting" => params}, socket) do
    changeset =
      socket.assigns.setting
      |> Settings.change_app_setting(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"app_setting" => params}, socket) do
    save_setting(socket, socket.assigns.live_action, params)
  end

  defp save_setting(socket, :new, params) do
    case Settings.create_app_setting(params) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> put_flash(:info, "Setting created successfully")
         |> push_navigate(to: ~p"/admin/app-settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_setting(socket, :edit, params) do
    case Settings.update_app_setting(socket.assigns.setting, params) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> put_flash(:info, "Setting updated successfully")
         |> push_navigate(to: ~p"/admin/app-settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <h1 class="text-2xl text-foreground font-bold mb-8">
        {if @live_action == :new, do: "New App Setting", else: "Edit App Setting"}
      </h1>

      <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-10">
        <section>
          <h2 class="text-xl font-semibold text-foreground mb-4">Setting Details</h2>
          <p class="text-sm text-muted-foreground mb-6">
            App settings are key-value pairs used to configure application behavior.
            Use lowercase keys with underscores (e.g., <code class="font-mono bg-muted px-1 rounded">ai_default_model</code>).
          </p>

          <div class="space-y-6">
            <.input
              field={@form[:key]}
              type="text"
              label="Key"
              placeholder="e.g., ai_default_model"
              disabled={@live_action == :edit}
              required
            />

            <p :if={@live_action == :edit} class="text-sm text-muted-foreground -mt-4">
              Keys cannot be changed after creation. To use a different key, delete this setting and create a new one.
            </p>

            <div class="space-y-1.5">
              <label class="block text-sm font-medium text-foreground">
                Value
              </label>
              <textarea
                name={@form[:value].name}
                id={@form[:value].id}
                placeholder="Enter the setting value"
                rows="8"
                class="w-full px-3 py-2 rounded-md border border-base bg-card text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/50 focus:border-primary font-mono text-sm"
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:value].value)}</textarea>
              <p class="text-sm text-muted-foreground mt-1">
                Values can be strings, numbers, JSON objects, or any text-based configuration.
              </p>
              <.error :for={msg <- Enum.map(@form[:value].errors, &translate_error/1)}>{msg}</.error>
            </div>
          </div>
        </section>

        <div class="flex justify-end gap-3 pt-6 border-t border-base">
          <.button type="button" variant="outline" navigate={~p"/admin/app-settings"}>
            Cancel
          </.button>
          <.button type="submit" variant="solid" color="primary" phx-disable-with="Saving...">
            {if @live_action == :new, do: "Create Setting", else: "Save Changes"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
