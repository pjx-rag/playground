defmodule Playground.Policies.UserPolicyTest do
  use Playground.DataCase

  alias Playground.Policies.UserPolicy
  alias Playground.{Accounts, Authorization}

  describe "authorize/3" do
    setup do
      # Setup authorization roles and permissions
      Authorization.setup!()

      # Admin user with all permissions
      {:ok, admin} =
        Accounts.register_user(%{
          email: "admin@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(admin, ["role:admin"])

      # Regular user
      {:ok, regular_user} =
        Accounts.register_user(%{
          email: "user@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(regular_user, ["role:member"])

      # Another regular user
      {:ok, other_user} =
        Accounts.register_user(%{
          email: "other@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(other_user, ["role:member"])

      %{admin: admin, regular_user: regular_user, other_user: other_user}
    end

    # List/View permissions
    test "list: allows admin with users:view permission", %{admin: admin} do
      assert :ok = UserPolicy.authorize(:list, admin, nil)
    end

    test "list: denies user without users:view permission", %{regular_user: user} do
      assert :error = UserPolicy.authorize(:list, user, nil)
    end

    test "view: allows admin with users:view permission", %{admin: admin} do
      assert :ok = UserPolicy.authorize(:view, admin, nil)
    end

    # Create permissions
    test "create: allows admin with users:create permission", %{admin: admin} do
      assert :ok = UserPolicy.authorize(:create, admin, nil)
    end

    test "create: denies user without users:create permission", %{regular_user: user} do
      assert :error = UserPolicy.authorize(:create, user, nil)
    end

    # Edit/Update permissions
    test "edit: allows admin with users:edit permission", %{admin: admin, other_user: other} do
      assert :ok = UserPolicy.authorize(:edit, admin, other)
    end

    test "edit: allows user to edit themselves", %{regular_user: user} do
      assert :ok = UserPolicy.authorize(:edit, user, user)
    end

    test "edit: denies user editing others without permission", %{
      regular_user: user,
      other_user: other
    } do
      assert :error = UserPolicy.authorize(:edit, user, other)
    end

    test "update: allows admin with users:edit permission", %{admin: admin, other_user: other} do
      assert :ok = UserPolicy.authorize(:update, admin, other)
    end

    test "update: allows user to update themselves", %{regular_user: user} do
      assert :ok = UserPolicy.authorize(:update, user, user)
    end

    test "update: denies user updating others without permission", %{
      regular_user: user,
      other_user: other
    } do
      assert :error = UserPolicy.authorize(:update, user, other)
    end

    # Delete permissions
    test "delete: allows admin with users:delete permission", %{admin: admin, other_user: other} do
      assert :ok = UserPolicy.authorize(:delete, admin, other)
    end

    test "delete: denies user deleting themselves", %{regular_user: user} do
      assert :error = UserPolicy.authorize(:delete, user, user)
    end

    test "delete: denies admin deleting themselves", %{admin: admin} do
      assert :error = UserPolicy.authorize(:delete, admin, admin)
    end

    test "delete: denies user without users:delete permission", %{
      regular_user: user,
      other_user: other
    } do
      assert :error = UserPolicy.authorize(:delete, user, other)
    end

    # Role management permissions
    test "manage_roles: allows admin with admin:roles permission", %{admin: admin} do
      assert :ok = UserPolicy.authorize(:manage_roles, admin, nil)
    end

    test "manage_roles: denies user without admin:roles permission", %{regular_user: user} do
      assert :error = UserPolicy.authorize(:manage_roles, user, nil)
    end

    # Unconfirm permissions
    test "unconfirm: allows admin with users:edit permission", %{admin: admin} do
      assert :ok = UserPolicy.authorize(:unconfirm, admin, nil)
    end

    test "unconfirm: denies user without users:edit permission", %{regular_user: user} do
      assert :error = UserPolicy.authorize(:unconfirm, user, nil)
    end

    # Unknown actions
    test "unknown action: denies all users", %{admin: admin, regular_user: user} do
      assert :error = UserPolicy.authorize(:unknown_action, admin, nil)
      assert :error = UserPolicy.authorize(:unknown_action, user, nil)
    end
  end
end
