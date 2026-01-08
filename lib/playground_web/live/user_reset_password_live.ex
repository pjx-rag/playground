defmodule PlaygroundWeb.UserResetPasswordLive do
  use PlaygroundWeb, :live_view

  alias Playground.Accounts

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
            <h1 class="text-center text-xl/10 font-bold text-foreground">Reset your password</h1>
            <p class="text-center text-sm text-foreground-softer">
              Enter your new password below.
            </p>

            <.form
              for={@form}
              id="reset_password_form"
              phx-submit="reset_password"
              phx-change="validate"
              class="flex flex-col gap-y-3 mt-6"
            >
              <.error :if={@form.errors != []}>
                Oops, something went wrong! Please check the errors below.
              </.error>

              <.input field={@form[:password]} type="password" label="New password" required />
              <.input
                field={@form[:password_confirmation]}
                type="password"
                label="Confirm new password"
                required
              />

              <.button variant="solid" type="submit" phx-disable-with="Resetting..." class="w-full">
                Reset password
              </.button>
            </.form>
          </div>
          <p class="text-center p-4 text-sm">
            <.link
              href={~p"/users/log_in"}
              class="font-medium text-foreground-soft hover:text-foreground"
            >
              Sign in
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end

  def mount(params, _session, socket) do
    socket = assign_user_and_token(socket, params)

    logo_url =
      case socket.assigns[:site_settings] do
        %{logo_url: url} when is_binary(url) and url != "" -> url
        _ -> @default_logo_url
      end

    form_source =
      case socket.assigns do
        %{user: user} ->
          Accounts.change_user_password(user)

        _ ->
          %{}
      end

    {:ok, socket |> assign(:logo_url, logo_url) |> assign_form(form_source), temporary_assigns: [form: nil]}
  end

  # Do not log in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/users/log_in")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: ~p"/")
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "user"))
  end
end
