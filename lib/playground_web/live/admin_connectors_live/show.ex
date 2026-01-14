defmodule PlaygroundWeb.AdminConnectorsLive.Show do
  use PlaygroundWeb, :live_view

  alias Playground.Connectors
  alias Playground.Files
  alias Playground.ApiTokens.TokenManager
  alias Playground.Services.GoogleDrive

  import PlaygroundWeb.Components.Layout.PageLayout

  require Logger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    connector_org = Connectors.get_connector_organization!(id)

    breadcrumbs = [
      %{label: "Admin", path: ~p"/admin"},
      %{label: "Connectors", path: ~p"/admin/connectors"},
      %{label: connector_org.connector.name, path: nil}
    ]

    {:ok,
     socket
     |> assign(:page_title, connector_org.connector.name)
     |> assign(:breadcrumbs, breadcrumbs)
     |> assign(:connector_org, connector_org)
     |> assign(:loading, false)
     |> assign(:error, nil)
     |> assign(:files, [])
     |> assign(:expanded_folders, MapSet.new())
     |> assign(:folder_contents, %{})
     |> assign(:loading_folders, MapSet.new())
     # Track pending sync status changes: file_id => :sync | :unsync
     |> assign(:pending_changes, %{})
     # Track pending folder changes: folder_id => :sync | :unsync
     |> assign(:pending_folder_changes, %{})
     |> assign(:saving, false)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    # Load root files from API on page load
    socket =
      if connected?(socket) do
        load_root_files(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_folder", %{"folder_id" => folder_id}, socket) do
    expanded = socket.assigns.expanded_folders

    socket =
      if MapSet.member?(expanded, folder_id) do
        # Collapse folder
        assign(socket, :expanded_folders, MapSet.delete(expanded, folder_id))
      else
        # Expand folder - load contents if not already loaded
        socket = assign(socket, :expanded_folders, MapSet.put(expanded, folder_id))

        if Map.has_key?(socket.assigns.folder_contents, folder_id) do
          socket
        else
          load_folder_contents(socket, folder_id)
        end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_file_selection", %{"file_id" => file_id, "current_status" => current_status}, socket) do
    file_id = String.to_integer(file_id)
    pending_changes = socket.assigns.pending_changes

    # Toggle pending change based on current status
    # If already has pending change, remove it (revert to original)
    # If no pending change, add one (opposite of current status)
    pending_changes =
      if Map.has_key?(pending_changes, file_id) do
        Map.delete(pending_changes, file_id)
      else
        # Add opposite of current status
        new_status = if current_status == "synced", do: :unsync, else: :sync
        Map.put(pending_changes, file_id, new_status)
      end

    {:noreply, assign(socket, :pending_changes, pending_changes)}
  end

  @impl true
  def handle_event("toggle_folder_selection", %{"folder_id" => folder_id, "is_checked" => is_checked}, socket) do
    # Toggle pending changes for folder and all visible descendants
    # is_checked is the current display state (sync_status XOR pending change)
    folder_contents = socket.assigns.folder_contents
    pending_changes = socket.assigns.pending_changes
    pending_folder_changes = socket.assigns.pending_folder_changes

    # Determine new target state: if currently checked -> uncheck (unsync), if unchecked -> check (sync)
    new_action = if is_checked == "true", do: :unsync, else: :sync

    # Get all visible descendant IDs (folders and files already loaded)
    {descendant_folder_ids, descendant_file_ids} =
      get_visible_descendants(folder_id, folder_contents)

    # Get file sync statuses to determine if we need to add/remove pending changes
    all_folder_ids = [folder_id | descendant_folder_ids]

    # Update pending folder changes
    pending_folder_changes =
      Enum.reduce(all_folder_ids, pending_folder_changes, fn fid, acc ->
        # For folders, we just track the intent
        Map.put(acc, fid, new_action)
      end)

    # Update pending file changes based on their current sync status
    files_with_status = get_files_with_status(socket, descendant_file_ids)

    pending_changes =
      Enum.reduce(files_with_status, pending_changes, fn {file_id, current_status}, acc ->
        # Only add pending change if it would actually change the state
        target_status = if new_action == :sync, do: "synced", else: "unsynced"

        if current_status == target_status do
          # Already in desired state, remove any pending change
          Map.delete(acc, file_id)
        else
          # Need to change, add pending change
          Map.put(acc, file_id, new_action)
        end
      end)

    {:noreply,
     socket
     |> assign(:pending_changes, pending_changes)
     |> assign(:pending_folder_changes, pending_folder_changes)}
  end

  @impl true
  def handle_event("save_changes", _, socket) do
    connector_org = socket.assigns.connector_org
    pending_changes = socket.assigns.pending_changes
    pending_folder_changes = socket.assigns.pending_folder_changes

    socket = assign(socket, :saving, true)

    # First, recursively fetch all files for folders that need syncing
    folders_to_sync =
      pending_folder_changes
      |> Enum.filter(fn {_id, action} -> action == :sync end)
      |> Enum.map(fn {id, _} -> id end)

    socket =
      if length(folders_to_sync) > 0 do
        fetch_folders_recursively(socket, folders_to_sync)
      else
        socket
      end

    # Get file IDs from folders (after fetching)
    folder_file_changes =
      Enum.flat_map(pending_folder_changes, fn {folder_id, action} ->
        file_ids = Files.get_descendant_file_ids(connector_org.id, folder_id)
        Enum.map(file_ids, fn id -> {id, action} end)
      end)

    # Merge folder file changes with direct file changes (direct takes precedence)
    all_changes =
      folder_file_changes
      |> Map.new()
      |> Map.merge(pending_changes)

    # Split into sync and unsync
    {to_sync, to_unsync} =
      Enum.split_with(all_changes, fn {_id, action} -> action == :sync end)

    sync_ids = Enum.map(to_sync, fn {id, _} -> id end)
    unsync_ids = Enum.map(to_unsync, fn {id, _} -> id end)

    # Apply changes
    sync_count =
      if length(sync_ids) > 0 do
        case Files.bulk_update_sync_status(sync_ids, "synced") do
          {count, _} -> count
          _ -> 0
        end
      else
        0
      end

    unsync_count =
      if length(unsync_ids) > 0 do
        case Files.bulk_update_sync_status(unsync_ids, "unsynced") do
          {count, _} -> count
          _ -> 0
        end
      else
        0
      end

    total_changes = sync_count + unsync_count

    socket =
      socket
      |> assign(:saving, false)
      |> assign(:pending_changes, %{})
      |> assign(:pending_folder_changes, %{})
      |> refresh_all_files()

    socket =
      if total_changes > 0 do
        put_flash(socket, :info, "Saved #{total_changes} change(s)")
      else
        put_flash(socket, :info, "No changes to save")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("discard_changes", _, socket) do
    {:noreply,
     socket
     |> assign(:pending_changes, %{})
     |> assign(:pending_folder_changes, %{})}
  end


  @impl true
  def handle_event("refresh_files", _, socket) do
    socket =
      socket
      |> assign(:folder_contents, %{})
      |> assign(:expanded_folders, MapSet.new())
      |> load_root_files()

    {:noreply, socket}
  end

  @impl true
  def handle_event("reconnect", _, socket) do
    connector_org = socket.assigns.connector_org

    # Generate OAuth URL for reconnection
    case Playground.OAuth.create_state(socket.assigns.current_user.id, connector_org.connector_id) do
      {:ok, state_id} ->
        auth_url = GoogleDrive.authorize_url(state: state_id)
        {:noreply, redirect(socket, external: auth_url)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start reconnection. Please try again.")}
    end
  end

  # Private Functions

  defp load_root_files(socket) do
    connector_org = socket.assigns.connector_org

    socket = assign(socket, :loading, true)

    case get_access_token(connector_org) do
      {:ok, token} ->
        case GoogleDrive.list_files(token, []) do
          {:ok, %{files: remote_files}} ->
            files = process_files(socket, remote_files)

            socket
            |> assign(:loading, false)
            |> assign(:files, files)

          {:error, reason} ->
            Logger.error("Failed to fetch files from Google Drive: #{inspect(reason)}")

            socket
            |> assign(:loading, false)
            |> assign(:error, "Failed to load files from Google Drive")
        end

      {:error, reason} ->
        Logger.error("Failed to get access token: #{inspect(reason)}")

        socket
        |> assign(:loading, false)
        |> assign(:error, "Failed to authenticate with Google Drive. Please reconnect.")
    end
  end

  defp load_folder_contents(socket, folder_id) do
    # Mark folder as loading
    socket = assign(socket, :loading_folders, MapSet.put(socket.assigns.loading_folders, folder_id))

    # Always load from API for lazy loading
    load_folder_contents_from_api(socket, folder_id)
  end

  defp load_folder_contents_from_api(socket, folder_id) do
    connector_org = socket.assigns.connector_org

    case get_access_token(connector_org) do
      {:ok, token} ->
        case GoogleDrive.list_files(token, folder_id: folder_id) do
          {:ok, %{files: remote_files}} ->
            files = process_files(socket, remote_files)

            socket
            |> assign(:loading_folders, MapSet.delete(socket.assigns.loading_folders, folder_id))
            |> assign(:folder_contents, Map.put(socket.assigns.folder_contents, folder_id, files))

          {:error, _reason} ->
            socket
            |> assign(:loading_folders, MapSet.delete(socket.assigns.loading_folders, folder_id))
            |> put_flash(:error, "Failed to load folder contents")
        end

      {:error, _reason} ->
        socket
        |> assign(:loading_folders, MapSet.delete(socket.assigns.loading_folders, folder_id))
        |> put_flash(:error, "Failed to authenticate")
    end
  end

  defp refresh_all_files(socket) do
    # Reload root and all expanded folders
    socket = load_root_files(socket)

    Enum.reduce(socket.assigns.expanded_folders, socket, fn folder_id, acc ->
      case get_access_token(socket.assigns.connector_org) do
        {:ok, token} ->
          case GoogleDrive.list_files(token, folder_id: folder_id) do
            {:ok, %{files: remote_files}} ->
              files = process_files(acc, remote_files)
              assign(acc, :folder_contents, Map.put(acc.assigns.folder_contents, folder_id, files))

            _ ->
              acc
          end

        _ ->
          acc
      end
    end)
  end

  defp process_files(socket, remote_files) do
    # Upsert all files from Google Drive into our database
    Enum.each(remote_files, fn file_data ->
      # Get first parent folder ID (Google Drive files can have multiple parents)
      parent_folder_id = List.first(file_data.parents)

      Files.upsert_file(%{
        connector_organization_id: socket.assigns.connector_org.id,
        provider_file_id: file_data.id,
        parent_folder_id: parent_folder_id,
        name: file_data.name,
        mime_type: file_data.mime_type,
        size_bytes: file_data.size,
        metadata: file_data.metadata
      })
    end)

    # Load files from database with their sync status
    db_files = Files.list_files(socket.assigns.connector_org.id)

    # Create a map of provider_file_id -> database file
    db_files_map = Map.new(db_files, fn f -> {f.provider_file_id, f} end)

    # Merge remote files with database sync status
    remote_files
    |> Enum.map(fn remote_file ->
      db_file = Map.get(db_files_map, remote_file.id)

      Map.merge(remote_file, %{
        db_id: db_file && db_file.id,
        sync_status: (db_file && db_file.sync_status) || "unsynced"
      })
    end)
    |> Enum.sort_by(&(&1.mime_type == "application/vnd.google-apps.folder"), :desc)
  end

  defp get_access_token(connector_org) do
    TokenManager.get_valid_token("connector", connector_org.id)
  end

  # Recursively fetch all files for selected folders (called on bulk sync)
  defp fetch_folders_recursively(socket, folder_ids) do
    connector_org = socket.assigns.connector_org

    case get_access_token(connector_org) do
      {:ok, token} ->
        # Fetch all folders recursively
        Enum.each(folder_ids, fn folder_id ->
          fetch_folder_recursive(connector_org.id, token, folder_id)
        end)

        socket

      {:error, _reason} ->
        put_flash(socket, :error, "Failed to authenticate for folder sync")
    end
  end

  defp fetch_folder_recursive(connector_org_id, token, folder_id) do
    case GoogleDrive.list_files(token, folder_id: folder_id) do
      {:ok, %{files: files}} ->
        # Store all files in database
        Enum.each(files, fn file_data ->
          parent_folder_id = List.first(file_data.parents)

          Files.upsert_file(%{
            connector_organization_id: connector_org_id,
            provider_file_id: file_data.id,
            parent_folder_id: parent_folder_id,
            name: file_data.name,
            mime_type: file_data.mime_type,
            size_bytes: file_data.size,
            metadata: file_data.metadata
          })
        end)

        # Find folders and recursively fetch their contents
        folders =
          Enum.filter(files, fn f ->
            f.mime_type == "application/vnd.google-apps.folder"
          end)

        Enum.each(folders, fn folder ->
          fetch_folder_recursive(connector_org_id, token, folder.id)
        end)

      {:error, _reason} ->
        Logger.warning("Failed to fetch folder contents",
          connector_org_id: connector_org_id,
          folder_id: folder_id
        )
    end
  end

  # Get file IDs with their current sync status from loaded files
  defp get_files_with_status(socket, file_ids) do
    # Look through root files and folder contents to find files with matching db_ids
    all_files = socket.assigns.files ++ Enum.flat_map(socket.assigns.folder_contents, fn {_, files} -> files end)

    file_ids
    |> Enum.map(fn file_id ->
      file = Enum.find(all_files, fn f -> f.db_id == file_id end)
      {file_id, file && file.sync_status || "unsynced"}
    end)
  end

  # Determine effective checked state for a file (sync_status XOR pending change)
  defp file_is_checked?(file, pending_changes) do
    current_synced = file.sync_status == "synced"
    pending = Map.get(pending_changes, file.db_id)

    case pending do
      :sync -> true
      :unsync -> false
      nil -> current_synced
    end
  end

  # Determine effective checked state for a folder
  defp folder_is_checked?(folder_id, pending_folder_changes) do
    case Map.get(pending_folder_changes, folder_id) do
      :sync -> true
      :unsync -> false
      nil -> false  # Folders don't have inherent sync state, default unchecked
    end
  end

  # Get all visible descendants (folders and files that are already loaded in folder_contents)
  defp get_visible_descendants(folder_id, folder_contents) do
    get_visible_descendants_acc(folder_id, folder_contents, [], [])
  end

  defp get_visible_descendants_acc(folder_id, folder_contents, folder_acc, file_acc) do
    case Map.get(folder_contents, folder_id) do
      nil ->
        # Folder not expanded, no visible children
        {folder_acc, file_acc}

      children ->
        # Separate folders and files
        {child_folders, child_files} =
          Enum.split_with(children, fn child ->
            child.mime_type == "application/vnd.google-apps.folder"
          end)

        # Add child folder IDs
        child_folder_ids = Enum.map(child_folders, & &1.id)

        # Add child file IDs (only those with db_id)
        child_file_ids =
          child_files
          |> Enum.filter(& &1.db_id)
          |> Enum.map(& &1.db_id)

        folder_acc = folder_acc ++ child_folder_ids
        file_acc = file_acc ++ child_file_ids

        # Recursively get descendants from child folders
        Enum.reduce(child_folder_ids, {folder_acc, file_acc}, fn child_folder_id, {f_acc, fi_acc} ->
          get_visible_descendants_acc(child_folder_id, folder_contents, f_acc, fi_acc)
        end)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_layout>
      <div class="space-y-6">
        <!-- Connector Header Card -->
        <div class="bg-card border border-base rounded-xl p-6">
          <div class="flex items-center gap-4">
            <.connector_logo key={@connector_org.connector.key} />
            <div class="flex-1 min-w-0">
              <h1 class="text-xl font-semibold text-foreground">
                <%= @connector_org.connector.name %>
              </h1>
              <p class="text-sm text-muted-foreground mt-1">
                <%= if @connector_org.metadata["email"] do %>
                  Connected as <%= @connector_org.metadata["email"] %>
                <% else %>
                  Connected by <%= @connector_org.user.email %>
                <% end %>
              </p>
            </div>
            <div class="flex items-center gap-2">
              <.link
                navigate={~p"/admin/files?connector_id=#{@connector_org.id}"}
                class="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-foreground bg-card border border-base rounded-lg hover:bg-muted/50 transition-colors"
              >
                <.icon name="hero-document-text" class="w-4 h-4" />
                Files
              </.link>
              <button
                type="button"
                phx-click="refresh_files"
                class="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-foreground bg-card border border-base rounded-lg hover:bg-muted/50 transition-colors"
                disabled={@loading}
              >
                <.icon name="hero-arrow-path" class={if @loading, do: "w-4 h-4 animate-spin", else: "w-4 h-4"} />
                Refresh
              </button>
            </div>
          </div>
        </div>

        <!-- Error State -->
        <%= if @error do %>
          <div class="bg-danger/10 border border-danger/20 rounded-xl p-4 flex items-center gap-3">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-danger flex-shrink-0" />
            <div class="flex-1">
              <p class="text-sm font-medium text-danger">Connection Error</p>
              <p class="text-sm text-danger/80 mt-1"><%= @error %></p>
            </div>
            <.button
              type="button"
              phx-click="reconnect"
              variant="solid"
              color="danger"
              size="sm"
            >
              <.icon name="hero-arrow-path" class="w-4 h-4" />
              Reconnect
            </.button>
          </div>
        <% end %>

        <!-- Saving Overlay -->
        <%= if @saving do %>
          <div class="bg-primary/5 border border-primary/20 rounded-xl px-4 py-3 flex items-center gap-3">
            <div class="w-5 h-5 rounded-full border-2 border-primary border-t-transparent animate-spin"></div>
            <p class="text-sm text-foreground">Saving changes...</p>
          </div>
        <% end %>

        <!-- Loading State -->
        <%= if @loading do %>
          <div class="bg-card border border-base rounded-xl p-12">
            <div class="flex flex-col items-center justify-center text-center">
              <div class="w-12 h-12 rounded-full border-2 border-primary border-t-transparent animate-spin"></div>
              <p class="mt-4 text-sm text-muted-foreground">Loading files...</p>
            </div>
          </div>
        <% else %>
          <!-- Pending Changes Bar -->
          <% has_pending_changes = map_size(@pending_changes) > 0 or map_size(@pending_folder_changes) > 0 %>
          <%= if has_pending_changes do %>
            <div class="bg-warning/10 border border-warning/30 rounded-xl px-4 py-3 flex items-center justify-between">
              <p class="text-sm text-foreground">
                <span class="font-semibold"><%= map_size(@pending_changes) + map_size(@pending_folder_changes) %></span> pending change(s)
              </p>
              <div class="flex items-center gap-2">
                <.button
                  type="button"
                  phx-click="discard_changes"
                  variant="ghost"
                  size="sm"
                >
                  Discard
                </.button>
                <.button
                  type="button"
                  phx-click="save_changes"
                  variant="solid"
                  color="primary"
                  size="sm"
                  disabled={@saving}
                >
                  <.icon name="hero-check" class="w-4 h-4" />
                  Save Changes
                </.button>
              </div>
            </div>
          <% end %>

          <!-- Files Tree -->
          <div class="bg-card border border-base rounded-xl overflow-hidden">
            <div class="divide-y divide-base">
              <%= if length(@files) == 0 do %>
                <div class="p-12 text-center">
                  <div class="flex items-center justify-center w-16 h-16 mx-auto rounded-full bg-muted mb-4">
                    <.icon name="hero-folder-open" class="w-8 h-8 text-muted-foreground" />
                  </div>
                  <p class="text-foreground font-medium">No files found</p>
                  <p class="text-sm text-muted-foreground mt-1">Your Google Drive root folder appears to be empty</p>
                </div>
              <% else %>
                <%= for file <- @files do %>
                  <.file_row
                    file={file}
                    depth={0}
                    connector_org_id={@connector_org.id}
                    expanded_folders={@expanded_folders}
                    folder_contents={@folder_contents}
                    loading_folders={@loading_folders}
                    pending_changes={@pending_changes}
                    pending_folder_changes={@pending_folder_changes}
                  />
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </.page_layout>
    """
  end

  attr :file, :map, required: true
  attr :depth, :integer, required: true
  attr :connector_org_id, :integer, required: true
  attr :expanded_folders, :any, required: true
  attr :folder_contents, :map, required: true
  attr :loading_folders, :any, required: true
  attr :pending_changes, :map, required: true
  attr :pending_folder_changes, :map, required: true

  defp file_row(assigns) do
    is_folder = assigns.file.mime_type == "application/vnd.google-apps.folder"
    is_expanded = MapSet.member?(assigns.expanded_folders, assigns.file.id)
    is_loading = MapSet.member?(assigns.loading_folders, assigns.file.id)
    children = Map.get(assigns.folder_contents, assigns.file.id, [])

    # Determine checked state based on sync_status + pending changes
    is_checked =
      if is_folder do
        folder_is_checked?(assigns.file.id, assigns.pending_folder_changes)
      else
        file_is_checked?(assigns.file, assigns.pending_changes)
      end

    # Check if this item has a pending change (for visual indicator)
    has_pending_change =
      if is_folder do
        Map.has_key?(assigns.pending_folder_changes, assigns.file.id)
      else
        Map.has_key?(assigns.pending_changes, assigns.file.db_id)
      end

    assigns =
      assigns
      |> assign(:is_folder, is_folder)
      |> assign(:is_expanded, is_expanded)
      |> assign(:is_loading, is_loading)
      |> assign(:children, children)
      |> assign(:is_checked, is_checked)
      |> assign(:has_pending_change, has_pending_change)

    ~H"""
    <div>
      <div
        class="group flex items-center gap-3 px-4 py-2.5 hover:bg-muted/30 transition-colors"
        style={"padding-left: #{16 + @depth * 24}px"}
      >
        <!-- Expand/Collapse for folders -->
        <div class="w-6 flex-shrink-0 flex items-center justify-center">
          <%= if @is_folder do %>
            <button
              type="button"
              phx-click="toggle_folder"
              phx-value-folder_id={@file.id}
              class="p-0.5 rounded hover:bg-muted transition-colors"
            >
              <%= if @is_loading do %>
                <.icon name="hero-arrow-path" class="w-4 h-4 text-muted-foreground animate-spin" />
              <% else %>
                <.icon
                  name={if @is_expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
                  class="w-4 h-4 text-muted-foreground"
                />
              <% end %>
            </button>
          <% else %>
            <div class="w-4"></div>
          <% end %>
        </div>

        <!-- Checkbox (for both files and folders) - represents sync status -->
        <div class="w-5 flex-shrink-0 flex items-center justify-center">
          <%= if @is_folder do %>
            <button
              type="button"
              phx-click="toggle_folder_selection"
              phx-value-folder_id={@file.id}
              phx-value-is_checked={to_string(@is_checked)}
              class={"w-4 h-4 rounded border flex items-center justify-center transition-colors hover:border-primary #{if @is_checked, do: "border-primary bg-primary", else: "border-base"} #{if @has_pending_change, do: "ring-2 ring-warning/50", else: ""}"}
            >
              <%= if @is_checked do %>
                <.icon name="hero-check-mini" class="w-3 h-3 text-white" />
              <% end %>
            </button>
          <% else %>
            <%= if @file.db_id do %>
              <button
                type="button"
                phx-click="toggle_file_selection"
                phx-value-file_id={@file.db_id}
                phx-value-current_status={@file.sync_status}
                class={"w-4 h-4 rounded border flex items-center justify-center transition-colors hover:border-primary #{if @is_checked, do: "border-primary bg-primary", else: "border-base"} #{if @has_pending_change, do: "ring-2 ring-warning/50", else: ""}"}
              >
                <%= if @is_checked do %>
                  <.icon name="hero-check-mini" class="w-3 h-3 text-white" />
                <% end %>
              </button>
            <% end %>
          <% end %>
        </div>

        <!-- Icon -->
        <div class="flex-shrink-0">
          <.file_icon mime_type={@file.mime_type} expanded={@is_expanded} />
        </div>

        <!-- Name -->
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-foreground truncate"><%= @file.name %></p>
        </div>

        <!-- Actions -->
        <div class="flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
          <%= if @file.metadata[:web_view_link] do %>
            <a
              href={@file.metadata[:web_view_link]}
              target="_blank"
              class="inline-flex items-center justify-center w-7 h-7 rounded-lg text-muted-foreground hover:text-foreground hover:bg-muted/50 transition-colors"
              title="Open in Google Drive"
            >
              <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
            </a>
          <% end %>
        </div>
      </div>

      <!-- Children (if expanded) -->
      <%= if @is_folder and @is_expanded and length(@children) > 0 do %>
        <%= for child <- @children do %>
          <.file_row
            file={child}
            depth={@depth + 1}
            connector_org_id={@connector_org_id}
            expanded_folders={@expanded_folders}
            folder_contents={@folder_contents}
            loading_folders={@loading_folders}
            pending_changes={@pending_changes}
            pending_folder_changes={@pending_folder_changes}
          />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :key, :string, required: true

  defp connector_logo(%{key: "google_drive"} = assigns) do
    ~H"""
    <div class="w-12 h-12 relative flex-shrink-0">
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
    <div class="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center flex-shrink-0">
      <.icon name="hero-cloud" class="w-6 h-6 text-primary" />
    </div>
    """
  end

  attr :mime_type, :string, required: true
  attr :expanded, :boolean, default: false

  defp file_icon(%{mime_type: "application/vnd.google-apps.folder"} = assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-md bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center">
      <.icon name={if @expanded, do: "hero-folder-open", else: "hero-folder"} class="w-4 h-4 text-amber-600 dark:text-amber-400" />
    </div>
    """
  end

  defp file_icon(%{mime_type: "application/vnd.google-apps.document"} = assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-md bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center">
      <.icon name="hero-document-text" class="w-4 h-4 text-blue-600 dark:text-blue-400" />
    </div>
    """
  end

  defp file_icon(%{mime_type: "application/vnd.google-apps.spreadsheet"} = assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-md bg-green-100 dark:bg-green-900/30 flex items-center justify-center">
      <.icon name="hero-table-cells" class="w-4 h-4 text-green-600 dark:text-green-400" />
    </div>
    """
  end

  defp file_icon(%{mime_type: "application/vnd.google-apps.presentation"} = assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-md bg-orange-100 dark:bg-orange-900/30 flex items-center justify-center">
      <.icon name="hero-presentation-chart-bar" class="w-4 h-4 text-orange-600 dark:text-orange-400" />
    </div>
    """
  end

  defp file_icon(%{mime_type: "application/pdf"} = assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-md bg-red-100 dark:bg-red-900/30 flex items-center justify-center">
      <.icon name="hero-document" class="w-4 h-4 text-red-600 dark:text-red-400" />
    </div>
    """
  end

  defp file_icon(%{mime_type: mime_type} = assigns) when is_binary(mime_type) do
    cond do
      String.starts_with?(mime_type, "image/") ->
        ~H"""
        <div class="w-8 h-8 rounded-md bg-purple-100 dark:bg-purple-900/30 flex items-center justify-center">
          <.icon name="hero-photo" class="w-4 h-4 text-purple-600 dark:text-purple-400" />
        </div>
        """

      String.starts_with?(mime_type, "video/") ->
        ~H"""
        <div class="w-8 h-8 rounded-md bg-pink-100 dark:bg-pink-900/30 flex items-center justify-center">
          <.icon name="hero-video-camera" class="w-4 h-4 text-pink-600 dark:text-pink-400" />
        </div>
        """

      true ->
        ~H"""
        <div class="w-8 h-8 rounded-md bg-muted flex items-center justify-center">
          <.icon name="hero-document" class="w-4 h-4 text-muted-foreground" />
        </div>
        """
    end
  end

  defp file_icon(assigns) do
    ~H"""
    <div class="w-8 h-8 rounded-md bg-muted flex items-center justify-center">
      <.icon name="hero-document" class="w-4 h-4 text-muted-foreground" />
    </div>
    """
  end
end
