defmodule Playground.Policies.UserPolicy do
  @moduledoc """
  Authorization policy for user-related actions.

  Implements Bodyguard.Policy behavior to control user CRUD operations.
  All permissions are checked through Playground.Authorization which integrates with Authorizir.

  Special rules:
  - Users can edit themselves even without "users:edit" permission
  - Users cannot delete themselves (prevents accidental lockout)
  - Role management requires "admin:roles" permission
  """

  @behaviour Bodyguard.Policy
  alias Playground.{Authorization, Accounts.User}

  @doc """
  Authorizes user-related actions.

  ## Actions
  - `:list` - Requires "users:view" permission
  - `:view` - Requires "users:view" permission
  - `:create` - Requires "users:create" permission
  - `:edit` - Requires "users:edit" permission OR editing self
  - `:update` - Requires "users:edit" permission OR updating self
  - `:delete` - Requires "users:delete" permission AND not deleting self
  - `:manage_roles` - Requires "admin:roles" permission
  - `:unconfirm` - Requires "users:edit" permission
  """

  # List and view operations
  def authorize(:list, user, _params) do
    check(user, "users:view")
  end

  def authorize(:view, user, _params) do
    check(user, "users:view")
  end

  # Create operations
  def authorize(:create, user, _params) do
    check(user, "users:create")
  end

  # Edit/update operations - can edit self OR has permission
  def authorize(action, user, %User{} = target) when action in [:edit, :update] do
    if user.id == target.id or Authorization.can?(user, "users:edit") do
      :ok
    else
      :error
    end
  end

  def authorize(action, user, _params) when action in [:edit, :update] do
    check(user, "users:edit")
  end

  # Delete operations - cannot delete self, need permission
  def authorize(:delete, user, %User{id: user_id}) when user_id == user.id do
    :error
  end

  def authorize(:delete, user, %User{}) do
    check(user, "users:delete")
  end

  def authorize(:delete, user, _params) do
    check(user, "users:delete")
  end

  # Role management
  def authorize(:manage_roles, user, _params) do
    check(user, "admin:roles")
  end

  # Confirmation management
  def authorize(:unconfirm, user, _params) do
    check(user, "users:edit")
  end

  # Default deny
  def authorize(_action, _user, _params), do: :error

  defp check(user, permission) do
    if Authorization.can?(user, permission) do
      :ok
    else
      :error
    end
  end
end
