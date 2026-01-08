defmodule Playground.Policies.AdminPolicy do
  @moduledoc """
  Authorization policy for admin routes and actions.

  Implements Bodyguard.Policy behavior to control access to admin-level functionality.
  All permissions are checked through Playground.Authorization which integrates with Authorizir.
  """

  @behaviour Bodyguard.Policy
  alias Playground.Authorization

  @doc """
  Authorizes admin-level actions.

  ## Actions
  - `:access_dashboard` - Requires "admin:system" permission
  - `:access_users` - Requires "admin:users" permission
  - `:access_roles` - Requires "admin:roles" permission
  """
  def authorize(:access_dashboard, user, _params) do
    check(user, "admin:system")
  end

  def authorize(:access_users, user, _params) do
    check(user, "admin:users")
  end

  def authorize(:access_roles, user, _params) do
    check(user, "admin:roles")
  end

  def authorize(_action, _user, _params), do: :error

  defp check(user, permission) do
    if Authorization.can?(user, permission) do
      :ok
    else
      :error
    end
  end
end
