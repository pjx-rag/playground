defmodule PlaygroundWeb.Router do
  use PlaygroundWeb, :router

  import PlaygroundWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PlaygroundWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_admin do
    plug :require_authenticated_user
    plug :authorize_analytics
  end

  # Public API routes
  scope "/api", PlaygroundWeb do
    pipe_through :api

    get "/theme/:mode", ThemeController, :show
  end

  scope "/", PlaygroundWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  ## Authentication routes

  scope "/", PlaygroundWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{PlaygroundWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", PlaygroundWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      layout: {PlaygroundWeb.Layouts, :app},
      on_mount: [{PlaygroundWeb.UserAuth, :ensure_authenticated}] do
      live "/dashboard", DashboardLive, :index
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email

      # AI Chat
      live "/chat", AIChatLive, :index
      live "/chat/:id", AIChatLive, :show

      # Unauthorized page - accessible to all authenticated users
      live "/unauthorized", UnauthorizedLive, :index
    end

    # Admin dashboard - requires admin:system
    live_session :admin_dashboard,
      layout: {PlaygroundWeb.Layouts, :app},
      on_mount: [
        {PlaygroundWeb.UserAuth, :ensure_authenticated},
        {PlaygroundWeb.AuthzMount, :require_admin}
      ] do
      live "/admin", AdminDashboardLive.Index, :index
      live "/admin/backups", AdminBackupsLive.Index, :index
      live "/admin/api-logs", AdminAPILogsLive.Index, :index
      live "/admin/api-logs/:id", AdminAPILogsLive.Show, :show
      live "/admin/themes", AdminThemesLive.Index, :index
      live "/admin/themes/new", AdminThemesLive.Index, :new
      live "/admin/themes/:id/edit", AdminThemesLive.Index, :edit
      live "/admin/settings", AdminSiteSettingsLive.Index, :index
    end

    # User management - requires admin:users
    live_session :admin_users,
      layout: {PlaygroundWeb.Layouts, :app},
      on_mount: [
        {PlaygroundWeb.UserAuth, :ensure_authenticated},
        {PlaygroundWeb.AuthzMount, :require_user_access}
      ] do
      live "/admin/users", UserManagementLive.Index, :index
      live "/admin/users/new", UserManagementLive.Index, :new
      live "/admin/users/:id/edit", UserManagementLive.Edit, :edit
    end

    # Role management - requires admin:roles
    live_session :admin_roles,
      layout: {PlaygroundWeb.Layouts, :app},
      on_mount: [
        {PlaygroundWeb.UserAuth, :ensure_authenticated},
        {PlaygroundWeb.AuthzMount, :require_role_access}
      ] do
      live "/admin/roles", AdminRolesLive.Index, :index
    end
  end

  scope "/", PlaygroundWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete
    get "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{PlaygroundWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  # Admin-only dashboards and tools
  import Phoenix.LiveDashboard.Router
  import Oban.Web.Router
  import ErrorTracker.Web.Router
  import PhoenixAnalytics.Web.Router

  scope "/admin" do
    pipe_through [:browser, :require_admin]

    # PhoenixAnalytics Dashboard
    phoenix_analytics_dashboard "/analytics"

    # Phoenix LiveDashboard
    live_dashboard "/dashboard", metrics: PlaygroundWeb.Telemetry

    # Oban Web interface
    oban_dashboard("/oban")

    # Error Tracker interface
    error_tracker_dashboard("/errors")
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:playground, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
