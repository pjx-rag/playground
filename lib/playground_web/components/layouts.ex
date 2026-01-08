defmodule PlaygroundWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PlaygroundWeb, :html

  embed_templates "layouts/*"

  # ============================================================================
  # Page Container Component
  # ============================================================================

  attr :fluid, :boolean, default: false
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  slot :inner_block, required: true
  slot :actions

  def page_container(assigns) do
    ~H"""
    <div class="min-h-full">
      <div class={container_classes(@fluid)}>
        <%= if @title || @actions != [] do %>
          <div class="flex items-center justify-between mb-6">
            <div>
              <%= if @title do %>
                <h1 class="text-2xl font-bold text-foreground">{@title}</h1>
              <% end %>
              <%= if @description do %>
                <p class="text-sm text-muted-foreground mt-1">{@description}</p>
              <% end %>
            </div>
            <%= if @actions != [] do %>
              <div class="flex items-center gap-3">
                {render_slot(@actions)}
              </div>
            <% end %>
          </div>
        <% end %>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp container_classes(true), do: "px-4 sm:px-6 lg:px-8 py-6"
  defp container_classes(false), do: "mx-auto max-w-6xl px-4 sm:px-6 py-6"

  @doc """
  Renders the app layout with sidebar navigation.

  ## Examples

      <Layouts.app flash={@flash} current_user={@current_user}>
        <h1>Content</h1>
      </Layouts.app>

  """
  @default_logo_url "https://fluxonui.com/images/logos/1.svg"

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, default: nil, doc: "the current user"
  attr :site_settings, :map, default: nil, doc: "site-wide settings"
  attr :page_title, :string, default: nil, doc: "the page title"
  attr :breadcrumbs, :list, default: nil, doc: "breadcrumb items"
  attr :inner_content, :any, default: nil, doc: "inner content for live layouts"

  slot :inner_block

  def app(assigns) do
    assigns =
      assigns
      |> assign_new(:sidebar_collapsed, fn ->
        case assigns[:current_user] do
          nil -> false
          user -> Playground.Accounts.User.sidebar_collapsed?(user)
        end
      end)
      |> assign_new(:logo_url, fn ->
        case assigns[:site_settings] do
          %{logo_url: url} when is_binary(url) and url != "" -> url
          _ -> @default_logo_url
        end
      end)

    ~H"""
    <%= if @current_user do %>
      <!-- Mobile sidebar -->
      <.sheet id="mobile-sidebar-nav" placement="left" class="w-full max-w-xs">
        <div class="flex flex-1 flex-col h-full">
          <div class="flex mb-6 shrink-0 items-center">
            <.link navigate="/dashboard">
              <img
                src={@logo_url}
                alt="Playground"
                class="h-7 w-auto logo-adaptive"
              />
            </.link>
          </div>
          <.sidebar_nav current_user={@current_user} collapsed={false} />
        </div>
      </.sheet>

      <div class="group/layout relative isolate flex min-h-svh w-full bg-base max-md:flex-col">
        <!-- Desktop Sidebar -->
        <div
          id="desktop-sidebar"
          phx-hook="SidebarCollapse"
          class={[
            "fixed inset-y-0 left-0 z-20 max-md:hidden border-r border-base transition-all duration-200",
            if(@sidebar_collapsed, do: "w-20", else: "w-64")
          ]}
        >
          <div class="flex h-full flex-col">
            <div class="flex flex-1 flex-col overflow-y-auto p-6">
              <div class="flex shrink-0 items-center mb-8 gap-2">
                <.link navigate="/dashboard" class="flex items-center gap-2">
                  <img
                    src={@logo_url}
                    alt="Playground"
                    class="h-6 w-auto logo-adaptive"
                  />
                  <span class={[
                    "text-xl font-extrabold text-foreground transition-opacity duration-200",
                    if(@sidebar_collapsed, do: "opacity-0 w-0 overflow-hidden", else: "opacity-100 delay-150")
                  ]}>
                    AcmeCo.
                  </span>
                </.link>
              </div>
              <.sidebar_nav current_user={@current_user} collapsed={@sidebar_collapsed} />
              <!-- Collapse button -->
              <.navlist class="mt-auto pt-4 border-t border-base">
                <.sidebar_collapse_button collapsed={@sidebar_collapsed} />
              </.navlist>
            </div>
          </div>
        </div>

        <!-- Main content area -->
        <main class={[
          "flex flex-1 flex-col md:min-w-0 group-[[data-sidebar-transitioning]]/layout:transition-[padding] group-[[data-sidebar-transitioning]]/layout:duration-200",
          if(@sidebar_collapsed, do: "md:pl-20", else: "md:pl-64")
        ]}>
          <header class="bg-base sticky z-10 top-0 border-b border-base">
            <div class="flex h-16 shrink-0 items-center gap-x-4 px-4 sm:px-6 md:px-8">
              <button
                phx-click={Fluxon.open_dialog("mobile-sidebar-nav")}
                class="relative cursor-pointer flex min-w-0 items-center -m-2 p-2 md:hidden"
              >
                <.icon name="hero-bars-3" class="size-6" />
              </button>

              <.separator vertical class="my-5 md:hidden" />

              <h1 class="text-xl font-semibold text-foreground">
                {@page_title || "Dashboard"}
              </h1>

              <div class="ml-auto flex items-center gap-x-4 md:gap-x-6">
                <.user_menu current_user={@current_user} />
              </div>
            </div>

            <%= if @breadcrumbs && length(@breadcrumbs) > 0 do %>
              <div class="px-4 sm:px-6 md:px-8 py-2 border-t border-base">
                <nav aria-label="Breadcrumb" class="flex w-full overflow-x-auto">
                  <ol role="list" class="flex items-center space-x-4 whitespace-nowrap">
                    <li>
                      <.link
                        navigate={~p"/dashboard"}
                        class="text-muted-foreground hover:text-foreground"
                      >
                        <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="size-5 shrink-0">
                          <path d="M9.293 2.293a1 1 0 0 1 1.414 0l7 7A1 1 0 0 1 17 11h-1v6a1 1 0 0 1-1 1h-2a1 1 0 0 1-1-1v-3a1 1 0 0 0-1-1H9a1 1 0 0 0-1 1v3a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-6H3a1 1 0 0 1-.707-1.707l7-7Z" clip-rule="evenodd" fill-rule="evenodd" />
                        </svg>
                        <span class="sr-only">Home</span>
                      </.link>
                    </li>
                    <%= for crumb <- @breadcrumbs |> Enum.reject(&(Map.get(&1, :label) in ["Home", "Dashboard"])) do %>
                      <li>
                        <div class="flex items-center">
                          <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="size-5 shrink-0 text-muted-foreground">
                            <path d="M8.22 5.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L11.94 10 8.22 6.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
                          </svg>
                          <%= if crumb[:path] do %>
                            <.link navigate={crumb[:path]} class="ml-4 text-sm font-medium text-muted-foreground hover:text-foreground">
                              {crumb[:label]}
                            </.link>
                          <% else %>
                            <span aria-current="page" class="ml-4 text-sm font-medium text-muted-foreground">
                              {crumb[:label]}
                            </span>
                          <% end %>
                        </div>
                      </li>
                    <% end %>
                  </ol>
                </nav>
              </div>
            <% end %>
          </header>

          <.flash_group flash={@flash} />

          <div class="flex-1 flex flex-col p-4 md:p-6 min-h-0">
            <%= if @inner_content do %>
              {@inner_content}
            <% else %>
              {render_slot(@inner_block)}
            <% end %>
          </div>
        </main>
      </div>
    <% else %>
      <!-- Non-authenticated layout -->
      <main class="min-h-screen bg-base flex flex-col">
        <.flash_group flash={@flash} />
        <%= if @inner_content do %>
          {@inner_content}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </main>
    <% end %>
    """
  end

  @doc """
  Sidebar navigation component.
  """
  attr :current_user, :map, required: true
  attr :collapsed, :boolean, default: false

  def sidebar_nav(assigns) do
    ~H"""
    <nav class={["flex flex-1 flex-col", if(@collapsed, do: "items-center")]}>
      <.navlist>
        <.sidebar_navlink navigate="/dashboard" icon="hero-home" collapsed={@collapsed}>
          Dashboard
        </.sidebar_navlink>
        <%= if Playground.Authorization.can?(@current_user, "ai_chat:use") do %>
          <.sidebar_navlink navigate="/chat" icon="hero-chat-bubble-left-right" collapsed={@collapsed}>
            AI Chat
          </.sidebar_navlink>
        <% end %>
      </.navlist>

      <%= if Playground.Authorization.admin?(@current_user) do %>
        <.navlist heading={unless @collapsed, do: "Admin"}>
          <.sidebar_navlink navigate="/admin" icon="hero-cog-6-tooth" collapsed={@collapsed}>
            Admin Dashboard
          </.sidebar_navlink>
        </.navlist>
      <% end %>

      <.navlist class="mt-auto!">
        <.sidebar_navlink navigate="/users/settings" icon="hero-cog-6-tooth" collapsed={@collapsed}>
          Settings
        </.sidebar_navlink>
      </.navlist>
    </nav>
    """
  end

  @doc """
  Sidebar navigation link that supports collapsed state with tooltips.
  """
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :collapsed, :boolean, default: false
  slot :inner_block, required: true

  def sidebar_navlink(assigns) do
    ~H"""
    <%= if @collapsed do %>
      <.tooltip value={render_slot(@inner_block)} placement="right">
        <.navlink navigate={@navigate} class="group text-foreground-softer">
          <.icon name={@icon} class="size-5 shrink-0 group-hover:text-foreground" />
        </.navlink>
      </.tooltip>
    <% else %>
      <.navlink navigate={@navigate} class="group text-foreground-softer">
        <.icon name={@icon} class="size-5 shrink-0 group-hover:text-foreground" />
        <span class="transition-opacity duration-200 whitespace-nowrap opacity-100 delay-150">
          {render_slot(@inner_block)}
        </span>
      </.navlink>
    <% end %>
    """
  end

  @doc """
  Sidebar collapse button that matches navlink styling.
  """
  attr :collapsed, :boolean, default: false

  def sidebar_collapse_button(assigns) do
    ~H"""
    <%= if @collapsed do %>
      <.tooltip value="Expand" placement="right">
        <button
          data-collapse-trigger
          class="group flex items-center rounded-base -ml-2 px-2.5 py-2 font-medium text-sm gap-x-3 text-foreground-soft hover:text-foreground hover:bg-accent"
        >
          <.icon name="hero-arrows-pointing-out" class="size-5 shrink-0 group-hover:text-foreground" />
        </button>
      </.tooltip>
    <% else %>
      <button
        data-collapse-trigger
        class="group flex items-center rounded-base -ml-2 px-2.5 py-2 font-medium text-sm gap-x-3 text-foreground-soft hover:text-foreground hover:bg-accent"
      >
        <.icon name="hero-arrows-pointing-in" class="size-5 shrink-0 group-hover:text-foreground" />
        <span class="transition-opacity duration-200 whitespace-nowrap opacity-100 delay-150">
          Collapse
        </span>
      </button>
    <% end %>
    """
  end

  @doc """
  User menu dropdown in the header.
  """
  attr :current_user, :map, required: true

  def user_menu(assigns) do
    ~H"""
    <.dropdown placement="bottom-end">
      <:toggle>
        <button class="flex items-center gap-2 text-sm text-foreground-soft hover:text-foreground">
          <span class="hidden sm:block">{@current_user.email}</span>
          <.icon name="hero-chevron-down" class="size-4" />
        </button>
      </:toggle>
      <.dropdown_link navigate="/users/settings">
        <.icon name="hero-cog-6-tooth" class="size-4 mr-2" />
        Settings
      </.dropdown_link>
      <.dropdown_link href="/users/log_out" method="get">
        <.icon name="hero-arrow-right-on-rectangle" class="size-4 mr-2" />
        Sign out
      </.dropdown_link>
    </.dropdown>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed bottom-6 left-1/2 -translate-x-1/2 z-50 flex flex-col gap-3 pointer-events-none"
    >
      <div class="pointer-events-auto">
        <.flash kind={:info} title="Success!" flash={@flash} />
      </div>
      <div class="pointer-events-auto">
        <.flash kind={:error} title="Error!" flash={@flash} />
      </div>
    </div>
    """
  end
end
