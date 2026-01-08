defmodule PlaygroundWeb.UserSettingsLive do
  use PlaygroundWeb, :live_view

  alias Playground.Accounts

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <h1 class="text-2xl text-foreground font-bold mb-8">Account Settings</h1>

      <!-- User Profile -->
      <section class="mb-12">
        <h2 class="text-xl font-semibold text-foreground mb-4">User Profile</h2>
        <div class="flex items-center gap-4 mb-6">
          <div class="h-16 w-16 bg-primary-soft rounded-full flex items-center justify-center">
            <span class="text-2xl font-semibold text-primary">
              {String.first(@current_user.email) |> String.upcase()}
            </span>
          </div>
          <div>
            <p class="text-lg font-medium text-foreground">{@current_user.email}</p>
            <p class="text-sm text-foreground-softer">Signed in</p>
          </div>
        </div>
      </section>

      <!-- Change Email -->
      <section class="mb-12">
        <h2 class="text-xl font-semibold text-foreground mb-4">Change Email</h2>
        <.form
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
          class="space-y-6"
        >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <.input field={@email_form[:email]} type="email" label="New Email Address" required />
            <.input
              field={@email_form[:current_password]}
              name="current_password"
              id="current_password_for_email"
              type="password"
              label="Current Password"
              value={@email_form_current_password}
              required
            />
          </div>
          <div class="flex justify-end">
            <.button type="submit" variant="solid" phx-disable-with="Updating...">
              Update Email
            </.button>
          </div>
        </.form>
      </section>

      <!-- Change Password -->
      <section class="mb-12">
        <h2 class="text-xl font-semibold text-foreground mb-4">Change Password</h2>
        <.form
          for={@password_form}
          id="password_form"
          action={~p"/users/log_in?_action=password_updated"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
          class="space-y-6"
        >
          <input
            name={@password_form[:email].name}
            type="hidden"
            id="hidden_user_email"
            value={@current_email}
          />
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <.input
              field={@password_form[:password]}
              type="password"
              label="New Password"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirm New Password"
            />
          </div>
          <.input
            field={@password_form[:current_password]}
            name="current_password"
            type="password"
            label="Current Password"
            id="current_password_for_password"
            value={@current_password}
            required
          />
          <div class="flex justify-end">
            <.button type="submit" variant="solid" phx-disable-with="Updating...">
              Update Password
            </.button>
          </div>
        </.form>
      </section>

      <!-- Appearance -->
      <section class="mb-12">
        <h2 class="text-xl font-semibold text-foreground mb-4">Appearance</h2>
        <div class="space-y-4">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <.label description="Choose your preferred color mode for a more comfortable experience">
              Color Mode
            </.label>
            <.button_group>
              <.button
                type="button"
                size="sm"
                variant={if @color_mode == "system", do: "solid", else: "outline"}
                phx-click="set_color_mode"
                phx-value-mode="system"
              >
                <.icon name="hero-computer-desktop" class="size-4 mr-1.5" />
                System
              </.button>
              <.button
                type="button"
                size="sm"
                variant={if @color_mode == "light", do: "solid", else: "outline"}
                phx-click="set_color_mode"
                phx-value-mode="light"
              >
                <.icon name="hero-sun" class="size-4 mr-1.5" />
                Light
              </.button>
              <.button
                type="button"
                size="sm"
                variant={if @color_mode == "dark", do: "solid", else: "outline"}
                phx-click="set_color_mode"
                phx-value-mode="dark"
              >
                <.icon name="hero-moon" class="size-4 mr-1.5" />
                Dark
              </.button>
            </.button_group>
          </div>
        </div>
      </section>

      <!-- Account Actions -->
      <section class="mb-12">
        <h2 class="text-xl font-semibold text-foreground mb-4">Account Actions</h2>
        <div class="space-y-4">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <.label description="Sign out of your account on this device">
              Sign Out
            </.label>
            <.button href="/users/log_out" method="delete" variant="outline" size="sm">
              <.icon name="hero-arrow-right-on-rectangle" class="size-4 mr-1.5" />
              Sign Out
            </.button>
          </div>
        </div>
      </section>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok ->
          put_flash(socket, :info, "Email changed successfully.")

        :error ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)
    color_mode = Accounts.User.theme_preference(user)

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:page_title, "Settings")
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:color_mode, color_mode)

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm_email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  def handle_event("set_color_mode", %{"mode" => mode}, socket) when mode in ["system", "light", "dark"] do
    user = socket.assigns.current_user

    case Accounts.update_user_preferences(user, %{"theme" => mode}) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:color_mode, mode)
         |> push_event("update_theme", %{theme: mode})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update color mode.")}
    end
  end
end
