defmodule PlaygroundWeb.AdminThemesLive.Index do
  @moduledoc """
  Admin page for managing UI themes.
  Allows viewing, creating, editing, and setting active themes.
  """
  use PlaygroundWeb, :live_view

  alias Playground.Settings
  alias Playground.Settings.Theme
  import PlaygroundWeb.Components.Layout.PageLayout

  @impl true
  def mount(_params, _session, socket) do
    themes = Settings.list_themes()
    {:ok, site_settings} = Settings.get_site_settings()

    breadcrumbs = [
      %{label: "Admin", path: ~p"/admin"},
      %{label: "Themes", path: nil}
    ]

    {:ok,
     socket
     |> assign(:page_title, "Themes")
     |> assign(:breadcrumbs, breadcrumbs)
     |> assign(:themes, themes)
     |> assign(:light_themes, Enum.filter(themes, &(&1.mode == "light")))
     |> assign(:dark_themes, Enum.filter(themes, &(&1.mode == "dark")))
     |> assign(:site_settings, site_settings)
     |> assign(:editing_theme, nil)
     |> assign(:show_editor, false)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:editing_theme, nil)
    |> assign(:show_editor, false)
  end

  defp apply_action(socket, :new, _params) do
    theme = %Theme{
      mode: "light",
      is_system: false,
      tokens: default_tokens()
    }

    socket
    |> assign(:editing_theme, theme)
    |> assign(:show_editor, true)
    |> assign(:form, to_form(Settings.change_theme(theme)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    theme = Settings.get_theme!(id)

    socket
    |> assign(:editing_theme, theme)
    |> assign(:show_editor, true)
    |> assign(:form, to_form(Settings.change_theme(theme)))
  end

  @impl true
  def handle_event("set_light_theme", %{"light_theme" => theme_id}, socket) do
    case Settings.update_site_settings(%{light_theme_id: theme_id}) do
      {:ok, site_settings} ->
        {:noreply,
         socket
         |> assign(:site_settings, site_settings)
         |> push_event("clear_theme_cache", %{})
         |> put_flash(:info, "Light theme updated successfully.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update light theme.")}
    end
  end

  @impl true
  def handle_event("set_dark_theme", %{"dark_theme" => theme_id}, socket) do
    case Settings.update_site_settings(%{dark_theme_id: theme_id}) do
      {:ok, site_settings} ->
        {:noreply,
         socket
         |> assign(:site_settings, site_settings)
         |> push_event("clear_theme_cache", %{})
         |> put_flash(:info, "Dark theme updated successfully.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update dark theme.")}
    end
  end

  @impl true
  def handle_event("preview_theme", %{"id" => id}, socket) do
    theme = Settings.get_theme!(id)

    {:noreply,
     socket
     |> push_event("preview_theme_tokens", %{tokens: theme.tokens, mode: theme.mode})}
  end

  @impl true
  def handle_event("close_editor", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_theme, nil)
     |> assign(:show_editor, false)
     |> push_patch(to: ~p"/admin/themes")}
  end

  @impl true
  def handle_event("validate", %{"theme" => theme_params}, socket) do
    changeset =
      socket.assigns.editing_theme
      |> Settings.change_theme(theme_params)
      |> Map.put(:action, :validate)

    # Live preview the tokens
    tokens = parse_tokens_from_params(theme_params)
    mode = Map.get(theme_params, "mode", socket.assigns.editing_theme.mode || "light")

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> push_event("preview_theme_tokens", %{tokens: tokens, mode: mode})}
  end

  @impl true
  def handle_event("save", %{"theme" => theme_params}, socket) do
    save_theme(socket, socket.assigns.editing_theme, theme_params)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    theme = Settings.get_theme!(id)

    case Settings.delete_theme(theme) do
      {:ok, _} ->
        themes = Settings.list_themes()

        {:noreply,
         socket
         |> assign(:themes, themes)
         |> assign(:light_themes, Enum.filter(themes, &(&1.mode == "light")))
         |> assign(:dark_themes, Enum.filter(themes, &(&1.mode == "dark")))
         |> put_flash(:info, "Theme deleted successfully.")}

      {:error, :cannot_delete_system_theme} ->
        {:noreply, put_flash(socket, :error, "System themes cannot be deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete theme.")}
    end
  end

  @impl true
  def handle_event("duplicate", %{"id" => id}, socket) do
    theme = Settings.get_theme!(id)

    new_theme = %Theme{
      name: "#{theme.name} (Copy)",
      slug: "#{theme.slug}-copy-#{:rand.uniform(1000)}",
      mode: theme.mode,
      is_system: false,
      tokens: theme.tokens
    }

    socket =
      socket
      |> assign(:editing_theme, new_theme)
      |> assign(:show_editor, true)
      |> assign(:form, to_form(Settings.change_theme(new_theme)))

    {:noreply, push_patch(socket, to: ~p"/admin/themes/new")}
  end

  defp save_theme(socket, %Theme{id: nil}, theme_params) do
    # Creating a new theme
    tokens = parse_tokens_from_params(theme_params)

    attrs =
      theme_params
      |> Map.put("tokens", tokens)
      |> Map.put("is_system", false)

    case Settings.create_theme(attrs) do
      {:ok, _theme} ->
        themes = Settings.list_themes()

        {:noreply,
         socket
         |> assign(:themes, themes)
         |> assign(:light_themes, Enum.filter(themes, &(&1.mode == "light")))
         |> assign(:dark_themes, Enum.filter(themes, &(&1.mode == "dark")))
         |> assign(:show_editor, false)
         |> assign(:editing_theme, nil)
         |> push_event("clear_theme_cache", %{})
         |> put_flash(:info, "Theme created successfully.")
         |> push_patch(to: ~p"/admin/themes")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_theme(socket, theme, theme_params) do
    # Updating existing theme
    tokens = parse_tokens_from_params(theme_params)

    attrs = Map.put(theme_params, "tokens", tokens)

    case Settings.update_theme(theme, attrs) do
      {:ok, _theme} ->
        themes = Settings.list_themes()

        {:noreply,
         socket
         |> assign(:themes, themes)
         |> assign(:light_themes, Enum.filter(themes, &(&1.mode == "light")))
         |> assign(:dark_themes, Enum.filter(themes, &(&1.mode == "dark")))
         |> assign(:show_editor, false)
         |> assign(:editing_theme, nil)
         |> push_event("clear_theme_cache", %{})
         |> put_flash(:info, "Theme updated successfully.")
         |> push_patch(to: ~p"/admin/themes")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp parse_tokens_from_params(params) do
    Theme.token_keys()
    |> Enum.reduce(%{}, fn key, acc ->
      value = Map.get(params, key, "")
      Map.put(acc, key, value)
    end)
  end

  defp default_tokens do
    %{
      "primary" => "#18181b",
      "primary_soft" => "#f4f4f5",
      "foreground" => "#3f3f46",
      "foreground_soft" => "#52525b",
      "foreground_softer" => "#71717a",
      "foreground_softest" => "#a1a1aa",
      "foreground_primary" => "#ffffff",
      "background_base" => "#ffffff",
      "background_accent" => "#f4f4f5",
      "background_input" => "#ffffff",
      "surface" => "#ffffff",
      "overlay" => "#ffffff",
      "border_base" => "#e4e4e7",
      "danger" => "#dc2626",
      "success" => "#16a34a",
      "warning" => "#f59e0b",
      "info" => "#2563eb"
    }
  end

  defp is_active_theme?(theme, site_settings) do
    site_settings.light_theme_id == theme.id or site_settings.dark_theme_id == theme.id
  end

  defp get_token_value(theme, key) do
    case theme.tokens do
      nil -> ""
      tokens -> Map.get(tokens, key, "")
    end
  end

  # Theme card component
  attr :theme, Theme, required: true
  attr :is_active, :boolean, default: false

  defp theme_card(assigns) do
    ~H"""
    <div
      class={[
        "relative rounded-lg border-2 p-3 cursor-pointer transition-all hover:shadow-md",
        if(@is_active, do: "border-primary ring-2 ring-primary/20", else: "border-base hover:border-foreground-softer")
      ]}
      phx-click="preview_theme"
      phx-value-id={@theme.id}
    >
      <!-- Active badge -->
      <div :if={@is_active} class="absolute -top-2 -right-2">
        <span class="inline-flex items-center rounded-full bg-primary px-2 py-0.5 text-xs font-medium text-foreground-primary">
          Active
        </span>
      </div>

      <!-- Theme preview -->
      <div
        class="rounded-md p-3 mb-3"
        style={"background-color: #{@theme.tokens["background_base"]}; border: 1px solid #{@theme.tokens["border_base"]};"}
      >
        <!-- Primary button preview -->
        <div class="flex items-center gap-2 mb-2">
          <div
            class="px-3 py-1.5 rounded text-xs font-medium"
            style={"background-color: #{@theme.tokens["primary"]}; color: #{@theme.tokens["foreground_primary"]};"}
          >
            A
          </div>
          <div
            class="w-6 h-6 rounded"
            style={"background-color: #{@theme.tokens["surface"]}; border: 1px solid #{@theme.tokens["border_base"]};"}
          >
          </div>
        </div>

        <!-- Text preview -->
        <div class="flex gap-1 mb-2">
          <span
            class="text-xs font-medium"
            style={"color: #{@theme.tokens["foreground"]};"}
          >
            A
          </span>
          <span
            class="text-xs font-medium px-1.5 py-0.5 rounded"
            style={"background-color: #{@theme.tokens["surface"]}; color: #{@theme.tokens["foreground"]}; border: 1px solid #{@theme.tokens["border_base"]};"}
          >
            A
          </span>
          <span
            class="text-xs font-medium px-1.5 py-0.5 rounded"
            style={"background-color: #{@theme.tokens["info"]}; color: white;"}
          >
            A
          </span>
        </div>

        <!-- Status colors row -->
        <div class="flex gap-1">
          <div
            class="text-xs font-medium px-1.5 py-0.5 rounded"
            style={"background-color: #{@theme.tokens["danger"]}; color: white;"}
          >
            A
          </div>
          <div
            class="text-xs font-medium px-1.5 py-0.5 rounded"
            style={"background-color: #{@theme.tokens["warning"]}; color: black;"}
          >
            A
          </div>
          <div
            class="text-xs font-medium px-1.5 py-0.5 rounded"
            style={"background-color: #{@theme.tokens["success"]}; color: white;"}
          >
            A
          </div>
        </div>
      </div>

      <!-- Theme info -->
      <div class="flex items-center justify-between">
        <div>
          <h3 class="font-medium text-foreground text-sm">{@theme.name}</h3>
          <p class="text-xs text-muted-foreground capitalize">{@theme.mode}</p>
        </div>

        <.dropdown placement="bottom-end">
          <:toggle>
            <.button variant="ghost" size="sm" class="p-1 h-7">
              <.icon name="hero-ellipsis-vertical" class="w-4 h-4" />
            </.button>
          </:toggle>
          <.dropdown_link phx-click={JS.patch(~p"/admin/themes/#{@theme.id}/edit")}>
            <.icon name="hero-pencil" class="size-4 mr-2" />
            Edit
          </.dropdown_link>
          <.dropdown_link phx-click="duplicate" phx-value-id={@theme.id}>
            <.icon name="hero-document-duplicate" class="size-4 mr-2" />
            Duplicate
          </.dropdown_link>
          <.dropdown_link
            :if={not @theme.is_system}
            phx-click="delete"
            phx-value-id={@theme.id}
            data-confirm="Are you sure you want to delete this theme?"
          >
            <.icon name="hero-trash" class="size-4 mr-2 text-danger" />
            <span class="text-danger">Delete</span>
          </.dropdown_link>
        </.dropdown>
      </div>
    </div>
    """
  end

  # Color input component
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true

  defp color_input(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-foreground mb-1">{@label}</label>
      <div class="flex items-center gap-2">
        <div
          class="h-9 w-9 rounded border border-base cursor-pointer flex-shrink-0"
          style={"background-color: #{@value};"}
        >
          <input
            type="color"
            name={@name}
            value={@value}
            class="h-full w-full opacity-0 cursor-pointer"
          />
        </div>
        <input
          type="text"
          name={@name}
          value={@value}
          class="flex-1 h-9 px-3 rounded border border-base bg-input text-foreground text-sm font-mono"
          pattern="^#[0-9A-Fa-f]{6}$"
        />
      </div>
    </div>
    """
  end
end
