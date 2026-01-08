defmodule PlaygroundWeb.UserConfirmationInstructionsLive do
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
          <h1 class="text-center text-xl/10 font-bold text-foreground">
            No confirmation instructions received?
          </h1>
          <p class="text-center text-sm text-foreground-softer">
            We'll send a new confirmation link to your inbox.
          </p>

          <.form
            for={@form}
            id="resend_confirmation_form"
            phx-submit="send_instructions"
            class="flex flex-col gap-y-3 mt-6"
          >
            <.input field={@form[:email]} type="email" placeholder="Email" label="Email" required />

            <.button variant="solid" type="submit" phx-disable-with="Sending..." class="w-full">
              Resend confirmation instructions
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

  def mount(_params, _session, socket) do
    logo_url =
      case socket.assigns[:site_settings] do
        %{logo_url: url} when is_binary(url) and url != "" -> url
        _ -> @default_logo_url
      end

    {:ok, assign(socket, form: to_form(%{}, as: "user"), logo_url: logo_url)}
  end

  def handle_event("send_instructions", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/users/confirm/#{&1}")
      )
    end

    info =
      "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
