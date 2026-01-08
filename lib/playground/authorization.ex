defmodule Playground.Authorization do
  @moduledoc """
  Authorization module built on Authorizir.

  Uses a simple role-based access control (RBAC) system with:
  - **Admin**: Full system access
  - **Member**: Standard user access

  ## Usage

      # Check if user can perform action
      Authorization.can?(user, "users:manage")

      # Check if user is admin
      Authorization.admin?(user)
  """

  use Authorizir, repo: Playground.Repo

  alias Playground.Repo
  alias Authorizir.{Subject, Object, Permission}

  import Ecto.Query

  # ============================================================================
  # Constants
  # ============================================================================

  @system_object "system"

  # ============================================================================
  # Subject/Object IDs
  # ============================================================================

  @doc "Generate subject ID for a user"
  def subject_id(%{id: id}), do: "user:#{id}"
  def subject_id(id) when is_binary(id), do: "user:#{id}"

  @doc "Generate subject ID for a role"
  def role_subject_id(:admin), do: "role:admin"
  def role_subject_id(:member), do: "role:member"
  def role_subject_id(role) when is_atom(role), do: "role:#{role}"
  def role_subject_id(role) when is_binary(role), do: "role:#{role}"

  @doc "Object ID for system-level permissions"
  def system_object_id, do: @system_object

  # ============================================================================
  # High-Level Authorization Checks
  # ============================================================================

  @doc """
  Check if a user can perform an action.

  ## Examples

      Authorization.can?(user, "users:manage")
      Authorization.can?(user, "admin:system")
  """
  def can?(nil, _permission), do: false

  def can?(user, permission) when is_binary(permission) do
    user_subject = subject_id(user)
    case permission_granted?(user_subject, system_object_id(), permission) do
      :granted -> true
      :denied -> false
      {:error, _} -> false
    end
  end

  @doc """
  Check if user is an admin.
  """
  def admin?(nil), do: false

  def admin?(user) do
    can?(user, "admin:system")
  end

  # ============================================================================
  # Role Management
  # ============================================================================

  @doc """
  Grant admin role to a user.
  """
  def grant_admin(user) do
    admin_role = role_subject_id(:admin)
    user_subject = subject_id(user)

    ensure_subject(admin_role, "Admin Role")
    ensure_subject(user_subject, "User #{user.id}")

    add_child(admin_role, user_subject, Subject)
  end

  @doc """
  Revoke admin role from a user.
  """
  def revoke_admin(user) do
    admin_role = role_subject_id(:admin)
    user_subject = subject_id(user)

    remove_child(admin_role, user_subject, Subject)
  end

  @doc """
  Grant member role to a user.
  """
  def grant_member(user) do
    member_role = role_subject_id(:member)
    user_subject = subject_id(user)

    ensure_subject(member_role, "Member Role")
    ensure_subject(user_subject, "User #{user.id}")

    add_child(member_role, user_subject, Subject)
  end

  # ============================================================================
  # Permission Definitions
  # ============================================================================

  @doc """
  Returns all permissions with their descriptions.
  Each permission is a tuple of {ext_id, description}.
  """
  def all_permissions do
    [
      # Admin permissions
      {"admin:system", "Access admin dashboard and monitoring tools (Oban, LiveDashboard, ErrorTracker)"},
      {"admin:users", "Access the user management section"},
      {"admin:roles", "Manage roles and permission grants"},

      # User management permissions
      {"users:view", "View the list of users"},
      {"users:create", "Create new user accounts"},
      {"users:edit", "Edit user account details"},
      {"users:delete", "Delete user accounts"},

      # AI Chat permissions
      {"ai_chat:use", "Use the AI chat feature"},
      {"ai_chat:view_all", "View all users' AI chats (admin only)"}
    ]
  end

  @doc "List of all admin permission IDs"
  def admin_permissions do
    all_permissions() |> Enum.map(&elem(&1, 0))
  end

  @doc "List of member permission IDs"
  def member_permissions do
    ["ai_chat:use"]
  end

  @doc "Get the description for a permission ID"
  def permission_description(ext_id) do
    case Enum.find(all_permissions(), fn {id, _desc} -> id == ext_id end) do
      {_, description} -> description
      nil -> ext_id
    end
  end

  # ============================================================================
  # Setup / Seeding
  # ============================================================================

  @doc """
  Initialize the authorization system with roles and permissions.
  Run this during deployment/seeding.
  """
  def setup! do
    # Register the system object
    ensure_object(system_object_id(), "System-level resource")

    # Register all permissions with their descriptions
    all_permissions()
    |> Enum.each(fn {ext_id, description} ->
      ensure_permission(ext_id, description)
    end)

    # Create and configure roles
    setup_role(:admin, "Full system access - can perform all operations", admin_permissions())
    setup_role(:member, "Standard user - authenticated access to own profile only", member_permissions())

    :ok
  end

  defp setup_role(role_atom, description, permissions) do
    role_id = role_subject_id(role_atom)
    ensure_subject(role_id, description)

    permissions
    |> Enum.each(fn perm ->
      grant_permission(role_id, system_object_id(), perm)
    end)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  @doc "Ensure a subject exists in the authorization system"
  def ensure_subject(ext_id, description) do
    case Repo.get_by(Subject, ext_id: ext_id) do
      nil -> register_subject(ext_id, description)
      _existing -> :ok
    end
  end

  @doc "Ensure an object exists in the authorization system"
  def ensure_object(ext_id, description) do
    case Repo.get_by(Object, ext_id: ext_id) do
      nil ->
        Object.new(ext_id, description)
        |> Repo.insert()
        |> case do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end

      _existing ->
        :ok
    end
  end

  @doc "Ensure a permission exists in the authorization system"
  def ensure_permission(ext_id, description) do
    case Repo.get_by(Permission, ext_id: ext_id) do
      nil ->
        Permission.new(ext_id, description)
        |> Repo.insert()
        |> case do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end

      existing ->
        # Update description if it differs
        if existing.description != description do
          existing
          |> Ecto.Changeset.change(description: description)
          |> Repo.update()
        end

        :ok
    end
  end

  # ============================================================================
  # Query Functions (for Admin UI)
  # ============================================================================

  alias Authorizir.AuthorizationRule

  @doc """
  List all roles in the system.
  """
  def list_roles do
    from(s in Subject, where: like(s.ext_id, "role:%"), order_by: s.ext_id)
    |> Repo.all()
  end

  @doc """
  List all permissions in the system.
  """
  def list_permissions do
    from(p in Permission, order_by: p.ext_id)
    |> Repo.all()
  end

  @doc """
  List all authorization rules (grants/denies).
  """
  def list_rules do
    from(r in AuthorizationRule,
      preload: [:subject, :object, :permission],
      order_by: [r.subject_id, r.object_id, r.permission_id]
    )
    |> Repo.all()
  end

  @doc """
  Get the children of a role (users with that role).
  """
  def get_role_children(role_ext_id) do
    case Repo.get_by(Subject, ext_id: role_ext_id) do
      nil -> []
      role ->
        Subject.children(role)
        |> Repo.all()
    end
  end

  @doc """
  Get all roles assigned to a user.
  Returns a list of role ext_ids (e.g., ["role:admin", "role:member"]).
  """
  def get_user_roles(user) do
    user_subject_id = subject_id(user)

    case Repo.get_by(Subject, ext_id: user_subject_id) do
      nil ->
        []

      user_subject ->
        user_subject
        |> Subject.parents()
        |> Repo.all()
        |> Enum.map(& &1.ext_id)
        |> Enum.filter(&String.starts_with?(&1, "role:"))
    end
  end

  @doc """
  Grant a role to a user.
  """
  def grant_role(user, role) when is_atom(role) do
    grant_role(user, role_subject_id(role))
  end

  def grant_role(user, role_ext_id) when is_binary(role_ext_id) do
    user_subject = subject_id(user)

    ensure_subject(role_ext_id, "Role")
    ensure_subject(user_subject, "User #{user.id}")

    add_child(role_ext_id, user_subject, Subject)
  end

  @doc """
  Revoke a role from a user.
  """
  def revoke_role(user, role) when is_atom(role) do
    revoke_role(user, role_subject_id(role))
  end

  def revoke_role(user, role_ext_id) when is_binary(role_ext_id) do
    user_subject = subject_id(user)
    remove_child(role_ext_id, user_subject, Subject)
  end

  @doc """
  Update user roles to match the given list.
  Grants new roles and revokes removed roles.
  """
  def update_user_roles(user, new_role_ext_ids) when is_list(new_role_ext_ids) do
    current_roles = get_user_roles(user) |> MapSet.new()
    new_roles = MapSet.new(new_role_ext_ids)

    # Roles to add
    roles_to_add = MapSet.difference(new_roles, current_roles)
    # Roles to remove
    roles_to_remove = MapSet.difference(current_roles, new_roles)

    # Grant new roles
    Enum.each(roles_to_add, fn role_ext_id ->
      grant_role(user, role_ext_id)
    end)

    # Revoke removed roles
    Enum.each(roles_to_remove, fn role_ext_id ->
      revoke_role(user, role_ext_id)
    end)

    :ok
  end

  @doc """
  Format a subject ext_id for display.
  """
  def format_subject_id(ext_id) do
    case ext_id do
      "role:admin" -> "Admin"
      "role:member" -> "Member"
      "role:" <> rest -> String.capitalize(rest)
      "user:" <> id -> "User #{String.slice(id, 0, 8)}..."
      other -> other
    end
  end

  @doc """
  Format an object ext_id for display.
  """
  def format_object_id(ext_id) do
    case ext_id do
      "system" -> "System"
      other -> other
    end
  end

  @doc """
  List all generic roles (not user-specific subjects).
  """
  def list_generic_roles do
    from(s in Subject, where: like(s.ext_id, "role:%"), order_by: s.ext_id)
    |> Repo.all()
  end

  @doc """
  List all subjects in the system.
  """
  def list_subjects do
    from(s in Subject, order_by: s.ext_id)
    |> Repo.all()
  end

  @doc """
  List all objects in the system.
  """
  def list_objects do
    from(o in Object, order_by: o.ext_id)
    |> Repo.all()
  end

  @doc """
  Get the parents of a role.
  """
  def get_role_parents(role_ext_id) do
    case Repo.get_by(Subject, ext_id: role_ext_id) do
      nil ->
        []

      role ->
        Subject.parents(role)
        |> Repo.all()
    end
  end

  @doc """
  List authorization rules for a specific role.
  """
  def list_rules_for_role(role_ext_id) do
    case Repo.get_by(Subject, ext_id: role_ext_id) do
      nil ->
        []

      role ->
        from(r in AuthorizationRule,
          where: r.subject_id == ^role.id,
          preload: [:subject, :object, :permission],
          order_by: [r.permission_id]
        )
        |> Repo.all()
    end
  end

  @doc """
  Add a permission to a role for an object.
  """
  def add_role_permission(role_ext_id, object_ext_id, permission_ext_id) do
    grant_permission(role_ext_id, object_ext_id, permission_ext_id)
  end

  @doc """
  Remove a permission from a role for an object.
  """
  def remove_role_permission(role_ext_id, object_ext_id, permission_ext_id) do
    revoke_permission(role_ext_id, object_ext_id, permission_ext_id)
  end
end
