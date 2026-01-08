defmodule PlaygroundWeb.AuthzMount do
  @moduledoc """
  LiveView on_mount hooks for authorization checks.

  Provides route-level protection by checking permissions before mounting LiveViews.
  Unauthorized users are redirected with an error flash message.
  """

  import Phoenix.LiveView
  alias Playground.Policies.AdminPolicy

  @doc """
  On_mount hook for authorization checks.

  ## Modes
  - `:require_admin` - Requires admin:system permission (admin dashboard routes)
  - `:require_user_access` - Requires admin:users permission (user management routes)
  - `:require_role_access` - Requires admin:roles permission (role management routes)
  """
  def on_mount(:require_admin, _params, _session, socket) do
    authorize(socket, AdminPolicy, :access_dashboard, "/unauthorized")
  end

  def on_mount(:require_user_access, _params, _session, socket) do
    authorize(socket, AdminPolicy, :access_users, "/unauthorized")
  end

  def on_mount(:require_role_access, _params, _session, socket) do
    authorize(socket, AdminPolicy, :access_roles, "/unauthorized")
  end

  defp authorize(socket, policy, action, redirect_to) do
    case Bodyguard.permit(policy, action, socket.assigns[:current_user]) do
      :ok ->
        {:cont, socket}

      {:error, _} ->
        socket =
          socket
          |> put_flash(:error, "You don't have permission to access this page.")
          |> redirect(to: redirect_to)

        {:halt, socket}
    end
  end
end
