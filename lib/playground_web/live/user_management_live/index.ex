defmodule PlaygroundWeb.UserManagementLive.Index do
  @moduledoc """
  LiveView for managing user accounts with Flop integration.
  """

  use PlaygroundWeb, :live_view

  import Ecto.Query
  alias Playground.{Accounts, Authorization, Repo}
  alias Playground.Accounts.User
  alias Playground.Policies.UserPolicy
  import PlaygroundWeb.Components.AdminTable

  @impl true
  def mount(_params, _session, socket) do
    breadcrumbs = [
      %{label: "Dashboard", path: ~p"/admin"},
      %{label: "Users", path: nil}
    ]

    socket =
      socket
      |> assign(:page_title, "User Management")
      |> assign(:breadcrumbs, breadcrumbs)
      |> assign(:user, %User{})
      |> assign(:user_to_delete, nil)
      |> assign(:selected_ids, MapSet.new())
      |> load_results(%{})

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_action(socket.assigns.live_action, params)
      |> load_results(params)

    {:noreply, socket}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:user, %User{})
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:user, %User{})
  end


  defp load_results(socket, params) do
    query = from(u in User)

    # Apply custom filters
    query = apply_search_filter(query, params)
    query = apply_status_filter(query, params)

    case Flop.validate_and_run(query, params, for: User) do
      {:ok, {users, meta}} ->
        # Store params at meta level for easy access
        meta = Map.put(meta, :params, params)

        socket
        |> assign(:users, users)
        |> assign(:meta, meta)

      {:error, meta} ->
        socket
        |> assign(:users, [])
        |> assign(:meta, meta)
    end
  end

  defp apply_search_filter(query, %{"search" => search}) when search != "" do
    search_term = "%#{search}%"

    from u in query,
      where: ilike(u.email, ^search_term)
  end

  defp apply_search_filter(query, _), do: query

  defp apply_status_filter(query, %{"status" => status}) do
    if status in User.states() do
      from u in query, where: u.status == ^status
    else
      query
    end
  end

  defp apply_status_filter(query, _), do: query

  @impl true
  def handle_event("update-filter", params, socket) do
    existing_params = Map.get(socket.assigns.meta, :params, %{})

    filter_params =
      existing_params
      |> update_if_changed(params, "search")
      |> update_if_changed(params, "status")

    # Only push_patch if params actually changed
    if filter_params != existing_params do
      {:noreply, push_patch(socket, to: ~p"/admin/users?#{filter_params}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear-filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/users")}
  end

  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    existing_params = Map.get(socket.assigns.meta, :params, %{})
    new_params = Map.put(existing_params, "page_size", page_size) |> Map.delete("page")
    {:noreply, push_patch(socket, to: ~p"/admin/users?#{new_params}")}
  end

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

  def handle_event("select_all_page", _params, socket) do
    all_ids = Enum.map(socket.assigns.users, & &1.id) |> MapSet.new()

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
    case Bodyguard.permit(UserPolicy, :delete, socket.assigns.current_user) do
      :ok ->
        selected_ids = MapSet.to_list(socket.assigns.selected_ids)

        # Don't allow deleting self
        current_user_id = socket.assigns.current_user.id
        deletable_ids = Enum.reject(selected_ids, &(&1 == current_user_id))

        # Fetch all users in a single query to avoid N+1
        users =
          from(u in Playground.Accounts.User, where: u.id in ^deletable_ids)
          |> Repo.all()

        # Delete each user (maintains any potential callbacks)
        deleted_count =
          Enum.reduce(users, 0, fn user, acc ->
            case Accounts.delete_user(user) do
              {:ok, _} -> acc + 1
              {:error, _} -> acc
            end
          end)

        socket =
          socket
          |> put_flash(:info, "Successfully deleted #{deleted_count} user(s)")
          |> assign(:selected_ids, MapSet.new())
          |> Fluxon.close_dialog("bulk-delete-modal")
          |> load_results(socket.assigns.meta.params)

        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to delete users.")
         |> Fluxon.close_dialog("bulk-delete-modal")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    case Bodyguard.permit(UserPolicy, :delete, socket.assigns.current_user, user) do
      :ok ->
        {:noreply,
         socket
         |> assign(:user_to_delete, user)
         |> Fluxon.open_dialog("delete-modal")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete this user.")}
    end
  end

  def handle_event("confirm_delete", _params, socket) do
    if socket.assigns.user_to_delete do
      user = socket.assigns.current_user
      target = socket.assigns.user_to_delete

      case Bodyguard.permit(UserPolicy, :delete, user, target) do
        :ok ->
          case Accounts.delete_user(target) do
            {:ok, _} ->
              {:noreply,
               socket
               |> put_flash(:info, "User deleted successfully")
               |> Fluxon.close_dialog("delete-modal")
               |> assign(:user_to_delete, nil)
               |> load_results(socket.assigns.meta.params)}

            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(:error, "Could not delete user")
               |> Fluxon.close_dialog("delete-modal")
               |> assign(:user_to_delete, nil)}
          end

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "You don't have permission to delete users.")
           |> Fluxon.close_dialog("delete-modal")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("unconfirm_user", %{"id" => id}, socket) do
    case Bodyguard.permit(UserPolicy, :unconfirm, socket.assigns.current_user) do
      :ok ->
        user = Accounts.get_user!(id)

        case Accounts.unconfirm_user(user, socket.assigns.current_user) do
          {:ok, _updated_user} ->
            {:noreply,
             socket
             |> put_flash(:info, "User confirmation revoked")
             |> load_results(socket.assigns.meta.params)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Error: #{reason}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to modify user confirmation.")}
    end
  end

  @impl true
  def handle_info({PlaygroundWeb.UserManagementLive.FormComponent, {:saved, _user}}, socket) do
    {:noreply, load_results(socket, socket.assigns.meta.params)}
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
      _ -> "10"
    end
  end

  defp status_filter_options do
    [{"All statuses", ""} | Enum.map(User.states(), fn state ->
      {User.state_name(state), state}
    end)]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-card border border-base shadow-sm rounded-lg overflow-hidden flex-1 flex flex-col min-h-0">
      <.admin_table
        id="users-table"
        rows={@users}
        meta={@meta}
        path={~p"/admin/users"}
        selected_ids={@selected_ids}
        show_checkboxes={true}
        title="Users"
      >
        <:header_action>
          <.button variant="solid" color="primary" size="sm" navigate={~p"/admin/users/new"}>
            <.icon name="hero-plus" class="size-4 mr-2" />
            Add User
          </.button>
        </:header_action>

        <:toolbar>
          <.form for={%{}} phx-change="update-filter" class="flex items-center gap-3">
            <div class="flex-1">
              <.input
                type="text"
                name="search"
                value={get_filter_value(@meta, "search")}
                placeholder="Search users..."
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
                    <.label>Status</.label>
                    <.select
                      name="status"
                      value={get_filter_value(@meta, "status")}
                      options={status_filter_options()}
                    />
                  </div>

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
          <:col :let={user} label="Email" field={:email} sortable>
            <div class="flex items-center">
              <div class="h-10 w-10 flex-shrink-0">
                <div class="h-10 w-10 rounded-full bg-muted flex items-center justify-center">
                  <span class="text-sm font-medium text-foreground-soft">
                    {String.first(user.email) |> String.upcase()}
                  </span>
                </div>
              </div>
              <div class="ml-4">
                <div class="font-medium text-foreground">{user.email}</div>
              </div>
            </div>
          </:col>

          <:col :let={user} label="Admin">
            <%= if Authorization.admin?(user) do %>
              <.badge color="primary">
                <.icon name="hero-shield-check" class="size-3 mr-1" />
                Admin
              </.badge>
            <% else %>
              <span class="text-muted-foreground">-</span>
            <% end %>
          </:col>

          <:col :let={user} label="Status">
            <%= if user.status == "confirmed" do %>
              <.badge color="success">Confirmed</.badge>
            <% else %>
              <.badge color="warning">Unconfirmed</.badge>
            <% end %>
          </:col>

          <:col :let={user} label="Created" field={:inserted_at} sortable>
            <span class="text-muted-foreground">
              {Calendar.strftime(user.inserted_at, "%b %d, %Y")}
            </span>
          </:col>

          <:bulk_action label="Delete Selected" icon="hero-trash" event="open_bulk_delete" />

          <:row_action :let={user}>
            <.dropdown placement="bottom-end">
              <:toggle>
                <.button variant="ghost" size="sm">
                  <.icon name="hero-ellipsis-vertical" class="size-4" />
                </.button>
              </:toggle>
              <.dropdown_link navigate={~p"/admin/users/#{user}/edit"}>
                <.icon name="hero-pencil" class="size-4 mr-2" />
                Edit
              </.dropdown_link>
              <%= if user.status == "confirmed" do %>
                <.dropdown_separator />
                <.dropdown_button
                  phx-click="unconfirm_user"
                  phx-value-id={user.id}
                  class="text-warning"
                >
                  <.icon name="hero-x-circle" class="size-4 mr-2" />
                  Revoke Confirmation
                </.dropdown_button>
              <% end %>
              <.dropdown_separator />
              <.dropdown_button
                phx-click="delete"
                phx-value-id={user.id}
                class="text-danger"
              >
                <.icon name="hero-trash" class="size-4 mr-2" />
                Delete
              </.dropdown_button>
            </.dropdown>
          </:row_action>
        </.admin_table>

        <!-- Empty state -->
        <%= if length(@users) == 0 do %>
          <div class="text-center py-12">
            <.icon name="hero-users" class="mx-auto h-12 w-12 text-muted-foreground" />
            <h3 class="mt-2 text-sm font-medium text-foreground">No users found</h3>
            <p class="mt-1 text-sm text-muted-foreground">
              <%= if has_active_filters?(@meta) do %>
                Try adjusting your filters or search terms.
              <% else %>
                Get started by creating a new user.
              <% end %>
            </p>
          </div>
        <% end %>
      </div>

      <!-- Delete Confirmation Modal -->
      <.modal id="delete-modal" class="max-w-md w-full">
        <h3 class="text-base font-semibold leading-6 text-foreground mb-4">
          Delete User
        </h3>

        <%= if @user_to_delete do %>
          <p class="text-sm text-muted-foreground">
            Are you sure you want to delete <strong>{@user_to_delete.email}</strong>?
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
          Delete Multiple Users
        </h3>

        <p class="text-sm text-muted-foreground">
          Are you sure you want to delete <strong>{MapSet.size(@selected_ids)}</strong> user(s)?
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

      <!-- New User Modal -->
      <.modal
        :if={@live_action == :new}
        id="user-modal"
        open
        on_close={JS.patch(~p"/admin/users")}
      >
        <.live_component
          module={PlaygroundWeb.UserManagementLive.FormComponent}
          id={:new}
          title="New User"
          action={:new}
          user={@user}
          patch={~p"/admin/users"}
        />
      </.modal>
    """
  end
end
