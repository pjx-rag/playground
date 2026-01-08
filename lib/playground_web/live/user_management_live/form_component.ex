defmodule PlaygroundWeb.UserManagementLive.FormComponent do
  use PlaygroundWeb, :live_component

  alias Playground.{Accounts, Authorization}
  alias Playground.Policies.UserPolicy

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage user records in your database.</:subtitle>
      </.header>

      <div class="space-y-6">
        <.simple_form
          for={@form}
          id="user-form"
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input field={@form[:first_name]} type="text" label="First Name" />
          <.input field={@form[:last_name]} type="text" label="Last Name" />

          <%= if @action == :new do %>
            <.input field={@form[:password]} type="password" label="Password" required />
          <% end %>

          <%= if @action == :edit and assigns[:available_roles] do %>
            <div class="pt-4 border-t">
              <.select
                id="user-roles-select"
                name="roles[]"
                label="Roles"
                multiple
                value={@user_roles}
                options={@available_roles}
                placeholder="Select roles..."
                help_text="Assign roles to control user permissions. Administrators can access the admin dashboard and manage users."
              />
            </div>
          <% end %>

          <:actions>
            <.button variant="solid" color="primary" phx-disable-with="Saving...">Save User</.button>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end

  @impl true
  def update(%{user: user} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:available_roles, fn ->
       Authorization.list_generic_roles()
       |> Enum.map(fn role ->
         label = Authorization.format_subject_id(role.ext_id)
         {label, role.ext_id}
       end)
     end)
     |> assign_new(:user_roles, fn ->
       if user.id do
         Authorization.get_user_roles(user)
       else
         []
       end
     end)
     |> assign_new(:form, fn ->
       to_form(Accounts.change_user(user))
     end)}
  end

  require Logger

  @impl true
  def handle_event("validate", params, socket) do
    user_params = Map.get(params, "user", %{})
    changeset = Accounts.change_user(socket.assigns.user, user_params)

    # Handle roles update if roles are in the params
    socket =
      case Map.get(params, "roles") do
        nil ->
          socket

        roles when is_list(roles) ->
          case Bodyguard.permit(UserPolicy, :manage_roles, socket.assigns[:current_user]) do
            :ok ->
              new_roles = Enum.reject(roles, &(&1 == ""))
              update_roles_for_user(socket, new_roles)

            {:error, _} ->
              put_flash(socket, :error, "You don't have permission to assign roles.")
          end
      end

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    save_user(socket, socket.assigns.action, user_params)
  end

  defp update_roles_for_user(socket, new_roles) do
    user = socket.assigns.user
    current_roles = socket.assigns.user_roles

    # Only update if roles actually changed
    if MapSet.new(new_roles) != MapSet.new(current_roles) do
      Authorization.update_user_roles(user, new_roles)
      assign(socket, :user_roles, new_roles)
    else
      socket
    end
  end

  defp save_user(socket, :edit, user_params) do
    case Bodyguard.permit(UserPolicy, :update, socket.assigns[:current_user], socket.assigns.user) do
      :ok ->
        case Accounts.update_user(socket.assigns.user, user_params) do
          {:ok, user} ->
            notify_parent({:saved, user})

            {:noreply,
             socket
             |> put_flash(:info, "User updated successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to edit this user.")}
    end
  end

  defp save_user(socket, :new, user_params) do
    case Bodyguard.permit(UserPolicy, :create, socket.assigns[:current_user]) do
      :ok ->
        case Accounts.register_user(user_params) do
          {:ok, user} ->
            notify_parent({:saved, user})

            {:noreply,
             socket
             |> put_flash(:info, "User created successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to create users.")}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
