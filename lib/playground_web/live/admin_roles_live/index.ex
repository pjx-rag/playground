defmodule PlaygroundWeb.AdminRolesLive.Index do
  @moduledoc """
  Admin page for managing roles, permissions, and authorization rules.
  """
  use PlaygroundWeb, :live_view

  alias Playground.Authorization
  alias Playground.Policies.RolePolicy
  import PlaygroundWeb.Components.Layout.PageLayout

  @impl true
  def mount(_params, _session, socket) do
    breadcrumbs = [
      %{label: "Admin", path: ~p"/admin"},
      %{label: "Roles & Permissions", path: nil}
    ]

    {:ok,
     socket
     |> assign(:page_title, "Roles & Permissions")
     |> assign(:breadcrumbs, breadcrumbs)
     |> assign(:active_tab, "roles")
     |> assign(:selected_role, nil)
     |> load_data()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    tab = Map.get(params, "tab", "roles")
    {:noreply, assign(socket, :active_tab, tab)}
  end

  defp load_data(socket) do
    permissions = Authorization.list_permissions()

    # Group permissions by category (prefix before :)
    grouped_permissions =
      permissions
      |> Enum.group_by(fn p ->
        case String.split(p.ext_id, ":") do
          [category | _] -> category
          _ -> "other"
        end
      end)
      |> Enum.sort_by(fn {category, _} -> category end)

    socket
    |> assign(:roles, Authorization.list_generic_roles())
    |> assign(:permissions, permissions)
    |> assign(:grouped_permissions, grouped_permissions)
    |> assign(:rules, Authorization.list_rules())
    |> assign(:subjects, Authorization.list_subjects())
    |> assign(:objects, Authorization.list_objects())
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> push_patch(to: ~p"/admin/roles?tab=#{tab}")}
  end

  def handle_event("select_role", %{"role_id" => ""}, socket) do
    {:noreply,
     socket
     |> assign(:selected_role, nil)
     |> assign(:selected_role_children, [])
     |> assign(:selected_role_parents, [])
     |> assign(:selected_role_rules, [])
     |> assign(:granted_permissions, MapSet.new())}
  end

  def handle_event("select_role", %{"role_id" => role_ext_id}, socket) do
    children = Authorization.get_role_children(role_ext_id)
    parents = Authorization.get_role_parents(role_ext_id)
    rules = Authorization.list_rules_for_role(role_ext_id)

    # Create a set of granted permission ext_ids for quick lookup
    granted_permissions =
      rules
      |> Enum.filter(&(&1.rule_type == :+))
      |> Enum.map(& &1.permission.ext_id)
      |> MapSet.new()

    {:noreply,
     socket
     |> assign(:selected_role, role_ext_id)
     |> assign(:selected_role_children, children)
     |> assign(:selected_role_parents, parents)
     |> assign(:selected_role_rules, rules)
     |> assign(:granted_permissions, granted_permissions)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_role, nil)
     |> assign(:selected_role_children, [])
     |> assign(:selected_role_parents, [])
     |> assign(:selected_role_rules, [])
     |> assign(:granted_permissions, MapSet.new())}
  end

  def handle_event("toggle_permission", %{"permission" => perm_id, "role" => role_id}, socket) do
    granted = socket.assigns[:granted_permissions] || MapSet.new()
    action = if MapSet.member?(granted, perm_id), do: :revoke_permission, else: :grant_permission

    case Bodyguard.permit(RolePolicy, action, socket.assigns.current_user) do
      :ok ->
        result =
          if MapSet.member?(granted, perm_id) do
            Authorization.remove_role_permission(role_id, "system", perm_id)
          else
            Authorization.add_role_permission(role_id, "system", perm_id)
          end

        case result do
          success when success in [:ok, :granted, :revoked] ->
            reload_role_permissions(socket, role_id)

          {:ok, _} ->
            reload_role_permissions(socket, role_id)

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to update permission: #{inspect(reason)}")}

          other ->
            require Logger
            Logger.warning("Unexpected result from permission toggle: #{inspect(other)}")
            reload_role_permissions(socket, role_id)
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to modify role permissions.")}
    end
  end

  defp reload_role_permissions(socket, role_id) do
    rules = Authorization.list_rules_for_role(role_id)

    granted_permissions =
      rules
      |> Enum.filter(&(&1.rule_type == :+))
      |> Enum.map(& &1.permission.ext_id)
      |> MapSet.new()

    {:noreply,
     socket
     |> assign(:selected_role_rules, rules)
     |> assign(:granted_permissions, granted_permissions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_layout>
      <div class="space-y-6">
        <!-- Tab Navigation -->
        <div class="border-b border-base">
          <nav class="-mb-px flex space-x-8" aria-label="Tabs">
            <button
              phx-click="select_tab"
              phx-value-tab="roles"
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@active_tab == "roles",
                  do: "border-primary text-primary",
                  else: "border-transparent text-muted-foreground hover:text-foreground hover:border-border"
                )
              ]}
            >
              <.icon name="hero-user-group" class="w-4 h-4 mr-2 inline" /> Roles
              <span class="ml-2 bg-muted text-muted-foreground text-xs px-2 py-0.5 rounded-full">
                {length(@roles)}
              </span>
            </button>
            <button
              phx-click="select_tab"
              phx-value-tab="permissions"
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@active_tab == "permissions",
                  do: "border-primary text-primary",
                  else: "border-transparent text-muted-foreground hover:text-foreground hover:border-border"
                )
              ]}
            >
              <.icon name="hero-key" class="w-4 h-4 mr-2 inline" /> Permissions
              <span class="ml-2 bg-muted text-muted-foreground text-xs px-2 py-0.5 rounded-full">
                {length(@permissions)}
              </span>
            </button>
            <button
              phx-click="select_tab"
              phx-value-tab="grants"
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@active_tab == "grants",
                  do: "border-primary text-primary",
                  else: "border-transparent text-muted-foreground hover:text-foreground hover:border-border"
                )
              ]}
            >
              <.icon name="hero-shield-check" class="w-4 h-4 mr-2 inline" /> Grants
              <span class="ml-2 bg-muted text-muted-foreground text-xs px-2 py-0.5 rounded-full">
                {length(@rules)}
              </span>
            </button>
            <button
              phx-click="select_tab"
              phx-value-tab="subjects"
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@active_tab == "subjects",
                  do: "border-primary text-primary",
                  else: "border-transparent text-muted-foreground hover:text-foreground hover:border-border"
                )
              ]}
            >
              <.icon name="hero-users" class="w-4 h-4 mr-2 inline" /> All Subjects
              <span class="ml-2 bg-muted text-muted-foreground text-xs px-2 py-0.5 rounded-full">
                {length(@subjects)}
              </span>
            </button>
          </nav>
        </div>

        <!-- Tab Content -->
        <div class="mt-6">
          <%= case @active_tab do %>
            <% "roles" -> %>
              <.roles_tab
                roles={@roles}
                selected_role={@selected_role}
                selected_role_children={assigns[:selected_role_children] || []}
                selected_role_parents={assigns[:selected_role_parents] || []}
                grouped_permissions={@grouped_permissions}
                granted_permissions={assigns[:granted_permissions] || MapSet.new()}
              />
            <% "permissions" -> %>
              <.permissions_tab permissions={@permissions} />
            <% "grants" -> %>
              <.grants_tab rules={@rules} />
            <% "subjects" -> %>
              <.subjects_tab subjects={@subjects} />
            <% _ -> %>
              <.roles_tab
                roles={@roles}
                selected_role={@selected_role}
                selected_role_children={assigns[:selected_role_children] || []}
                selected_role_parents={assigns[:selected_role_parents] || []}
                grouped_permissions={@grouped_permissions}
                granted_permissions={assigns[:granted_permissions] || MapSet.new()}
              />
          <% end %>
        </div>
      </div>
    </.page_layout>
    """
  end

  # ===========================================================================
  # Roles Tab
  # ===========================================================================

  defp roles_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Role Selection -->
      <div class="bg-card border border-base rounded-lg overflow-hidden shadow-sm">
        <div class="px-6 py-4 border-b border-base bg-muted">
          <h2 class="text-lg font-semibold text-foreground">Select a Role</h2>
          <p class="text-sm text-muted-foreground mt-1">
            Choose a role to view and manage its permissions
          </p>
        </div>

        <div class="p-4">
          <%= if Enum.empty?(@roles) do %>
            <div class="text-center py-8">
              <.icon name="hero-user-group" class="mx-auto h-12 w-12 text-muted-foreground" />
              <h3 class="mt-2 text-sm font-medium text-foreground">No roles</h3>
              <p class="mt-1 text-sm text-muted-foreground">No roles have been created yet.</p>
            </div>
          <% else %>
            <form phx-change="select_role" class="max-w-sm">
              <select
                name="role_id"
                class="block w-full rounded-lg border-base bg-card text-foreground shadow-sm focus:border-primary focus:ring-primary sm:text-sm"
              >
                <option value="">Choose a role...</option>
                <%= for role <- @roles do %>
                  <option value={role.ext_id} selected={@selected_role == role.ext_id}>
                    {Authorization.format_subject_id(role.ext_id)}
                  </option>
                <% end %>
              </select>
            </form>
          <% end %>
        </div>
      </div>

      <%= if @selected_role do %>
        <!-- Permissions by Category -->
        <div class="bg-card border border-base rounded-lg overflow-hidden shadow-sm">
          <div class="px-6 py-4 border-b border-base bg-muted flex items-center justify-between">
            <div>
              <h2 class="text-lg font-semibold text-foreground">
                Permissions for {Authorization.format_subject_id(@selected_role)}
              </h2>
              <p class="text-sm text-muted-foreground mt-1">
                Check or uncheck permissions to grant or revoke access
              </p>
            </div>
            <button
              phx-click="clear_selection"
              class="text-muted-foreground hover:text-foreground p-1 rounded hover:bg-muted"
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <div class="p-6">
            <div class="space-y-6">
              <%= for {category, permissions} <- @grouped_permissions do %>
                <div>
                  <h3 class="text-sm font-semibold text-foreground mb-3 capitalize flex items-center gap-2">
                    <.icon name={category_icon(category)} class="w-4 h-4" />
                    {category}
                    <span class="text-xs font-normal text-muted-foreground">
                      ({Enum.count(permissions, fn p -> MapSet.member?(@granted_permissions, p.ext_id) end)}/{length(permissions)})
                    </span>
                  </h3>
                  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                    <%= for perm <- permissions do %>
                      <label class={[
                        "group flex items-center gap-3 p-3 rounded-base border cursor-pointer transition-all",
                        "bg-surface shadow-xs",
                        "has-[:focus-visible]:border-focus has-[:focus-visible]:ring-3 has-[:focus-visible]:ring-focus",
                        if(MapSet.member?(@granted_permissions, perm.ext_id),
                          do: "border-primary bg-accent",
                          else: "border-input hover:bg-muted"
                        )
                      ]}>
                        <div class="relative inline-flex shrink-0">
                          <input
                            type="checkbox"
                            checked={MapSet.member?(@granted_permissions, perm.ext_id)}
                            phx-click="toggle_permission"
                            phx-value-permission={perm.ext_id}
                            phx-value-role={@selected_role}
                            class="peer appearance-none size-4.5 rounded-[0.3125rem] border border-input shadow-xs bg-input checked:border-transparent checked:bg-primary cursor-pointer"
                          />
                          <svg
                            viewBox="0 0 16 16"
                            fill="currentColor"
                            xmlns="http://www.w3.org/2000/svg"
                            class="absolute text-foreground-primary opacity-0 peer-checked:opacity-100 inset-0 pointer-events-none"
                          >
                            <path d="M12.207 4.793a1 1 0 010 1.414l-5 5a1 1 0 01-1.414 0l-2-2a1 1 0 011.414-1.414L6.5 9.086l4.293-4.293a1 1 0 011.414 0z" />
                          </svg>
                        </div>
                        <div class="flex-1 min-w-0">
                          <div class="flex items-center gap-1.5">
                            <span class="text-sm font-medium text-foreground">
                              {permission_action(perm.ext_id)}
                            </span>
                            <.tooltip>
                              <.icon
                                name="hero-information-circle"
                                class="w-4 h-4 text-muted-foreground cursor-help"
                              />
                              <:content>
                                <div class="max-w-xs">
                                  <div class="font-mono text-xs text-primary-foreground/70 mb-1">
                                    {perm.ext_id}
                                  </div>
                                  <div class="text-sm">
                                    {perm.description || Authorization.permission_description(perm.ext_id)}
                                  </div>
                                </div>
                              </:content>
                            </.tooltip>
                          </div>
                        </div>
                      </label>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% else %>
        <!-- No role selected placeholder -->
        <div class="bg-card border border-base rounded-lg">
          <div class="flex items-center justify-center h-64 text-muted-foreground">
            <div class="text-center">
              <.icon name="hero-cursor-arrow-rays" class="mx-auto h-12 w-12" />
              <p class="mt-2 text-sm">Select a role from the dropdown to manage its permissions</p>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
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

  defp child_icon(ext_id) do
    cond do
      String.starts_with?(ext_id, "user:") -> "hero-user"
      String.starts_with?(ext_id, "role:") -> "hero-user-group"
      true -> "hero-cube"
    end
  end

  # ===========================================================================
  # Permissions Tab
  # ===========================================================================

  defp permissions_tab(assigns) do
    ~H"""
    <div class="bg-card border border-base rounded-lg overflow-hidden shadow-sm">
      <div class="px-6 py-4 border-b border-base bg-muted">
        <h2 class="text-lg font-semibold text-foreground">All Permissions</h2>
        <p class="text-sm text-muted-foreground mt-1">
          Permissions that can be granted to roles
        </p>
      </div>

      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-base">
          <thead class="bg-muted/50">
            <tr>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Permission ID
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Description
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Category
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Created
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base">
            <%= for permission <- @permissions do %>
              <tr class="hover:bg-muted/30">
                <td class="whitespace-nowrap px-6 py-4">
                  <div class="font-mono text-sm text-primary">{permission.ext_id}</div>
                </td>
                <td class="px-6 py-4 text-sm text-foreground">
                  {permission.description}
                </td>
                <td class="whitespace-nowrap px-6 py-4 text-sm">
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-muted text-muted-foreground">
                    {permission_category(permission.ext_id)}
                  </span>
                </td>
                <td class="whitespace-nowrap px-6 py-4 text-sm text-muted-foreground">
                  {Calendar.strftime(permission.inserted_at, "%b %d, %Y")}
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%= if Enum.empty?(@permissions) do %>
        <div class="text-center py-12">
          <.icon name="hero-key" class="mx-auto h-12 w-12 text-muted-foreground" />
          <h3 class="mt-2 text-sm font-medium text-foreground">No permissions</h3>
          <p class="mt-1 text-sm text-muted-foreground">No permissions have been defined yet.</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp permission_category(ext_id) do
    case String.split(ext_id, ":") do
      [category | _] -> String.capitalize(category)
      _ -> "Other"
    end
  end

  # ===========================================================================
  # Grants Tab
  # ===========================================================================

  defp grants_tab(assigns) do
    ~H"""
    <div class="bg-card border border-base rounded-lg overflow-hidden shadow-sm">
      <div class="px-6 py-4 border-b border-base bg-muted">
        <h2 class="text-lg font-semibold text-foreground">Authorization Rules</h2>
        <p class="text-sm text-muted-foreground mt-1">
          All permission grants and denies in the system
        </p>
      </div>

      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-base">
          <thead class="bg-muted/50">
            <tr>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Type
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Subject
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Permission
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Object
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Created
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base">
            <%= for rule <- @rules do %>
              <tr class="hover:bg-muted/30">
                <td class="whitespace-nowrap px-6 py-4">
                  <span class={[
                    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border",
                    if(rule.rule_type == :+,
                      do: "bg-success-soft text-foreground-success-soft border-success",
                      else: "bg-danger-soft text-foreground-danger-soft border-danger"
                    )
                  ]}>
                    {if rule.rule_type == :+, do: "GRANT", else: "DENY"}
                  </span>
                </td>
                <td class="px-6 py-4">
                  <div class="text-sm font-medium text-foreground">
                    {Authorization.format_subject_id(rule.subject.ext_id)}
                  </div>
                  <div class="text-xs text-muted-foreground font-mono">{rule.subject.ext_id}</div>
                </td>
                <td class="whitespace-nowrap px-6 py-4">
                  <div class="font-mono text-sm text-primary">{rule.permission.ext_id}</div>
                </td>
                <td class="px-6 py-4">
                  <div class="text-sm font-medium text-foreground">
                    {Authorization.format_object_id(rule.object.ext_id)}
                  </div>
                  <div class="text-xs text-muted-foreground font-mono">{rule.object.ext_id}</div>
                </td>
                <td class="whitespace-nowrap px-6 py-4 text-sm text-muted-foreground">
                  {Calendar.strftime(rule.inserted_at, "%b %d, %Y")}
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%= if Enum.empty?(@rules) do %>
        <div class="text-center py-12">
          <.icon name="hero-shield-check" class="mx-auto h-12 w-12 text-muted-foreground" />
          <h3 class="mt-2 text-sm font-medium text-foreground">No authorization rules</h3>
          <p class="mt-1 text-sm text-muted-foreground">
            No permission grants or denies have been created yet.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  # ===========================================================================
  # Subjects Tab
  # ===========================================================================

  defp subjects_tab(assigns) do
    ~H"""
    <div class="bg-card border border-base rounded-lg overflow-hidden shadow-sm">
      <div class="px-6 py-4 border-b border-base bg-muted">
        <h2 class="text-lg font-semibold text-foreground">All Subjects</h2>
        <p class="text-sm text-muted-foreground mt-1">
          All entities in the authorization system (roles, users)
        </p>
      </div>

      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-base">
          <thead class="bg-muted/50">
            <tr>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Type
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Subject ID
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Description
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-semibold uppercase tracking-wide text-foreground"
              >
                Created
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base">
            <%= for subject <- @subjects do %>
              <tr class="hover:bg-muted/30">
                <td class="whitespace-nowrap px-6 py-4">
                  <span class={[
                    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                    subject_type_class(subject.ext_id)
                  ]}>
                    <.icon name={child_icon(subject.ext_id)} class="w-3 h-3 mr-1" />
                    {subject_type(subject.ext_id)}
                  </span>
                </td>
                <td class="px-6 py-4">
                  <div class="font-mono text-sm text-foreground">{subject.ext_id}</div>
                </td>
                <td class="px-6 py-4 text-sm text-muted-foreground">
                  {subject.description}
                </td>
                <td class="whitespace-nowrap px-6 py-4 text-sm text-muted-foreground">
                  {Calendar.strftime(subject.inserted_at, "%b %d, %Y")}
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%= if Enum.empty?(@subjects) do %>
        <div class="text-center py-12">
          <.icon name="hero-users" class="mx-auto h-12 w-12 text-muted-foreground" />
          <h3 class="mt-2 text-sm font-medium text-foreground">No subjects</h3>
          <p class="mt-1 text-sm text-muted-foreground">
            No subjects have been registered yet.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp subject_type(ext_id) do
    cond do
      String.starts_with?(ext_id, "user:") -> "User"
      String.starts_with?(ext_id, "role:") -> "Role"
      true -> "Other"
    end
  end

  defp subject_type_class(ext_id) do
    cond do
      String.starts_with?(ext_id, "user:") ->
        "bg-primary-soft text-foreground-soft border-primary/30"

      String.starts_with?(ext_id, "role:") ->
        "bg-success-soft text-foreground-success-soft border-success"

      true ->
        "bg-muted text-muted-foreground border-base"
    end
  end
end
