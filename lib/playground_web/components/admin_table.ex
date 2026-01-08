defmodule PlaygroundWeb.Components.AdminTable do
  @moduledoc """
  Reusable admin table component with selection, bulk actions, and full-height layout.

  This component provides:
  - Row selection with checkboxes
  - Select all on current page
  - Bulk actions dropdown
  - Full-height table that fills available screen space
  - Consistent pagination
  """

  use Phoenix.Component
  import Fluxon.Components.Button
  import Fluxon.Components.Checkbox
  import Fluxon.Components.Dropdown

  @doc """
  Renders an admin table with selection and bulk actions.

  ## Attributes
  - `id` - Unique ID for the table
  - `rows` - The data rows to display
  - `meta` - Flop meta information
  - `selected_ids` - MapSet of selected row IDs
  - `path` - Base path for pagination links

  ## Slots
  - `col` - Column definitions with label and field attributes
  - `bulk_action` - Bulk action definitions
  - `row_action` - Per-row action buttons
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :meta, :map, required: true
  attr :selected_ids, :any, default: MapSet.new()
  attr :path, :string, required: true
  attr :row_id, :any, default: nil
  attr :show_checkboxes, :boolean, default: true
  attr :target, :any, default: nil
  attr :title, :string, default: nil
  attr :page_size_options, :list, default: [10, 25, 50, 100]

  slot :header_action
  slot :toolbar

  slot :col, required: true do
    attr :label, :string
    attr :field, :atom
    attr :sortable, :boolean
    attr :class, :string
    attr :td_class, :string
  end

  slot :bulk_action do
    attr :label, :string
    attr :icon, :string
    attr :event, :string
  end

  slot :row_action

  def admin_table(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <!-- Header with title and actions -->
      <div
        :if={@title || @header_action != []}
        class="px-4 py-3 border-b border-base flex items-center justify-between"
      >
        <h2 :if={@title} class="text-lg font-semibold text-foreground">{@title}</h2>
        <div :if={@title == nil}></div>
        <div :if={@header_action != []} class="flex items-center gap-2">
          {render_slot(@header_action)}
        </div>
      </div>

      <!-- Toolbar (search, filters) -->
      <div :if={@toolbar != []} class="px-4 py-3 border-b border-base">
        {render_slot(@toolbar)}
      </div>

      <!-- Selection Info Bar -->
      <div
        :if={@show_checkboxes}
        class="px-4 py-2 border-b border-base flex items-center justify-between min-h-[44px]"
      >
        <div class="flex items-center space-x-4">
          <%= if MapSet.size(@selected_ids) > 0 do %>
            <span class="text-sm text-foreground">
              {MapSet.size(@selected_ids)} {if MapSet.size(@selected_ids) == 1,
                do: "item",
                else: "items"} selected
            </span>
          <% else %>
            <span class="text-sm text-foreground-soft">No items selected</span>
          <% end %>
        </div>

        <!-- Bulk Actions Dropdown -->
        <div class={
          if MapSet.size(@selected_ids) > 0 && length(@bulk_action) > 0, do: "", else: "invisible"
        }>
          <.dropdown>
            <:toggle>
              <.button variant="outline" size="sm">
                Bulk Actions <.icon name="hero-chevron-down" class="size-4 ml-2" />
              </.button>
            </:toggle>
            <%= for action <- @bulk_action do %>
              <.dropdown_button phx-click={action.event} phx-target={@target}>
                <%= if action[:icon] do %>
                  <.icon name={action.icon} class="size-4 mr-2" />
                <% end %>
                {action.label} ({MapSet.size(@selected_ids)})
              </.dropdown_button>
            <% end %>
            <.dropdown_separator />
            <.dropdown_button phx-click="clear_selection" phx-target={@target}>
              <.icon name="hero-x-mark" class="size-4 mr-2" /> Clear Selection
            </.dropdown_button>
          </.dropdown>
        </div>
      </div>

      <!-- Table - fills available height -->
      <div class="flex-1 overflow-auto">
          <table class="min-w-full text-left text-sm text-foreground">
            <thead class="text-foreground-soft border-b border-base sticky top-0 z-10 bg-background">
              <tr>
                <th
                  :if={@show_checkboxes}
                  class="pl-4 sm:last:pr-1 px-3 py-2 text-left text-sm font-medium w-12"
                >
                  <.checkbox
                    name="select-all"
                    phx-click="select_all_page"
                    phx-target={@target}
                    checked={MapSet.size(@selected_ids) == length(@rows) && length(@rows) > 0}
                  />
                </th>
                <%= for col <- @col do %>
                  <th class={"first:pl-4 sm:last:pr-1 px-3 py-2 text-left text-sm font-medium #{col[:class]}"}>
                    <%= if col[:sortable] do %>
                      <.link
                        patch={build_sort_url(@path, @meta, col.field)}
                        class="flex items-center gap-1 hover:text-primary"
                      >
                        {col.label}
                        {render_sort_indicator(@meta, col.field)}
                      </.link>
                    <% else %>
                      {col.label}
                    <% end %>
                  </th>
                <% end %>
                <%= if length(@row_action) > 0 do %>
                  <th class="sm:first:pl-1 sm:last:pr-1 px-3 py-2 text-left text-sm font-medium w-16">
                    <span class="sr-only">Actions</span>
                  </th>
                <% end %>
              </tr>
            </thead>

            <tbody>
              <%= for row <- @rows do %>
                <tr class="border-b border-base last:border-b-0 hover:bg-muted/50">
                  <td
                    :if={@show_checkboxes}
                    class="pl-4 sm:last:pr-1 whitespace-nowrap py-2 px-3 w-12"
                  >
                    <.checkbox
                      name={"select-#{get_row_id(@row_id, row)}"}
                      phx-click="toggle_select"
                      phx-target={@target}
                      phx-value-id={get_row_id(@row_id, row)}
                      checked={MapSet.member?(@selected_ids, get_row_id(@row_id, row))}
                    />
                  </td>
                  <%= for col <- @col do %>
                    <td class={"first:pl-4 sm:last:pr-1 whitespace-nowrap py-2 px-3 #{col[:td_class]}"}>
                      {render_slot(col, row)}
                    </td>
                  <% end %>
                  <%= if length(@row_action) > 0 do %>
                    <td class="sm:first:pl-1 sm:last:pr-1 whitespace-nowrap py-2 px-3 text-right">
                      <div class="flex justify-end space-x-2">
                        <%= for action <- @row_action do %>
                          {render_slot(action, row)}
                        <% end %>
                      </div>
                    </td>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
          </table>
      </div>

      <!-- Pagination -->
      <%= if @meta do %>
        <% current_page = @meta.current_page || 1 %>
        <% total_pages = @meta.total_pages || 1 %>
        <% page_size = get_current_page_size(@meta) %>
        <% total_count = @meta.total_count || 0 %>
        <% start_item = if total_count > 0, do: (current_page - 1) * page_size + 1, else: 0 %>
        <% end_item = min(current_page * page_size, total_count) %>

        <div class="flex items-center justify-between border-t border-base px-4 py-3 sm:px-6">
          <!-- Mobile: Simple Previous/Next -->
          <div class="flex flex-1 justify-between sm:hidden">
            <%= if current_page > 1 do %>
              <.link
                patch={build_pagination_url(@path, @meta, current_page - 1)}
                class="relative inline-flex items-center rounded-md border border-base bg-card px-4 py-2 text-sm font-medium text-foreground hover:bg-muted"
              >
                Previous
              </.link>
            <% else %>
              <span class="relative inline-flex items-center rounded-md border border-base bg-card px-4 py-2 text-sm font-medium text-muted-foreground cursor-not-allowed">
                Previous
              </span>
            <% end %>
            <%= if current_page < total_pages do %>
              <.link
                patch={build_pagination_url(@path, @meta, current_page + 1)}
                class="relative ml-3 inline-flex items-center rounded-md border border-base bg-card px-4 py-2 text-sm font-medium text-foreground hover:bg-muted"
              >
                Next
              </.link>
            <% else %>
              <span class="relative ml-3 inline-flex items-center rounded-md border border-base bg-card px-4 py-2 text-sm font-medium text-muted-foreground cursor-not-allowed">
                Next
              </span>
            <% end %>
          </div>

          <!-- Desktop: Full pagination -->
          <div class="hidden sm:flex sm:flex-1 sm:items-center sm:justify-between">
            <div>
              <p class="text-sm text-muted-foreground">
                Showing
                <span class="font-medium text-foreground">{start_item}</span>
                to
                <span class="font-medium text-foreground">{end_item}</span>
                of
                <span class="font-medium text-foreground">{total_count}</span>
                results
              </p>
            </div>
            <div>
              <nav aria-label="Pagination" class="isolate inline-flex -space-x-px rounded-md shadow-base">
                <!-- Previous arrow -->
                <%= if current_page > 1 do %>
                  <.link
                    patch={build_pagination_url(@path, @meta, current_page - 1)}
                    class="relative inline-flex items-center rounded-l-md border border-base bg-card px-2 py-2 text-foreground-soft hover:bg-muted focus:z-20 focus:outline-offset-0"
                  >
                    <span class="sr-only">Previous</span>
                    <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="size-5">
                      <path d="M11.78 5.22a.75.75 0 0 1 0 1.06L8.06 10l3.72 3.72a.75.75 0 1 1-1.06 1.06l-4.25-4.25a.75.75 0 0 1 0-1.06l4.25-4.25a.75.75 0 0 1 1.06 0Z" clip-rule="evenodd" fill-rule="evenodd" />
                    </svg>
                  </.link>
                <% else %>
                  <span class="relative inline-flex items-center rounded-l-md border border-base bg-card px-2 py-2 text-foreground-softest cursor-not-allowed">
                    <span class="sr-only">Previous</span>
                    <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="size-5">
                      <path d="M11.78 5.22a.75.75 0 0 1 0 1.06L8.06 10l3.72 3.72a.75.75 0 1 1-1.06 1.06l-4.25-4.25a.75.75 0 0 1 0-1.06l4.25-4.25a.75.75 0 0 1 1.06 0Z" clip-rule="evenodd" fill-rule="evenodd" />
                    </svg>
                  </span>
                <% end %>

                <!-- Page numbers -->
                <%= for page_item <- build_page_list(current_page, total_pages) do %>
                  <%= if page_item == :ellipsis do %>
                    <span class="relative inline-flex items-center border border-base bg-card px-4 py-2 text-sm font-semibold text-foreground-soft">...</span>
                  <% else %>
                    <%= if page_item == current_page do %>
                      <span aria-current="page" class="relative z-10 inline-flex items-center border border-primary bg-primary px-4 py-2 text-sm font-semibold text-foreground-primary focus:z-20">{page_item}</span>
                    <% else %>
                      <.link
                        patch={build_pagination_url(@path, @meta, page_item)}
                        class="relative inline-flex items-center border border-base bg-card px-4 py-2 text-sm font-semibold text-foreground hover:bg-muted focus:z-20 focus:outline-offset-0"
                      >
                        {page_item}
                      </.link>
                    <% end %>
                  <% end %>
                <% end %>

                <!-- Next arrow -->
                <%= if current_page < total_pages do %>
                  <.link
                    patch={build_pagination_url(@path, @meta, current_page + 1)}
                    class="relative inline-flex items-center rounded-r-md border border-base bg-card px-2 py-2 text-foreground-soft hover:bg-muted focus:z-20 focus:outline-offset-0"
                  >
                    <span class="sr-only">Next</span>
                    <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="size-5">
                      <path d="M8.22 5.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L11.94 10 8.22 6.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
                    </svg>
                  </.link>
                <% else %>
                  <span class="relative inline-flex items-center rounded-r-md border border-base bg-card px-2 py-2 text-foreground-softest cursor-not-allowed">
                    <span class="sr-only">Next</span>
                    <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="size-5">
                      <path d="M8.22 5.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L11.94 10 8.22 6.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
                    </svg>
                  </span>
                <% end %>
              </nav>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper to get row ID
  defp get_row_id(nil, row), do: Map.get(row, :id)
  defp get_row_id(row_id_fn, row) when is_function(row_id_fn), do: row_id_fn.(row)

  # Get current page size from meta
  defp get_current_page_size(%{flop: %{page_size: page_size}}) when is_integer(page_size), do: page_size
  defp get_current_page_size(_meta), do: 10

  # Build page list with ellipsis for pagination
  # Shows: 1 ... current-1 current current+1 ... last
  defp build_page_list(_current_page, total_pages) when total_pages <= 7 do
    Enum.to_list(1..total_pages)
  end

  defp build_page_list(current_page, total_pages) do
    # Always show first page, last page, and pages around current
    pages = MapSet.new([1, total_pages])

    # Add pages around current
    pages =
      (current_page - 1)..(current_page + 1)
      |> Enum.filter(&(&1 >= 1 and &1 <= total_pages))
      |> Enum.reduce(pages, &MapSet.put(&2, &1))

    # Convert to sorted list
    sorted_pages = pages |> MapSet.to_list() |> Enum.sort()

    # Insert ellipsis where there are gaps
    sorted_pages
    |> Enum.reduce({[], 0}, fn page, {acc, prev} ->
      if prev > 0 and page - prev > 1 do
        {acc ++ [:ellipsis, page], page}
      else
        {acc ++ [page], page}
      end
    end)
    |> elem(0)
  end

  # Pagination URL builder
  defp build_pagination_url(path, meta, page) do
    params = Map.get(meta, :params, %{})
    flop = meta.flop || %{}

    params = Map.put(params, "page", page)

    # Preserve page_size if it exists
    page_size = Map.get(flop, :page_size)
    params = if page_size, do: Map.put(params, "page_size", page_size), else: params

    # Preserve order if it exists
    order_by = Map.get(flop, :order_by, [])
    order_directions = Map.get(flop, :order_directions, [:asc])

    params =
      if order_by != [] do
        params
        |> Map.put("order_by", Enum.map(order_by, &to_string/1))
        |> Map.put("order_directions", Enum.map(order_directions, &to_string/1))
      else
        params
      end

    "#{path}?#{encode_params(params)}"
  end

  # Sort URL builder
  defp build_sort_url(path, meta, field) do
    params = Map.get(meta, :params, %{})
    current_order_by = params["order_by"] || Map.get(meta.flop, :order_by)
    current_directions = params["order_directions"] || Map.get(meta.flop, :order_directions, ["asc"])

    {order_by, order_directions} =
      if current_order_by == [Atom.to_string(field)] || current_order_by == [field] do
        current_direction = List.first(current_directions)

        current_dir_atom =
          if is_binary(current_direction),
            do: String.to_atom(current_direction),
            else: current_direction

        new_direction = if current_dir_atom == :asc, do: "desc", else: "asc"
        {[Atom.to_string(field)], [new_direction]}
      else
        {[Atom.to_string(field)], ["asc"]}
      end

    params =
      params
      |> Map.put("order_by", order_by)
      |> Map.put("order_directions", order_directions)
      |> Map.delete("page")

    "#{path}?#{encode_params(params)}"
  end

  # Sort indicator renderer
  defp render_sort_indicator(meta, field) do
    params = Map.get(meta, :params, %{})
    current_order_by = params["order_by"] || Map.get(meta.flop, :order_by)

    if current_order_by == [Atom.to_string(field)] || current_order_by == [field] do
      current_directions = params["order_directions"] || Map.get(meta.flop, :order_directions, ["asc"])
      dir = List.first(current_directions)

      dir_atom =
        cond do
          is_atom(dir) -> dir
          is_binary(dir) -> String.to_atom(dir)
          true -> :asc
        end

      is_descending = dir_atom == :desc
      assigns = %{is_descending: is_descending}

      ~H"""
      <.icon
        name={if @is_descending, do: "hero-chevron-down", else: "hero-chevron-up"}
        class="size-3"
      />
      """
    else
      ""
    end
  end

  defp encode_params(params) do
    params
    |> Enum.flat_map(fn
      {k, v} when is_list(v) ->
        Enum.map(v, fn item ->
          "#{k}[]=#{URI.encode_www_form(to_string(item))}"
        end)

      {k, v} ->
        ["#{k}=#{URI.encode_www_form(to_string(v))}"]
    end)
    |> Enum.join("&")
  end

  defp icon(assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end
end
