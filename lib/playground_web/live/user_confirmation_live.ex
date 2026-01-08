defmodule PlaygroundWeb.UserConfirmationLive do
  use PlaygroundWeb, :live_view

  alias Playground.Accounts

  @default_logo_url "https://fluxonui.com/images/logos/1.svg"

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <div class="flex flex-1 items-center justify-center px-4 py-10">
      <div class="flex flex-col items-center gap-y-6 w-full max-w-sm">
        <.link navigate={~p"/"} class="flex items-center gap-3 hover:opacity-80 transition-opacity">
          <img src={@logo_url} alt="Logo" class="h-8 w-auto logo-adaptive" />
          <span class="text-2xl font-bold text-foreground uppercase tracking-wide">Playground</span>
        </.link>

        <div class="w-full border border-base rounded-base shadow-base bg-accent">
          <div class="bg-base p-10 rounded-base border border-base -m-px">
            <h1 class="text-center text-xl/10 font-bold text-foreground">Confirm Account</h1>
            <p class="text-center text-sm text-foreground-softer">
              Click the button below to confirm your account.
            </p>

            <.form
              for={@form}
              id="confirmation_form"
              phx-submit="confirm_account"
              class="flex flex-col gap-y-3 mt-6"
            >
              <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
              <.button variant="solid" type="submit" phx-disable-with="Confirming..." class="w-full">
                Confirm my account
              </.button>
            </.form>
          </div>
          <p class="text-center p-4 text-sm">
            <.link
              href={~p"/users/register"}
              class="font-medium text-foreground-soft hover:text-foreground"
            >
              Register
            </.link>
            |
            <.link
              href={~p"/users/log_in"}
              class="font-medium text-foreground-soft hover:text-foreground"
            >
              Log in
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    form = to_form(%{"token" => token}, as: "user")

    logo_url =
      case socket.assigns[:site_settings] do
        %{logo_url: url} when is_binary(url) and url != "" -> url
        _ -> @default_logo_url
      end

    {:ok, assign(socket, form: form, logo_url: logo_url), temporary_assigns: [form: nil]}
  end

  # Do not log in the user after confirmation to avoid a
  # leaked token giving the user access to the account.
  def handle_event("confirm_account", %{"user" => %{"token" => token}}, socket) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User confirmed successfully.")
         |> redirect(to: ~p"/")}

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case socket.assigns do
          %{current_user: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            {:noreply, redirect(socket, to: ~p"/")}

          %{} ->
            {:noreply,
             socket
             |> put_flash(:error, "User confirmation link is invalid or it has expired.")
             |> redirect(to: ~p"/")}
        end
    end
  end
end
