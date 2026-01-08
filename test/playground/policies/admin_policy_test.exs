defmodule Playground.Policies.AdminPolicyTest do
  use Playground.DataCase

  alias Playground.Policies.AdminPolicy
  alias Playground.{Accounts, Authorization}

  describe "authorize/3" do
    setup do
      # Setup authorization roles and permissions
      Authorization.setup!()

      # Create admin user with admin:system permission
      {:ok, admin} =
        Accounts.register_user(%{
          email: "admin@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(admin, ["role:admin"])

      # Create regular user without admin permissions
      {:ok, regular_user} =
        Accounts.register_user(%{
          email: "user@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(regular_user, ["role:member"])

      %{admin: admin, regular_user: regular_user}
    end

    test "access_dashboard: allows admin with admin:system permission", %{admin: admin} do
      assert :ok = AdminPolicy.authorize(:access_dashboard, admin, nil)
    end

    test "access_dashboard: denies regular user without admin:system permission", %{
      regular_user: regular_user
    } do
      assert :error = AdminPolicy.authorize(:access_dashboard, regular_user, nil)
    end

    test "access_users: allows admin with admin:users permission", %{admin: admin} do
      assert :ok = AdminPolicy.authorize(:access_users, admin, nil)
    end

    test "access_users: denies regular user without admin:users permission", %{
      regular_user: regular_user
    } do
      assert :error = AdminPolicy.authorize(:access_users, regular_user, nil)
    end

    test "access_roles: allows admin with admin:roles permission", %{admin: admin} do
      assert :ok = AdminPolicy.authorize(:access_roles, admin, nil)
    end

    test "access_roles: denies regular user without admin:roles permission", %{
      regular_user: regular_user
    } do
      assert :error = AdminPolicy.authorize(:access_roles, regular_user, nil)
    end

    test "unknown action: denies all users", %{admin: admin, regular_user: regular_user} do
      assert :error = AdminPolicy.authorize(:unknown_action, admin, nil)
      assert :error = AdminPolicy.authorize(:unknown_action, regular_user, nil)
    end
  end
end
