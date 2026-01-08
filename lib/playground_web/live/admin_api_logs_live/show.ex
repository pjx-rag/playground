defmodule PlaygroundWeb.AdminAPILogsLive.Show do
  @moduledoc """
  LiveView for viewing a single API request log in detail.
  """

  use PlaygroundWeb, :live_view

  alias Playground.{Repo, APIRequestLog}
  import PlaygroundWeb.Components.Layout.PageLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    case Repo.get(APIRequestLog, id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "API log not found.")
         |> redirect(to: ~p"/admin/api-logs")}

      log ->
        breadcrumbs = [
          %{label: "Admin", path: ~p"/admin"},
          %{label: "API Request Logs", path: ~p"/admin/api-logs"},
          %{label: "Log Details", path: nil}
        ]

        {:noreply,
         socket
         |> assign(:page_title, "API Log Details")
         |> assign(:breadcrumbs, breadcrumbs)
         |> assign(:log, log)
         |> assign(:active_tab, "request")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_layout>
      <div class="space-y-6">
        <!-- Request Summary Header -->
        <div class="bg-card border border-base rounded-xl overflow-hidden">
          <table class="w-full">
            <tbody class="divide-y divide-base">
              <tr>
                <td class="px-5 py-4 text-sm text-muted-foreground w-32">URL</td>
                <td class="px-5 py-4">
                  <code class="text-sm font-mono text-foreground break-all">{@log.url || @log.path}</code>
                </td>
              </tr>
              <tr>
                <td class="px-5 py-4 text-sm text-muted-foreground">Service</td>
                <td class="px-5 py-4 text-foreground">{@log.service}</td>
              </tr>
              <tr>
                <td class="px-5 py-4 text-sm text-muted-foreground">Duration</td>
                <td class="px-5 py-4 font-mono text-foreground">{@log.duration_ms}ms</td>
              </tr>
              <tr>
                <td class="px-5 py-4 text-sm text-muted-foreground">Time</td>
                <td class="px-5 py-4 text-foreground">{Calendar.strftime(@log.inserted_at, "%b %d, %Y at %H:%M:%S")}</td>
              </tr>
              <%= if @log.request_id do %>
                <tr>
                  <td class="px-5 py-4 text-sm text-muted-foreground">Request ID</td>
                  <td class="px-5 py-4 font-mono text-sm text-muted-foreground">{@log.request_id}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <!-- Error Message -->
        <%= if @log.error_message do %>
          <div class="bg-danger border border-danger rounded-xl p-5">
            <div class="flex items-start gap-4">
              <.icon name="hero-exclamation-triangle" class="size-5 text-danger flex-shrink-0 mt-0.5" />
              <div>
                <p class="text-sm font-medium text-danger mb-2">Error</p>
                <pre class="text-sm text-danger whitespace-pre-wrap leading-relaxed"><%= @log.error_message %></pre>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Tabs -->
        <div class="bg-card border border-base rounded-xl overflow-hidden">
          <div class="border-b border-base px-2 bg-muted/30">
            <nav class="flex gap-1" aria-label="Tabs">
              <.tab_button active={@active_tab == "request"} tab="request">
                <.icon name="hero-arrow-up-right" class="size-4" />
                Request
                <.method_badge method={@log.method} />
              </.tab_button>
              <.tab_button active={@active_tab == "response"} tab="response">
                <.icon name="hero-arrow-down-left" class="size-4" />
                Response
                <.status_badge status={@log.status_code} success={@log.success} />
              </.tab_button>
              <.tab_button active={@active_tab == "both"} tab="both">
                <.icon name="hero-arrows-right-left" class="size-4" />
                Side by Side
              </.tab_button>
            </nav>
          </div>

          <div class="p-6">
            <%= case @active_tab do %>
              <% "request" -> %>
                <.request_panel log={@log} />
              <% "response" -> %>
                <.response_panel log={@log} />
              <% "both" -> %>
                <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
                  <div>
                    <h3 class="text-sm font-semibold text-foreground mb-4 flex items-center gap-2">
                      <.icon name="hero-arrow-up-right" class="size-4 text-muted-foreground" />
                      Request
                    </h3>
                    <.request_panel log={@log} />
                  </div>
                  <div>
                    <h3 class="text-sm font-semibold text-foreground mb-4 flex items-center gap-2">
                      <.icon name="hero-arrow-down-left" class="size-4 text-muted-foreground" />
                      Response
                    </h3>
                    <.response_panel log={@log} />
                  </div>
                </div>
            <% end %>
          </div>
        </div>
      </div>
    </.page_layout>
    """
  end

  # Tab button component
  attr :active, :boolean, required: true
  attr :tab, :string, required: true
  slot :inner_block, required: true

  defp tab_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="switch-tab"
      phx-value-tab={@tab}
      class={[
        "px-4 py-3 text-sm font-medium border-b-2 -mb-px transition-colors flex items-center gap-2",
        if(@active,
          do: "border-primary text-primary",
          else: "border-transparent text-muted-foreground hover:text-foreground"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  # Request panel component
  attr :log, :map, required: true

  defp request_panel(assigns) do
    ~H"""
    <div class="space-y-6">
      <.data_box title="Headers" empty={is_nil(@log.request_headers) or map_size(@log.request_headers) == 0}>
        <pre class="text-sm font-mono text-foreground whitespace-pre-wrap leading-relaxed"><%= format_headers(@log.request_headers) %></pre>
      </.data_box>

      <.data_box title="Body" empty={is_nil(@log.request_body)}>
        <pre class="text-sm font-mono text-foreground whitespace-pre-wrap leading-relaxed"><%= format_body(@log.request_body) %></pre>
      </.data_box>
    </div>
    """
  end

  # Response panel component
  attr :log, :map, required: true

  defp response_panel(assigns) do
    ~H"""
    <div class="space-y-6">
      <.data_box title="Headers" empty={is_nil(@log.response_headers) or map_size(@log.response_headers) == 0}>
        <pre class="text-sm font-mono text-foreground whitespace-pre-wrap leading-relaxed"><%= format_headers(@log.response_headers) %></pre>
      </.data_box>

      <.data_box title="Body" empty={is_nil(@log.response_body)}>
        <pre class="text-sm font-mono text-foreground whitespace-pre-wrap leading-relaxed"><%= format_body(@log.response_body) %></pre>
      </.data_box>
    </div>
    """
  end

  # Data box component for headers/body
  attr :title, :string, required: true
  attr :empty, :boolean, default: false
  slot :inner_block

  defp data_box(assigns) do
    ~H"""
    <div class="border border-base rounded-lg overflow-hidden">
      <div class="bg-muted/50 px-4 py-2.5 border-b border-base">
        <h4 class="text-xs font-medium text-muted-foreground uppercase tracking-wide">{@title}</h4>
      </div>
      <div class="p-5 bg-card max-h-96 overflow-auto">
        <%= if @empty do %>
          <p class="text-muted-foreground">No {@title |> String.downcase()}</p>
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  # Components

  attr :method, :string, required: true

  defp method_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border",
      case @method do
        "GET" -> "bg-success-soft text-foreground-success-soft border-success"
        "POST" -> "bg-primary-soft text-foreground-soft border-primary/30"
        "PUT" -> "bg-warning-soft text-foreground-warning-soft border-warning"
        "PATCH" -> "bg-warning-soft text-foreground-warning-soft border-warning"
        "DELETE" -> "bg-danger-soft text-foreground-danger-soft border-danger"
        _ -> "bg-muted text-muted-foreground border-base"
      end
    ]}>
      {@method}
    </span>
    """
  end

  attr :status, :string, required: true
  attr :success, :boolean, required: true

  defp status_badge(assigns) do
    status_int =
      case Integer.parse(assigns.status || "") do
        {n, _} -> n
        :error -> nil
      end

    assigns = assign(assigns, :status_int, status_int)

    ~H"""
    <span class={[
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border",
      cond do
        not @success -> "bg-danger-soft text-foreground-danger-soft border-danger"
        is_nil(@status_int) -> "bg-muted text-muted-foreground border-base"
        @status_int >= 200 and @status_int < 300 -> "bg-success-soft text-foreground-success-soft border-success"
        @status_int >= 300 and @status_int < 400 -> "bg-warning-soft text-foreground-warning-soft border-warning"
        @status_int >= 400 -> "bg-danger-soft text-foreground-danger-soft border-danger"
        true -> "bg-muted text-muted-foreground border-base"
      end
    ]}>
      {@status || "—"}
    </span>
    """
  end

  defp format_headers(headers) when is_map(headers) do
    headers
    |> Enum.sort()
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join("\n")
  end

  defp format_headers(_), do: ""

  defp format_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> body
    end
  end

  defp format_body(body) when is_map(body) or is_list(body) do
    Jason.encode!(body, pretty: true)
  end

  defp format_body(body), do: inspect(body)
end
