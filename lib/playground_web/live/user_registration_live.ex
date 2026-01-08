defmodule PlaygroundWeb.UserRegistrationLive do
  use PlaygroundWeb, :live_view

  alias Playground.Accounts
  alias Playground.Accounts.User

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
            <h1 class="text-center text-xl/10 font-bold text-foreground">Create an account</h1>
            <p class="text-center text-sm text-foreground-softer">
              Welcome! Please sign up to continue.
            </p>

            <.form
              for={@form}
              id="registration_form"
              phx-submit="save"
              phx-change="validate"
              phx-trigger-action={@trigger_submit}
              action={~p"/users/log_in?_action=registered"}
              method="post"
              class="flex flex-col gap-y-3 mt-6"
            >
              <.error :if={@check_errors}>
                Oops, something went wrong! Please check the errors below.
              </.error>

              <.input field={@form[:email]} type="email" label="Email" />
              <.input field={@form[:password]} type="password" label="Password" />

              <.button type="submit" variant="solid" phx-disable-with="Signing up..." class="w-full">
                Sign up
              </.button>
            </.form>
          </div>
          <p class="text-center p-4 text-sm">
            Already have an account?
            <.link
              navigate={~p"/users/log_in"}
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
    changeset = Accounts.change_user_registration(%User{})

    logo_url =
      case socket.assigns[:site_settings] do
        %{logo_url: url} when is_binary(url) and url != "" -> url
        _ -> @default_logo_url
      end

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false, logo_url: logo_url)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
