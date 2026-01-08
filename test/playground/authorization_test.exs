defmodule Playground.AuthorizationTest do
  use Playground.DataCase

  alias Playground.{Authorization, Accounts}

  describe "can?/2" do
    test "returns false for nil user" do
      refute Authorization.can?(nil, "users:manage")
      refute Authorization.can?(nil, "admin:system")
      refute Authorization.can?(nil, "any:permission")
    end

    test "returns true for user with permission" do
      Authorization.setup!()

      {:ok, user} =
        Accounts.register_user(%{
          email: "admin@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(user, ["role:admin"])

      assert Authorization.can?(user, "admin:system")
    end

    test "returns false for user without permission" do
      Authorization.setup!()

      {:ok, user} =
        Accounts.register_user(%{
          email: "user@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(user, ["role:member"])

      refute Authorization.can?(user, "admin:system")
    end
  end

  describe "admin?/1" do
    test "returns false for nil user" do
      refute Authorization.admin?(nil)
    end

    test "returns true for admin user" do
      Authorization.setup!()

      {:ok, admin} =
        Accounts.register_user(%{
          email: "admin@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(admin, ["role:admin"])

      assert Authorization.admin?(admin)
    end

    test "returns false for non-admin user" do
      Authorization.setup!()

      {:ok, user} =
        Accounts.register_user(%{
          email: "user@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(user, ["role:member"])

      refute Authorization.admin?(user)
    end
  end
end
