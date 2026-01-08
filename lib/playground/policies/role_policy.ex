defmodule Playground.Policies.RolePolicy do
  @moduledoc """
  Authorization policy for role management actions.

  Implements Bodyguard.Policy behavior to control role and permission management.
  All permissions are checked through Playground.Authorization which integrates with Authorizir.
  """

  @behaviour Bodyguard.Policy
  alias Playground.Authorization

  @doc """
  Authorizes role management actions.

  ## Actions
  - `:view` - Requires "admin:roles" permission
  - `:grant_permission` - Requires "admin:roles" permission
  - `:revoke_permission` - Requires "admin:roles" permission
  """
  def authorize(action, user, _params)
      when action in [:view, :grant_permission, :revoke_permission] do
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
