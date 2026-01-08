defmodule PlaygroundWeb.AdminAPILogsLive.Index do
  @moduledoc """
  LiveView for viewing API request logs.
  """

  use PlaygroundWeb, :live_view

  import Ecto.Query
  alias Playground.{Repo, APIRequestLog}
  import PlaygroundWeb.Components.AdminTable

  @impl true
  def mount(_params, _session, socket) do
    services = get_unique_services()

    breadcrumbs = [
      %{label: "Admin", path: ~p"/admin"},
      %{label: "API Request Logs", path: nil}
    ]

    {:ok,
     socket
     |> assign(:page_title, "API Request Logs")
     |> assign(:breadcrumbs, breadcrumbs)
     |> assign(:services, services)
     |> assign(:stats, nil)
     |> assign(:selected_ids, MapSet.new())
     |> load_results(%{})}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> load_results(params)
      |> maybe_load_stats(params)

    {:noreply, socket}
  end

  defp load_results(socket, params) do
    query = from(l in APIRequestLog)

    query = apply_search_filter(query, params)
    query = apply_service_filter(query, params)
    query = apply_method_filter(query, params)
    query = apply_success_filter(query, params)

    case Flop.validate_and_run(query, params, for: APIRequestLog) do
      {:ok, {logs, meta}} ->
        meta = Map.put(meta, :params, params)

        socket
        |> assign(:logs, logs)
        |> assign(:meta, meta)

      {:error, meta} ->
        socket
        |> assign(:logs, [])
        |> assign(:meta, meta)
    end
  end

  defp maybe_load_stats(socket, params) do
    service = Map.get(params, "service")

    if service && service != "" do
      stats = calculate_service_stats(service)
      assign(socket, :stats, stats)
    else
      assign(socket, :stats, calculate_overall_stats())
    end
  end

  defp apply_search_filter(query, %{"search" => search}) when search != "" do
    search_term = "%#{search}%"
    from l in query, where: ilike(l.url, ^search_term) or ilike(l.path, ^search_term)
  end

  defp apply_search_filter(query, _), do: query

  defp apply_service_filter(query, %{"service" => service}) when service != "" do
    from l in query, where: l.service == ^service
  end

  defp apply_service_filter(query, _), do: query

  defp apply_method_filter(query, %{"method" => method}) when method != "" do
    from l in query, where: l.method == ^method
  end

  defp apply_method_filter(query, _), do: query

  defp apply_success_filter(query, %{"success" => "true"}) do
    from l in query, where: l.success == true
  end

  defp apply_success_filter(query, %{"success" => "false"}) do
    from l in query, where: l.success == false
  end

  defp apply_success_filter(query, _), do: query

  defp get_unique_services do
    from(l in APIRequestLog, select: l.service, distinct: true, order_by: l.service)
    |> Repo.all()
  end

  defp calculate_service_stats(service) do
    since = DateTime.add(DateTime.utc_now(), -24, :hour)

    query =
      from l in APIRequestLog,
        where: l.service == ^service and l.inserted_at >= ^since

    logs = Repo.all(query)
    calculate_stats_from_logs(logs)
  end

  defp calculate_overall_stats do
    since = DateTime.add(DateTime.utc_now(), -24, :hour)

    query = from l in APIRequestLog, where: l.inserted_at >= ^since

    logs = Repo.all(query)
    calculate_stats_from_logs(logs)
  end

  defp calculate_stats_from_logs(logs) do
    if Enum.empty?(logs) do
      %{
        total: 0,
        success_count: 0,
        error_count: 0,
        success_rate: 0.0,
        avg_duration_ms: 0,
        total_cost_usd: Decimal.new("0.00"),
        total_tokens: 0
      }
    else
      total = length(logs)
      success_count = Enum.count(logs, & &1.success)
      error_count = total - success_count
      durations = Enum.map(logs, & &1.duration_ms) |> Enum.reject(&is_nil/1)

      avg_duration =
        if Enum.empty?(durations), do: 0, else: Enum.sum(durations) / length(durations)

      # Calculate cost and token totals
      total_cost =
        logs
        |> Enum.map(& &1.cost_usd)
        |> Enum.reject(&is_nil/1)
        |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

      total_tokens =
        logs
        |> Enum.map(& &1.tokens_total)
        |> Enum.reject(&is_nil/1)
        |> Enum.sum()

      %{
        total: total,
        success_count: success_count,
        error_count: error_count,
        success_rate: if(total > 0, do: success_count / total * 100, else: 0.0),
        avg_duration_ms: round(avg_duration),
        total_cost_usd: total_cost,
        total_tokens: total_tokens
      }
    end
  end

  @impl true
  def handle_event("update-filter", params, socket) do
    existing_params = Map.get(socket.assigns.meta, :params, %{})

    filter_params =
      existing_params
      |> update_if_changed(params, "search")
      |> update_if_changed(params, "service")
      |> update_if_changed(params, "method")
      |> update_if_changed(params, "success")

    if filter_params != existing_params do
      {:noreply, push_patch(socket, to: ~p"/admin/api-logs?#{filter_params}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear-filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/api-logs")}
  end

  @impl true
  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    existing_params = Map.get(socket.assigns.meta, :params, %{})
    new_params = Map.put(existing_params, "page_size", page_size) |> Map.delete("page")
    {:noreply, push_patch(socket, to: ~p"/admin/api-logs?#{new_params}")}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected_ids =
      if MapSet.member?(socket.assigns.selected_ids, id) do
        MapSet.delete(socket.assigns.selected_ids, id)
      else
        MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, :selected_ids, selected_ids)}
  end

  @impl true
  def handle_event("select_all_page", _params, socket) do
    all_ids = Enum.map(socket.assigns.logs, & &1.id) |> MapSet.new()

    selected_ids =
      if MapSet.equal?(socket.assigns.selected_ids, all_ids) do
        MapSet.new()
      else
        all_ids
      end

    {:noreply, assign(socket, :selected_ids, selected_ids)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  @impl true
  def handle_event("open_bulk_delete", _params, socket) do
    {:noreply, Fluxon.open_dialog(socket, "bulk-delete-modal")}
  end

  @impl true
  def handle_event("confirm_bulk_delete", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_ids)

    # Use delete_all for efficient bulk deletion (no N+1 query)
    {deleted_count, _} =
      from(log in APIRequestLog, where: log.id in ^selected_ids)
      |> Repo.delete_all()

    socket =
      socket
      |> put_flash(:info, "Successfully deleted #{deleted_count} log(s)")
      |> assign(:selected_ids, MapSet.new())
      |> Fluxon.close_dialog("bulk-delete-modal")
      |> load_results(socket.assigns.meta.params)

    {:noreply, socket}
  end

  # Helper functions
  defp update_if_changed(existing, new_params, key) do
    case Map.get(new_params, key) do
      nil -> existing
      "" -> Map.delete(existing, key)
      value -> Map.put(existing, key, value)
    end
  end

  defp has_active_filters?(meta) do
    params = Map.get(meta, :params, %{})

    Enum.any?(params, fn
      {"search", value} -> value != ""
      {"service", value} -> value != ""
      {"method", value} -> value != ""
      {"success", value} -> value != ""
      _ -> false
    end)
  end

  defp get_filter_value(meta, key) do
    case meta do
      %{params: params} when is_map(params) -> Map.get(params, key, "")
      _ -> ""
    end
  end

  defp get_page_size(meta) do
    case meta do
      %{flop: %{page_size: page_size}} when is_integer(page_size) -> to_string(page_size)
      %{params: %{"page_size" => page_size}} -> page_size
      _ -> "50"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- Stats Dashboard -->
    <%= if @stats do %>
      <div class="grid grid-cols-2 lg:grid-cols-6 gap-4 mb-6">
        <.stat_card
          title="Total Requests"
          value={@stats.total}
          subtitle="Last 24 hours"
          icon="hero-arrow-path"
        />
        <.stat_card
          title="Success Rate"
          value={"#{Float.round(@stats.success_rate, 1)}%"}
          subtitle={"#{@stats.success_count} successful"}
          icon="hero-check-circle"
        />
        <.stat_card
          title="Avg Response"
          value={"#{@stats.avg_duration_ms}ms"}
          icon="hero-clock"
        />
        <.stat_card
          title="Errors"
          value={@stats.error_count}
          icon="hero-exclamation-triangle"
        />
        <.stat_card
          title="Total Cost"
          value={"$#{Decimal.round(@stats.total_cost_usd, 4)}"}
          subtitle="Last 24 hours"
          icon="hero-currency-dollar"
        />
        <.stat_card
          title="Tokens Used"
          value={format_number(@stats.total_tokens)}
          subtitle="Last 24 hours"
          icon="hero-calculator"
        />
      </div>
    <% end %>

    <div class="bg-card border border-base shadow-sm rounded-lg overflow-hidden flex-1 flex flex-col min-h-0">
      <.admin_table
        id="api-logs-table"
        rows={@logs}
        meta={@meta}
        path={~p"/admin/api-logs"}
        selected_ids={@selected_ids}
        show_checkboxes={true}
        title="Request Logs"
      >
        <:toolbar>
          <.form for={%{}} phx-change="update-filter" class="flex items-center gap-3">
            <div class="flex-1">
              <.input
                type="text"
                name="search"
                value={get_filter_value(@meta, "search")}
                placeholder="Search URL..."
                phx-debounce="300"
              />
            </div>

            <div class="relative">
              <.button
                type="button"
                variant="outline"
                size="sm"
                phx-click={JS.toggle(to: "#filters-dropdown")}
              >
                <.icon name="hero-funnel" class="size-4 mr-2" />
                Filters
                <%= if has_active_filters?(@meta) do %>
                  <.badge color="primary" class="ml-2">
                    <%= Enum.count([@meta.params["service"], @meta.params["method"], @meta.params["success"]], & &1) %>
                  </.badge>
                <% end %>
              </.button>

              <div
                id="filters-dropdown"
                phx-click-away={JS.hide(to: "#filters-dropdown")}
                class="hidden absolute right-0 top-full mt-2 w-72 bg-overlay border border-base rounded-base shadow-lg p-4 z-50"
              >
                <div class="flex items-center justify-between mb-4">
                  <h3 class="text-base font-semibold text-foreground">Filters</h3>
                  <%= if has_active_filters?(@meta) do %>
                    <.button
                      type="button"
                      variant="ghost"
                      size="sm"
                      phx-click={
                        JS.dispatch("reset", to: "form")
                        |> JS.push("clear-filters")
                        |> JS.hide(to: "#filters-dropdown")
                      }
                    >
                      <.icon name="hero-x-mark" class="size-4 mr-1" />
                      Clear
                    </.button>
                  <% end %>
                </div>

                <div class="space-y-4">
                  <div>
                    <.label>Service</.label>
                    <.select
                      name="service"
                      value={get_filter_value(@meta, "service")}
                      options={[{"All services", ""} | Enum.map(@services, &{&1, &1})]}
                    />
                  </div>

                  <div>
                    <.label>Method</.label>
                    <.select
                      name="method"
                      value={get_filter_value(@meta, "method")}
                      options={[
                        {"All methods", ""},
                        {"GET", "GET"},
                        {"POST", "POST"},
                        {"PUT", "PUT"},
                        {"PATCH", "PATCH"},
                        {"DELETE", "DELETE"}
                      ]}
                    />
                  </div>

                  <div>
                    <.label>Status</.label>
                    <.select
                      name="success"
                      value={get_filter_value(@meta, "success")}
                      options={[
                        {"All statuses", ""},
                        {"Success", "true"},
                        {"Failed", "false"}
                      ]}
                    />
                  </div>

                  <div>
                    <.label>Rows per page</.label>
                    <.select
                      name="page_size"
                      value={get_page_size(@meta)}
                      phx-change="change_page_size"
                      options={[
                        {"10", "10"},
                        {"25", "25"},
                        {"50", "50"},
                        {"100", "100"}
                      ]}
                    />
                  </div>
                </div>
              </div>
            </div>
          </.form>
        </:toolbar>

        <:col :let={log} label="Time" field={:inserted_at} sortable>
          <time datetime={log.inserted_at} title={DateTime.to_string(log.inserted_at)} class="text-muted-foreground">
            {format_time(log.inserted_at)}
          </time>
        </:col>

        <:col :let={log} label="Service" field={:service} sortable>
          {log.service}
        </:col>

        <:col :let={log} label="Request" td_class="max-w-md truncate">
          <span class="font-mono text-muted-foreground">{log.method}</span>
          <span class="ml-2 font-mono">{log.path}</span>
        </:col>

        <:col :let={log} label="Status">
          <.status_badge status={log.status_code} success={log.success} />
        </:col>

        <:col :let={log} label="Duration" field={:duration_ms} sortable>
          <span class="text-muted-foreground font-mono">{log.duration_ms}ms</span>
        </:col>

        <:col :let={log} label="Tokens">
          <span class="text-muted-foreground font-mono">{format_tokens(log.tokens_total)}</span>
        </:col>

        <:col :let={log} label="Cost">
          <span class="text-muted-foreground font-mono">{format_cost(log.cost_usd)}</span>
        </:col>

        <:bulk_action label="Delete Selected" icon="hero-trash" event="open_bulk_delete" />

        <:row_action :let={log}>
          <.link navigate={~p"/admin/api-logs/#{log.id}"} class="text-muted-foreground hover:text-foreground">
            <.icon name="hero-chevron-right" class="size-4" />
          </.link>
        </:row_action>
      </.admin_table>

      <!-- Empty state -->
      <%= if length(@logs) == 0 do %>
        <div class="text-center py-12">
          <.icon name="hero-signal" class="mx-auto h-12 w-12 text-muted-foreground" />
          <h3 class="mt-2 text-sm font-medium text-foreground">No API requests logged</h3>
          <p class="mt-1 text-sm text-muted-foreground">
            <%= if has_active_filters?(@meta) do %>
              Try adjusting your filters.
            <% else %>
              API requests will appear here as they are made.
            <% end %>
          </p>
        </div>
      <% end %>
    </div>

    <!-- Bulk Delete Confirmation Modal -->
    <.modal id="bulk-delete-modal" class="max-w-md w-full">
      <h3 class="text-base font-semibold leading-6 text-foreground mb-4">
        Delete API Logs
      </h3>

      <p class="text-sm text-muted-foreground">
        Are you sure you want to delete <strong>{MapSet.size(@selected_ids)}</strong> log(s)?
        This action cannot be undone.
      </p>

      <div class="flex justify-end gap-3 mt-6">
        <.button
          variant="outline"
          phx-click={Fluxon.close_dialog("bulk-delete-modal")}
        >
          Cancel
        </.button>
        <.button
          variant="solid"
          color="danger"
          phx-click="confirm_bulk_delete"
        >
          Delete All
        </.button>
      </div>
    </.modal>
    """
  end

  # Status badge component
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
      "inline-flex items-centers rounded px-2 py-0.5 text-xs font-medium font-mono border",
      cond do
        not @success -> "bg-danger-soft text-foreground-danger-soft border-danger"
        is_nil(@status_int) -> "bg-muted text-muted-foreground border-base"
        @status_int >= 200 and @status_int < 300 -> "bg-success-soft text-foreground-success-soft border-success"
        @status_int >= 300 and @status_int < 400 -> "bg-muted text-muted-foreground border-base"
        @status_int >= 400 -> "bg-danger-soft text-foreground-danger-soft border-danger"
        true -> "bg-muted text-muted-foreground border-base"
      end
    ]}>
      {@status || "—"}
    </span>
    """
  end

  defp format_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> Calendar.strftime(datetime, "%b %d, %H:%M")
    end
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_number(_), do: "0"

  defp format_cost(nil), do: "-"
  defp format_cost(cost), do: "$#{Decimal.round(cost, 6)}"

  defp format_tokens(nil), do: "-"
  defp format_tokens(tokens), do: format_number(tokens)

  # Stat card component
  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :subtitle, :string, default: nil
  attr :icon, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-card border border-base rounded-lg p-4 shadow-sm">
      <div class="flex items-start justify-between">
        <div class="flex-1">
          <p class="text-sm font-medium text-muted-foreground">{@title}</p>
          <p class="text-2xl font-semibold mt-1 tabular-nums text-foreground">
            {@value}
          </p>
          <p :if={@subtitle} class="text-xs text-muted-foreground mt-1">{@subtitle}</p>
        </div>
        <div class="p-2 rounded-lg bg-muted">
          <.icon name={@icon} class="size-5 text-muted-foreground" />
        </div>
      </div>
    </div>
    """
  end
end
