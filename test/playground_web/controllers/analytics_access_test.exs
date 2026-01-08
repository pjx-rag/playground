defmodule PlaygroundWeb.AnalyticsAccessTest do
  use PlaygroundWeb.ConnCase, async: true

  alias Playground.{Accounts, Authorization}

  setup do
    # Setup authorization system
    Authorization.setup!()
    :ok
  end

  describe "GET /admin/analytics" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      conn = get(conn, ~p"/admin/analytics")
      assert redirected_to(conn) =~ "/users/log_in"
    end

    test "redirects non-admin authenticated users to home with error", %{conn: conn} do
      {:ok, user} =
        Accounts.register_user(%{
          email: "user@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(user, ["role:member"])

      conn = conn |> log_in_user(user) |> get(~p"/admin/analytics")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not authorized"
    end

    test "allows admin users to access analytics dashboard", %{conn: conn} do
      {:ok, admin} =
        Accounts.register_user(%{
          email: "admin@example.com",
          password: "SecurePassword123!"
        })

      Authorization.update_user_roles(admin, ["role:admin"])

      conn = conn |> log_in_user(admin) |> get(~p"/admin/analytics")

      assert html_response(conn, 200)
      assert conn.resp_body =~ "Analytics"
    end
  end

  defp log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
