defmodule PlaygroundWeb.AdminAppSettingsLive.Index do
  @moduledoc """
  Admin page for managing app settings (key-value store) with Flop integration.
  """
  use PlaygroundWeb, :live_view

  import Ecto.Query
  alias Playground.Settings
  alias Playground.Settings.AppSetting
  alias Playground.Repo
  import PlaygroundWeb.Components.AdminTable

  @impl true
  def mount(_params, _session, socket) do
    breadcrumbs = [
      %{label: "Admin", path: ~p"/admin"},
      %{label: "App Settings", path: nil}
    ]

    {:ok,
     socket
     |> assign(:page_title, "App Settings")
     |> assign(:breadcrumbs, breadcrumbs)
     |> assign(:setting_to_delete, nil)
     |> assign(:selected_ids, MapSet.new())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, load_results(socket, params)}
  end

  defp load_results(socket, params) do
    query = from(s in AppSetting)

    # Apply search filter
    query = apply_search_filter(query, params)

    case Flop.validate_and_run(query, params, for: AppSetting) do
      {:ok, {settings, meta}} ->
        meta = Map.put(meta, :params, params)

        socket
        |> assign(:settings, settings)
        |> assign(:meta, meta)

      {:error, meta} ->
        socket
        |> assign(:settings, [])
        |> assign(:meta, meta)
    end
  end

  defp apply_search_filter(query, %{"search" => search}) when search != "" do
    search_term = "%#{search}%"
    from s in query, where: ilike(s.key, ^search_term) or ilike(s.value, ^search_term)
  end

  defp apply_search_filter(query, _), do: query

  @impl true
  def handle_event("update-filter", params, socket) do
    existing_params = Map.get(socket.assigns.meta, :params, %{})

    filter_params =
      existing_params
      |> update_if_changed(params, "search")

    if filter_params != existing_params do
      {:noreply, push_patch(socket, to: ~p"/admin/app-settings?#{filter_params}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear-filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/app-settings")}
  end

  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    existing_params = Map.get(socket.assigns.meta, :params, %{})
    new_params = Map.put(existing_params, "page_size", page_size) |> Map.delete("page")
    {:noreply, push_patch(socket, to: ~p"/admin/app-settings?#{new_params}")}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected_ids =
      if MapSet.member?(socket.assigns.selected_ids, id) do
        MapSet.delete(socket.assigns.selected_ids, id)
      else
        MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, :selected_ids, selected_ids)}
  end

  def handle_event("select_all_page", _params, socket) do
    all_ids = Enum.map(socket.assigns.settings, & &1.id) |> MapSet.new()

    selected_ids =
      if MapSet.equal?(socket.assigns.selected_ids, all_ids) do
        MapSet.new()
      else
        all_ids
      end

    {:noreply, assign(socket, :selected_ids, selected_ids)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  def handle_event("open_bulk_delete", _params, socket) do
    {:noreply, Fluxon.open_dialog(socket, "bulk-delete-modal")}
  end

  def handle_event("confirm_bulk_delete", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_ids)

    settings =
      from(s in AppSetting, where: s.id in ^selected_ids)
      |> Repo.all()

    deleted_count =
      Enum.reduce(settings, 0, fn setting, acc ->
        case Settings.delete_app_setting(setting) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

    socket =
      socket
      |> put_flash(:info, "Successfully deleted #{deleted_count} setting(s)")
      |> assign(:selected_ids, MapSet.new())
      |> Fluxon.close_dialog("bulk-delete-modal")
      |> load_results(socket.assigns.meta.params)

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    setting = Settings.get_app_setting!(id)

    {:noreply,
     socket
     |> assign(:setting_to_delete, setting)
     |> Fluxon.open_dialog("delete-modal")}
  end

  def handle_event("confirm_delete", _params, socket) do
    if socket.assigns.setting_to_delete do
      case Settings.delete_app_setting(socket.assigns.setting_to_delete) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Setting deleted successfully")
           |> Fluxon.close_dialog("delete-modal")
           |> assign(:setting_to_delete, nil)
           |> load_results(socket.assigns.meta.params)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Could not delete setting")
           |> Fluxon.close_dialog("delete-modal")
           |> assign(:setting_to_delete, nil)}
      end
    else
      {:noreply, socket}
    end
  end

  # Helper functions
  defp update_if_changed(existing, new_params, key) do
    case Map.get(new_params, key) do
      nil -> existing
      "" -> Map.delete(existing, key)
      value -> Map.put(existing, key, value)
    end
  end

  defp has_active_filters?(meta) do
    params = Map.get(meta, :params, %{})

    Enum.any?(params, fn
      {"search", value} -> value != ""
      _ -> false
    end)
  end

  defp get_filter_value(meta, key) do
    case meta do
      %{params: params} when is_map(params) -> Map.get(params, key, "")
      _ -> ""
    end
  end

  defp get_page_size(meta) do
    case meta do
      %{flop: %{page_size: page_size}} when is_integer(page_size) -> to_string(page_size)
      %{params: %{"page_size" => page_size}} -> page_size
      _ -> "25"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mb-4 p-4 bg-warning/10 border border-warning/30 rounded-lg flex items-start gap-3">
      <.icon name="hero-exclamation-triangle" class="size-5 text-warning flex-shrink-0 mt-0.5" />
      <div class="text-sm text-foreground">
        <span class="font-medium">Caution:</span>
        Deleting app settings may break application functionality. Only modify these values if you understand their purpose.
      </div>
    </div>

    <div class="bg-card border border-base shadow-sm rounded-lg overflow-hidden flex-1 flex flex-col min-h-0">
      <.admin_table
        id="app-settings-table"
        rows={@settings}
        meta={@meta}
        path={~p"/admin/app-settings"}
        selected_ids={@selected_ids}
        show_checkboxes={true}
        title="App Settings"
      >
        <:header_action>
          <.button variant="solid" color="primary" size="sm" navigate={~p"/admin/app-settings/new"}>
            <.icon name="hero-plus" class="size-4 mr-2" />
            New Setting
          </.button>
        </:header_action>

        <:toolbar>
          <.form for={%{}} phx-change="update-filter" class="flex items-center gap-3">
            <div class="flex-1">
              <.input
                type="text"
                name="search"
                value={get_filter_value(@meta, "search")}
                placeholder="Search by key or value..."
                phx-debounce="300"
              />
            </div>

            <div class="relative">
              <.button
                type="button"
                variant="outline"
                size="sm"
                phx-click={JS.toggle(to: "#filters-dropdown")}
              >
                <.icon name="hero-funnel" class="size-4 mr-2" />
                Filters
                <%= if has_active_filters?(@meta) do %>
                  <.badge color="primary" class="ml-2">1</.badge>
                <% end %>
              </.button>

              <div
                id="filters-dropdown"
                phx-click-away={JS.hide(to: "#filters-dropdown")}
                class="hidden absolute right-0 top-full mt-2 w-72 bg-overlay border border-base rounded-base shadow-lg p-4 z-50"
              >
                <div class="flex items-center justify-between mb-4">
                  <h3 class="text-base font-semibold text-foreground">Filters</h3>
                  <%= if has_active_filters?(@meta) do %>
                    <.button
                      type="button"
                      variant="ghost"
                      size="sm"
                      phx-click={
                        JS.dispatch("reset", to: "form")
                        |> JS.push("clear-filters")
                        |> JS.hide(to: "#filters-dropdown")
                      }
                    >
                      <.icon name="hero-x-mark" class="size-4 mr-1" />
                      Clear
                    </.button>
                  <% end %>
                </div>

                <div class="space-y-4">
                  <div>
                    <.label>Rows per page</.label>
                    <.select
                      name="page_size"
                      value={get_page_size(@meta)}
                      phx-change="change_page_size"
                      options={[
                        {"10", "10"},
                        {"25", "25"},
                        {"50", "50"},
                        {"100", "100"}
                      ]}
                    />
                  </div>
                </div>
              </div>
            </div>
          </.form>
        </:toolbar>

        <:col :let={setting} label="Key" field={:key} sortable>
          <span class="font-mono text-sm text-foreground">{setting.key}</span>
        </:col>

        <:col :let={setting} label="Value" field={:value} sortable>
          <span class="text-foreground-soft max-w-md truncate block">{setting.value || "-"}</span>
        </:col>

        <:col :let={setting} label="Updated" field={:updated_at} sortable>
          <span class="text-muted-foreground text-sm">
            {Calendar.strftime(setting.updated_at, "%b %d, %Y %H:%M")}
          </span>
        </:col>

        <:bulk_action label="Delete Selected" icon="hero-trash" event="open_bulk_delete" />

        <:row_action :let={setting}>
          <.dropdown placement="bottom-end">
            <:toggle>
              <.button variant="ghost" size="sm">
                <.icon name="hero-ellipsis-vertical" class="size-4" />
              </.button>
            </:toggle>
            <.dropdown_link navigate={~p"/admin/app-settings/#{setting}/edit"}>
              <.icon name="hero-pencil" class="size-4 mr-2" />
              Edit
            </.dropdown_link>
            <.dropdown_separator />
            <.dropdown_button
              phx-click="delete"
              phx-value-id={setting.id}
              class="text-danger"
            >
              <.icon name="hero-trash" class="size-4 mr-2" />
              Delete
            </.dropdown_button>
          </.dropdown>
        </:row_action>
      </.admin_table>

      <!-- Empty state -->
      <%= if length(@settings) == 0 do %>
        <div class="text-center py-12">
          <.icon name="hero-adjustments-horizontal" class="mx-auto h-12 w-12 text-muted-foreground" />
          <h3 class="mt-2 text-sm font-medium text-foreground">No settings found</h3>
          <p class="mt-1 text-sm text-muted-foreground">
            <%= if has_active_filters?(@meta) do %>
              Try adjusting your search terms.
            <% else %>
              Get started by creating a new setting.
            <% end %>
          </p>
          <div class="mt-6">
            <.button variant="solid" navigate={~p"/admin/app-settings/new"}>
              <.icon name="hero-plus" class="size-4 mr-2" />
              New Setting
            </.button>
          </div>
        </div>
      <% end %>
    </div>

    <!-- Delete Confirmation Modal -->
    <.modal id="delete-modal" class="max-w-md w-full">
      <h3 class="text-base font-semibold leading-6 text-foreground mb-4">
        Delete Setting
      </h3>

      <%= if @setting_to_delete do %>
        <p class="text-sm text-muted-foreground">
          Are you sure you want to delete the setting <strong class="font-mono">{@setting_to_delete.key}</strong>?
          This action cannot be undone.
        </p>
      <% end %>

      <div class="flex justify-end gap-3 mt-6">
        <.button
          variant="outline"
          phx-click={Fluxon.close_dialog("delete-modal")}
        >
          Cancel
        </.button>
        <.button
          variant="solid"
          color="danger"
          phx-click="confirm_delete"
        >
          Delete
        </.button>
      </div>
    </.modal>

    <!-- Bulk Delete Confirmation Modal -->
    <.modal id="bulk-delete-modal" class="max-w-md w-full">
      <h3 class="text-base font-semibold leading-6 text-foreground mb-4">
        Delete Multiple Settings
      </h3>

      <p class="text-sm text-muted-foreground">
        Are you sure you want to delete <strong>{MapSet.size(@selected_ids)}</strong> setting(s)?
        This action cannot be undone.
      </p>

      <div class="flex justify-end gap-3 mt-6">
        <.button
          variant="outline"
          phx-click={Fluxon.close_dialog("bulk-delete-modal")}
        >
          Cancel
        </.button>
        <.button
          variant="solid"
          color="danger"
          phx-click="confirm_bulk_delete"
        >
          Delete All
        </.button>
      </div>
    </.modal>
    """
  end
end
