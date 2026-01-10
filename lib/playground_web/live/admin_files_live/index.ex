defmodule PlaygroundWeb.AdminFilesLive.Index do
  @moduledoc """
  Admin page for viewing all synced files across connected data sources.
  """
  use PlaygroundWeb, :live_view

  import Ecto.Query
  import PlaygroundWeb.Components.AdminTable

  alias Playground.Repo
  alias Playground.Files.File
  alias Playground.Organizations

  @impl true
  def mount(_params, _session, socket) do
    breadcrumbs = [
      %{label: "Admin", path: ~p"/admin"},
      %{label: "Files", path: nil}
    ]

    connectors = get_user_connectors(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Files")
     |> assign(:breadcrumbs, breadcrumbs)
     |> assign(:connectors, connectors)
     |> assign(:selected_ids, MapSet.new())
     |> load_results(%{})}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, load_results(socket, params)}
  end

  defp load_results(socket, params) do
    user = socket.assigns.current_user
    org = Organizations.get_user_organization(user)
    connector_org_ids = get_connector_org_ids(org.id)

    # Base query: all files for user's organization (excluding deleted and folders)
    # Include chunks count as aggregate
    query =
      from(f in File,
        where: f.connector_organization_id in ^connector_org_ids,
        where: f.sync_status != "deleted",
        where: f.mime_type != "application/vnd.google-apps.folder",
        left_join: c in assoc(f, :chunks),
        group_by: f.id,
        select_merge: %{chunks_count: count(c.id)},
        preload: [connector_organization: :connector]
      )

    query = apply_search_filter(query, params)
    query = apply_connector_filter(query, params)
    query = apply_status_filter(query, params)

    case Flop.validate_and_run(query, params, for: File) do
      {:ok, {files, meta}} ->
        meta = Map.put(meta, :params, params)

        socket
        |> assign(:files, files)
        |> assign(:meta, meta)

      {:error, meta} ->
        socket
        |> assign(:files, [])
        |> assign(:meta, meta)
    end
  end

  defp apply_search_filter(query, %{"search" => search}) when search != "" do
    search_term = "%#{search}%"
    from f in query, where: ilike(f.name, ^search_term)
  end

  defp apply_search_filter(query, _), do: query

  defp apply_connector_filter(query, %{"connector" => connector_id}) when connector_id != "" do
    from f in query, where: f.connector_organization_id == ^connector_id
  end

  defp apply_connector_filter(query, _), do: query

  defp apply_status_filter(query, %{"status" => status}) when status != "" do
    from f in query, where: f.sync_status == ^status
  end

  defp apply_status_filter(query, _), do: query

  defp get_user_connectors(user) do
    org = Organizations.get_user_organization(user)

    from(co in Playground.Connectors.ConnectorOrganization,
      where: co.organization_id == ^org.id,
      preload: [:connector]
    )
    |> Repo.all()
  end

  defp get_connector_org_ids(organization_id) do
    from(co in Playground.Connectors.ConnectorOrganization,
      where: co.organization_id == ^organization_id,
      select: co.id
    )
    |> Repo.all()
  end

  @impl true
  def handle_event("update-filter", params, socket) do
    existing_params = Map.get(socket.assigns.meta, :params, %{})

    filter_params =
      existing_params
      |> update_if_changed(params, "search")
      |> update_if_changed(params, "connector")
      |> update_if_changed(params, "status")

    if filter_params != existing_params do
      {:noreply, push_patch(socket, to: ~p"/admin/files?#{filter_params}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear-filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/files")}
  end

  @impl true
  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    existing_params = Map.get(socket.assigns.meta, :params, %{})
    new_params = Map.put(existing_params, "page_size", page_size) |> Map.delete("page")
    {:noreply, push_patch(socket, to: ~p"/admin/files?#{new_params}")}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected_ids =
      if MapSet.member?(socket.assigns.selected_ids, id) do
        MapSet.delete(socket.assigns.selected_ids, id)
      else
        MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, :selected_ids, selected_ids)}
  end

  @impl true
  def handle_event("select_all_page", _params, socket) do
    all_ids = Enum.map(socket.assigns.files, & &1.id) |> MapSet.new()

    selected_ids =
      if MapSet.equal?(socket.assigns.selected_ids, all_ids) do
        MapSet.new()
      else
        all_ids
      end

    {:noreply, assign(socket, :selected_ids, selected_ids)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  @impl true
  def handle_event("bulk_mark_synced", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_ids)

    if length(selected_ids) > 0 do
      {count, _} = Playground.Files.bulk_update_sync_status(selected_ids, "synced")

      {:noreply,
       socket
       |> put_flash(:info, "#{count} file(s) marked as synced")
       |> assign(:selected_ids, MapSet.new())
       |> load_results(Map.get(socket.assigns.meta, :params, %{}))}
    else
      {:noreply, put_flash(socket, :error, "No files selected")}
    end
  end

  @impl true
  def handle_event("bulk_mark_unsynced", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_ids)

    if length(selected_ids) > 0 do
      {count, _} = Playground.Files.bulk_update_sync_status(selected_ids, "unsynced")

      {:noreply,
       socket
       |> put_flash(:info, "#{count} file(s) marked as unsynced")
       |> assign(:selected_ids, MapSet.new())
       |> load_results(Map.get(socket.assigns.meta, :params, %{}))}
    else
      {:noreply, put_flash(socket, :error, "No files selected")}
    end
  end

  @impl true
  def handle_event("bulk_chunk_files", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_ids)

    if length(selected_ids) > 0 do
      case Playground.Files.sync_and_process_files(selected_ids) do
        {:ok, count} ->
          {:noreply,
           socket
           |> put_flash(:info, "#{count} file(s) queued for chunking")
           |> assign(:selected_ids, MapSet.new())
           |> load_results(Map.get(socket.assigns.meta, :params, %{}))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to queue files: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "No files selected")}
    end
  end

  @impl true
  def handle_event("chunk_file", %{"id" => id}, socket) do
    file_id = String.to_integer(id)

    case Playground.Files.sync_and_process_files([file_id]) do
      {:ok, _count} ->
        {:noreply,
         socket
         |> put_flash(:info, "File queued for chunking")
         |> load_results(Map.get(socket.assigns.meta, :params, %{}))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue file: #{inspect(reason)}")}
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
      {"connector", value} -> value != ""
      {"status", value} -> value != ""
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
      _ -> "50"
    end
  end

  defp get_total_count(meta) do
    case meta do
      %{total_count: count} when is_integer(count) -> count
      _ -> 0
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-card border border-base shadow-sm rounded-lg overflow-hidden flex-1 flex flex-col min-h-0">
      <.admin_table
        id="files-table"
        rows={@files}
        meta={@meta}
        path={~p"/admin/files"}
        selected_ids={@selected_ids}
        show_checkboxes={true}
        title="Files"
      >
        <:bulk_action label="Mark Synced" icon="hero-check-circle" event="bulk_mark_synced" />
        <:bulk_action label="Mark Unsynced" icon="hero-minus-circle" event="bulk_mark_unsynced" />
        <:bulk_action label="Chunk Files" icon="hero-squares-2x2" event="bulk_chunk_files" />

        <:toolbar>
          <.form for={%{}} phx-change="update-filter" class="flex items-center gap-3">
            <div class="flex-1">
              <.input
                type="text"
                name="search"
                value={get_filter_value(@meta, "search")}
                placeholder="Search files..."
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
                  <.badge color="primary" class="ml-2">!</.badge>
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
                    <.label>Source</.label>
                    <.select
                      clearable
                      name="connector"
                      value={get_filter_value(@meta, "connector")}
                      options={Enum.map(@connectors, &{&1.connector.name, to_string(&1.id)})}
                      placeholder="All sources"
                    />
                  </div>

                  <div>
                    <.label>Status</.label>
                    <.select
                      clearable
                      name="status"
                      value={get_filter_value(@meta, "status")}
                      options={[
                        {"Synced", "synced"},
                        {"Unsynced", "unsynced"}
                      ]}
                      placeholder="All statuses"
                    />
                  </div>

                  <div>
                    <.label>Rows per page</.label>
                    <.select
                      name="page_size"
                      value={get_page_size(@meta)}
                      phx-change="change_page_size"
                      options={[
                        {"25", "25"},
                        {"50", "50"},
                        {"100", "100"},
                        {"200", "200"}
                      ]}
                    />
                  </div>
                </div>
              </div>
            </div>
          </.form>

          <div class="text-sm text-muted-foreground ml-4">
            <span class="font-semibold text-foreground"><%= get_total_count(@meta) %></span> files
          </div>
        </:toolbar>

        <:col :let={file} label="File" field={:name} sortable td_class="max-w-md">
          <div class="flex items-center gap-3">
            <.file_icon mime_type={file.mime_type} />
            <span class="truncate"><%= file.name %></span>
          </div>
        </:col>

        <:col :let={file} label="Source">
          <span class="text-muted-foreground">
            <%= file.connector_organization.connector.name %>
          </span>
        </:col>

        <:col :let={file} label="Status" field={:sync_status} sortable>
          <.status_badge status={file.sync_status} />
        </:col>

        <:col :let={file} label="Size" field={:size_bytes} sortable>
          <span class="text-muted-foreground font-mono text-sm">
            <%= format_file_size(file.size_bytes) %>
          </span>
        </:col>

        <:col :let={file} label="Synced" field={:synced_at} sortable>
          <time
            datetime={file.synced_at}
            title={file.synced_at && DateTime.to_string(file.synced_at)}
            class="text-muted-foreground"
          >
            <%= format_relative_time(file.synced_at) %>
          </time>
        </:col>

        <:col :let={file} label="Chunks">
          <%= if Map.get(file, :chunks_count, 0) > 0 do %>
            <.badge color="success"><%= file.chunks_count %></.badge>
          <% else %>
            <span class="text-muted-foreground">-</span>
          <% end %>
        </:col>

        <:row_action :let={file}>
          <%= if file.sync_status == "synced" do %>
            <button
              type="button"
              phx-click="chunk_file"
              phx-value-id={file.id}
              class="text-muted-foreground hover:text-foreground"
              title="Chunk this file"
            >
              <.icon name="hero-squares-2x2" class="size-4" />
            </button>
          <% end %>
          <%= if file.metadata["webViewLink"] do %>
            <a
              href={file.metadata["webViewLink"]}
              target="_blank"
              class="text-muted-foreground hover:text-foreground"
              title="Open in source"
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-4" />
            </a>
          <% end %>
        </:row_action>
      </.admin_table>

      <!-- Empty state -->
      <%= if length(@files) == 0 do %>
        <div class="text-center py-12">
          <.icon name="hero-document-duplicate" class="mx-auto h-12 w-12 text-muted-foreground" />
          <h3 class="mt-2 text-sm font-medium text-foreground">No synced files</h3>
          <p class="mt-1 text-sm text-muted-foreground">
            <%= if has_active_filters?(@meta) do %>
              Try adjusting your filters.
            <% else %>
              Connect a data source and select files to sync.
            <% end %>
          </p>
          <%= unless has_active_filters?(@meta) do %>
            <.link
              navigate={~p"/admin/connectors"}
              class="inline-flex items-center gap-2 mt-4 px-4 py-2 text-sm font-medium text-primary hover:text-primary/80 transition-colors"
            >
              <.icon name="hero-link" class="w-4 h-4" />
              Go to Connectors
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :mime_type, :string, required: true

  defp file_icon(%{mime_type: "application/vnd.google-apps.document"} = assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-md bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center flex-shrink-0">
      <.icon name="hero-document-text" class="w-4 h-4 text-blue-600 dark:text-blue-400" />
    </div>
    """
  end

  defp file_icon(%{mime_type: "application/vnd.google-apps.spreadsheet"} = assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-md bg-green-100 dark:bg-green-900/30 flex items-center justify-center flex-shrink-0">
      <.icon name="hero-table-cells" class="w-4 h-4 text-green-600 dark:text-green-400" />
    </div>
    """
  end

  defp file_icon(%{mime_type: "application/vnd.google-apps.presentation"} = assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-md bg-orange-100 dark:bg-orange-900/30 flex items-center justify-center flex-shrink-0">
      <.icon name="hero-presentation-chart-bar" class="w-4 h-4 text-orange-600 dark:text-orange-400" />
    </div>
    """
  end

  defp file_icon(%{mime_type: "application/pdf"} = assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-md bg-red-100 dark:bg-red-900/30 flex items-center justify-center flex-shrink-0">
      <.icon name="hero-document" class="w-4 h-4 text-red-600 dark:text-red-400" />
    </div>
    """
  end

  defp file_icon(%{mime_type: mime_type} = assigns) when is_binary(mime_type) do
    cond do
      String.starts_with?(mime_type, "image/") ->
        ~H"""
        <div class="w-8 h-8 rounded-md bg-purple-100 dark:bg-purple-900/30 flex items-center justify-center flex-shrink-0">
          <.icon name="hero-photo" class="w-4 h-4 text-purple-600 dark:text-purple-400" />
        </div>
        """

      String.starts_with?(mime_type, "video/") ->
        ~H"""
        <div class="w-8 h-8 rounded-md bg-pink-100 dark:bg-pink-900/30 flex items-center justify-center flex-shrink-0">
          <.icon name="hero-video-camera" class="w-4 h-4 text-pink-600 dark:text-pink-400" />
        </div>
        """

      true ->
        ~H"""
        <div class="w-8 h-8 rounded-md bg-muted flex items-center justify-center flex-shrink-0">
          <.icon name="hero-document" class="w-4 h-4 text-muted-foreground" />
        </div>
        """
    end
  end

  defp file_icon(assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-md bg-muted flex items-center justify-center flex-shrink-0">
      <.icon name="hero-document" class="w-4 h-4 text-muted-foreground" />
    </div>
    """
  end

  attr :status, :string, required: true

  defp status_badge(%{status: "synced"} = assigns) do
    ~H"""
    <.badge color="success">Synced</.badge>
    """
  end

  defp status_badge(%{status: "unsynced"} = assigns) do
    ~H"""
    <.badge color="info">Unsynced</.badge>
    """
  end

  defp status_badge(%{status: "deleted"} = assigns) do
    ~H"""
    <.badge color="danger">Deleted</.badge>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <.badge color="info"><%= @status %></.badge>
    """
  end

  defp format_file_size(nil), do: "-"
  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_file_size(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_file_size(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"

  defp format_relative_time(nil), do: "-"

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
