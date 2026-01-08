defmodule Playground.Policies.RolePolicyTest do
  use Playground.DataCase

  alias Playground.Policies.RolePolicy
  alias Playground.{Accounts, Authorization}

  describe "authorize/3" do
    setup do
      # Setup authorization roles and permissions
      Authorization.setup!()

      # Admin user with admin:roles permission
      {:ok, admin} =
        Accounts.register_user(%{
          email: "admin@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(admin, ["role:admin"])

      # Regular user without admin:roles permission
      {:ok, regular_user} =
        Accounts.register_user(%{
          email: "user@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(regular_user, ["role:member"])

      %{admin: admin, regular_user: regular_user}
    end

    test "view: allows admin with admin:roles permission", %{admin: admin} do
      assert :ok = RolePolicy.authorize(:view, admin, nil)
    end

    test "view: denies user without admin:roles permission", %{regular_user: user} do
      assert :error = RolePolicy.authorize(:view, user, nil)
    end

    test "grant_permission: allows admin with admin:roles permission", %{admin: admin} do
      assert :ok = RolePolicy.authorize(:grant_permission, admin, nil)
    end

    test "grant_permission: denies user without admin:roles permission", %{regular_user: user} do
      assert :error = RolePolicy.authorize(:grant_permission, user, nil)
    end

    test "revoke_permission: allows admin with admin:roles permission", %{admin: admin} do
      assert :ok = RolePolicy.authorize(:revoke_permission, admin, nil)
    end

    test "revoke_permission: denies user without admin:roles permission", %{regular_user: user} do
      assert :error = RolePolicy.authorize(:revoke_permission, user, nil)
    end

    test "unknown action: denies all users", %{admin: admin, regular_user: user} do
      assert :error = RolePolicy.authorize(:unknown_action, admin, nil)
      assert :error = RolePolicy.authorize(:unknown_action, user, nil)
    end
  end
end
