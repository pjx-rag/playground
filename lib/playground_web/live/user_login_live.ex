defmodule PlaygroundWeb.UserLoginLive do
  use PlaygroundWeb, :live_view

  @default_logo_url "https://fluxonui.com/images/logos/1.svg"

  def render(assigns) do
    ~H"""
    <div class="flex flex-1 items-center justify-center px-4 py-10">
      <div class="flex flex-col items-center gap-y-6 w-full max-w-sm">
        <.link navigate={~p"/"} class="flex items-center gap-3 hover:opacity-80 transition-opacity">
          <img src={@logo_url} alt="Logo" class="h-8 w-auto logo-adaptive" />
          <span class="text-2xl font-bold text-foreground uppercase tracking-wide">Playground</span>
        </.link>

        <div class="w-full border border-base rounded-base shadow-base bg-accent">
          <div class="bg-base p-10 rounded-base border border-base -m-px">
            <h1 class="text-center text-xl/10 font-bold text-foreground">Sign in to your account</h1>
            <p class="text-center text-sm text-foreground-softer">
              Welcome back! Please sign in to continue.
            </p>

            <.form
              for={@form}
              id="login_form"
              action={~p"/users/log_in"}
              phx-update="ignore"
              class="flex flex-col gap-y-3 mt-6"
            >
              <.input field={@form[:email]} type="email" label="Email" />
              <.input field={@form[:password]} type="password" label="Password" />

              <div class="flex items-center justify-between">
                <.checkbox field={@form[:remember_me]} label="Keep me logged in" />
                <.link
                  href={~p"/users/reset_password"}
                  class="text-sm font-medium text-foreground-soft hover:text-foreground"
                >
                  Forgot password?
                </.link>
              </div>

              <.button type="submit" variant="solid" phx-disable-with="Signing in..." class="w-full">
                Sign in
              </.button>
            </.form>
          </div>
          <p class="text-center p-4 text-sm">
            Don't have an account?
            <.link
              navigate={~p"/users/register"}
              class="font-medium text-foreground-soft hover:text-foreground"
            >
              Sign up
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    logo_url =
      case socket.assigns[:site_settings] do
        %{logo_url: url} when is_binary(url) and url != "" -> url
        _ -> @default_logo_url
      end

    {:ok, assign(socket, form: form, logo_url: logo_url), temporary_assigns: [form: form]}
  end
end
