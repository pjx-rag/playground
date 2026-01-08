defmodule PlaygroundWeb.UserManagementLive.Edit do
  @moduledoc """
  LiveView for editing a user account.
  """

  use PlaygroundWeb, :live_view

  alias Playground.{Accounts, Authorization}
  alias Playground.Policies.UserPolicy

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = Accounts.get_user!(id)

    breadcrumbs = [
      %{label: "Dashboard", path: ~p"/admin"},
      %{label: "Users", path: ~p"/admin/users"},
      %{label: "Edit User", path: nil}
    ]

    available_roles =
      Authorization.list_generic_roles()
      |> Enum.map(fn role ->
        label = Authorization.format_subject_id(role.ext_id)
        {label, role.ext_id}
      end)

    user_roles = Authorization.get_user_roles(user)

    # Get grouped permissions for display
    permissions = Authorization.list_permissions()

    grouped_permissions =
      permissions
      |> Enum.group_by(fn p ->
        case String.split(p.ext_id, ":") do
          [category | _] -> category
          _ -> "other"
        end
      end)
      |> Enum.sort_by(fn {category, _} -> category end)

    # Calculate granted permissions based on user's roles
    granted_permissions = calculate_granted_permissions(user_roles)

    socket =
      socket
      |> assign(:page_title, "Edit User")
      |> assign(:breadcrumbs, breadcrumbs)
      |> assign(:user, user)
      |> assign(:available_roles, available_roles)
      |> assign(:user_roles, user_roles)
      |> assign(:grouped_permissions, grouped_permissions)
      |> assign(:granted_permissions, granted_permissions)
      |> assign(:form, to_form(Accounts.change_user(user)))

    {:ok, socket}
  end

  defp calculate_granted_permissions(user_roles) do
    user_roles
    |> Enum.flat_map(fn role_ext_id ->
      Authorization.list_rules_for_role(role_ext_id)
      |> Enum.filter(&(&1.rule_type == :+))
      |> Enum.map(& &1.permission.ext_id)
    end)
    |> MapSet.new()
  end

  @impl true
  def handle_event("validate", params, socket) do
    user_params = Map.get(params, "user", %{})
    changeset = Accounts.change_user(socket.assigns.user, user_params)

    socket =
      case Map.get(params, "roles") do
        nil ->
          socket

        roles when is_list(roles) ->
          case Bodyguard.permit(UserPolicy, :manage_roles, socket.assigns.current_user) do
            :ok ->
              new_roles = Enum.reject(roles, &(&1 == ""))
              update_roles_for_user(socket, new_roles)

            {:error, _} ->
              put_flash(socket, :error, "You don't have permission to manage user roles.")
          end
      end

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Bodyguard.permit(UserPolicy, :update, socket.assigns.current_user, socket.assigns.user) do
      :ok ->
        case Accounts.update_user(socket.assigns.user, user_params) do
          {:ok, _user} ->
            {:noreply,
             socket
             |> put_flash(:info, "User updated successfully")
             |> push_navigate(to: ~p"/admin/users")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to edit this user.")}
    end
  end

  defp update_roles_for_user(socket, new_roles) do
    user = socket.assigns.user
    current_roles = socket.assigns.user_roles

    if MapSet.new(new_roles) != MapSet.new(current_roles) do
      Authorization.update_user_roles(user, new_roles)

      # Recalculate permissions when roles change
      granted_permissions = calculate_granted_permissions(new_roles)

      socket
      |> assign(:user_roles, new_roles)
      |> assign(:granted_permissions, granted_permissions)
    else
      socket
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <h1 class="text-2xl text-foreground font-bold mb-8">Edit User</h1>

      <.form :let={f} for={@form} class="space-y-14" phx-change="validate" phx-submit="save" as={:user}>
        <!-- User Profile -->
        <section>
          <h2 class="text-xl font-semibold text-foreground mb-4">User Profile</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <.input field={f[:email]} type="email" label="Email Address" required />
            <.input field={f[:first_name]} type="text" label="First Name" />
            <.input field={f[:last_name]} type="text" label="Last Name" />
          </div>
        </section>

        <!-- Roles -->
        <section>
          <h2 class="text-xl font-semibold text-foreground mb-4">Roles</h2>
          <p class="text-sm text-muted-foreground mb-4">
            Assign roles to control what this user can access. Permissions are inherited from assigned roles.
          </p>
          <input type="hidden" name="roles[]" value="" />
          <div class="space-y-3">
            <label
              :for={{label, value} <- @available_roles}
              class="flex items-start gap-3 p-4 rounded-lg border border-base hover:bg-muted/50 cursor-pointer transition-colors"
            >
              <input
                type="checkbox"
                name="roles[]"
                value={value}
                checked={value in @user_roles}
                class="mt-1 rounded border-input text-primary focus:ring-primary"
              />
              <div>
                <div class="text-sm font-medium text-foreground">{label}</div>
                <p :if={role_description(value)} class="text-sm text-muted-foreground mt-0.5">
                  {role_description(value)}
                </p>
              </div>
            </label>
          </div>
        </section>

        <!-- Effective Permissions (Read-only) -->
        <section>
          <h2 class="text-xl font-semibold text-foreground mb-4">Effective Permissions</h2>
          <p class="text-sm text-muted-foreground mb-4">
            These permissions are granted based on the user's assigned roles. To modify permissions, edit the role on the
            <.link navigate={~p"/admin/roles"} class="text-primary hover:underline">Roles & Permissions</.link>
            page.
          </p>

          <div class="space-y-6">
            <%= for {category, permissions} <- @grouped_permissions do %>
              <% granted_count = Enum.count(permissions, fn p -> MapSet.member?(@granted_permissions, p.ext_id) end) %>
              <div>
                <h3 class="text-sm font-semibold text-foreground mb-3 capitalize flex items-center gap-2">
                  <.icon name={category_icon(category)} class="w-4 h-4" />
                  {category}
                  <span class="text-xs font-normal text-muted-foreground">
                    ({granted_count}/{length(permissions)})
                  </span>
                </h3>
                <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                  <%= for perm <- permissions do %>
                    <% is_granted = MapSet.member?(@granted_permissions, perm.ext_id) %>
                    <div class={[
                      "flex items-center gap-3 p-3 rounded-base border shadow-xs transition-colors",
                      if(is_granted,
                        do: "bg-accent border-primary",
                        else: "bg-surface border-input opacity-60"
                      )
                    ]}>
                      <.icon
                        name={if is_granted, do: "hero-check-circle", else: "hero-minus-circle"}
                        class={"w-5 h-5 flex-shrink-0 #{if is_granted, do: "text-primary", else: "text-muted-foreground"}"}
                      />
                      <div class="flex-1 min-w-0">
                        <div class={[
                          "text-sm font-medium",
                          if(is_granted, do: "text-foreground", else: "text-muted-foreground")
                        ]}>
                          {permission_action(perm.ext_id)}
                        </div>
                        <div class="text-xs text-muted-foreground truncate">
                          {perm.description}
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </section>

        <div class="flex justify-end space-x-4">
          <.button type="button" navigate={~p"/admin/users"}>Cancel</.button>
          <.button variant="solid" color="primary" type="submit" phx-disable-with="Saving...">
            Save Changes
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  defp role_description(role_ext_id) do
    case role_ext_id do
      "role:admin" -> "Full system access - can manage users, roles, and all admin features"
      "role:member" -> "Standard user - authenticated access to own profile only"
      _ -> nil
    end
  end

  defp category_icon(category) do
    case category do
      "admin" -> "hero-shield-check"
      "users" -> "hero-users"
      "profile" -> "hero-user"
      _ -> "hero-key"
    end
  end

  defp permission_action(ext_id) do
    case String.split(ext_id, ":") do
      [_category, action] -> String.capitalize(action)
      _ -> ext_id
    end
  end
end
