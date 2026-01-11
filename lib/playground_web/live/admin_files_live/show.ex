defmodule PlaygroundWeb.AdminFilesLive.Show do
  @moduledoc """
  File detail page showing file information and associated chunks.
  """
  use PlaygroundWeb, :live_view

  import Ecto.Query
  import PlaygroundWeb.Components.AdminTable
  import PlaygroundWeb.Components.PipelineSteps

  alias Playground.Repo
  alias Playground.Files.File
  alias Playground.Files.PubSub
  alias Playground.RAG.Chunk
  alias Playground.RAG.EventLog

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Subscribe to updates for this specific file
    if connected?(socket) do
      PubSub.subscribe_to_file(id)
    end

    file = load_file(id)

    {:ok,
     socket
     |> assign(:page_title, file.name)
     |> assign(:page_title_suffix, title_suffix(file))
     |> assign(:breadcrumbs, [
       %{label: "Admin", path: ~p"/admin"},
       %{label: "Files", path: ~p"/admin/files"},
       %{label: file.name}
     ])
     |> assign(:file, file)
     |> assign(:active_tab, "details")
     |> assign(:selected_error_event, nil)
     |> assign(:selected_chunk, nil)
     |> load_events(%{})
     |> load_chunks(%{})}
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Only apply URL params to the active tab's table
    # This prevents one tab's pagination/sorting from affecting another
    socket =
      case socket.assigns.active_tab do
        "history" -> load_events(socket, params)
        "chunks" -> load_chunks(socket, params)
        _ -> socket
      end

    {:noreply, socket}
  end

  defp load_file(file_id) do
    Repo.get!(File, file_id)
    |> Repo.preload(connector_organization: :connector)
  end

  defp title_suffix(file) do
    assigns = %{file: file, external_link: external_link(file), connector_key: connector_key(file)}

    ~H"""
    <div class="flex items-center gap-2">
      <span class="inline-flex items-center px-2 py-0.5 text-xs font-medium rounded bg-muted text-muted-foreground">
        v<%= @file.processing_revision %>
      </span>
      <%= if @external_link do %>
        <a
          href={@external_link}
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs font-medium rounded bg-muted/50 text-foreground hover:bg-muted transition-colors"
        >
          <.connector_icon key={@connector_key} />
          <span><%= @file.connector_organization.connector.name %></span>
          <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 text-muted-foreground" />
        </a>
      <% else %>
        <span class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs font-medium rounded bg-muted/50 text-muted-foreground">
          <.connector_icon key={@connector_key} />
          <span><%= @file.connector_organization.connector.name %></span>
        </span>
      <% end %>
    </div>
    """
  end

  defp load_events(socket, params) do
    file_id = socket.assigns.file.id

    query = from(e in EventLog, where: e.file_id == ^file_id)

    case Flop.validate_and_run(query, params, for: EventLog) do
      {:ok, {events, meta}} ->
        assign(socket, events: events, events_meta: meta)

      {:error, _meta} ->
        assign(socket, events: [], events_meta: %Flop.Meta{})
    end
  end

  defp load_chunks(socket, params) do
    file_id = socket.assigns.file.id

    query =
      from(c in Chunk,
        where: c.file_id == ^file_id,
        select: %{
          id: c.id,
          file_id: c.file_id,
          content: c.content,
          metadata: c.metadata,
          revision: c.revision,
          position: c.position,
          chunk_hash: c.chunk_hash,
          start_byte: c.start_byte,
          end_byte: c.end_byte,
          inserted_at: c.inserted_at,
          updated_at: c.updated_at,
          has_embedding: not is_nil(c.embedding)
        }
      )

    case Flop.validate_and_run(query, params, for: Chunk) do
      {:ok, {chunks, meta}} ->
        assign(socket, chunks: chunks, meta: meta)

      {:error, _meta} ->
        assign(socket, chunks: [], meta: %Flop.Meta{})
    end
  end

  # PubSub message handlers for real-time updates from Machinery state machine
  @file_events [
    :file_downloading,
    :file_chunking,
    :file_chunked,
    :file_embedding,
    :file_ready,
    :file_failed,
    :file_reset,
    # Legacy events for backwards compatibility
    :file_updated,
    :file_processing_started
  ]

  @impl true
  def handle_info({event_type, updated_file}, socket) when event_type in @file_events do
    # Reload file data, events, and chunks when file status changes
    file = load_file(updated_file.id)

    {:noreply,
     socket
     |> assign(:file, file)
     |> load_events(Map.get(socket.assigns.events_meta, :params) || %{})
     |> load_chunks(Map.get(socket.assigns.meta, :params) || %{})}
  end

  @impl true
  def handle_event("start_processing", _params, socket) do
    file = socket.assigns.file

    if can_trigger_next_step?(file) do
      # Enqueue the processing worker - the worker will transition states and broadcast updates
      Playground.RAG.Workers.ProcessTextFileWorker.new(%{file_id: file.id})
      |> Oban.insert()

      {:noreply, put_flash(socket, :info, "Processing queued for #{file.name}")}
    else
      {:noreply, put_flash(socket, :error, "Cannot start processing for this file")}
    end
  end

  @impl true
  def handle_event("reset_file", _params, socket) do
    file = socket.assigns.file

    case Playground.Files.reset_file_for_reprocessing(file) do
      {:ok, _updated_file} ->
        # Reload file with proper preloads
        reloaded_file = load_file(file.id)

        {:noreply,
         socket
         |> assign(:file, reloaded_file)
         |> load_events(%{})
         |> load_chunks(%{})
         |> put_flash(:info, "File reset to draft. Ready for reprocessing.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reset file: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    # Reset URL params and reload data when switching tabs
    socket =
      socket
      |> assign(:active_tab, tab)
      |> then(fn s ->
        case tab do
          "history" -> load_events(s, %{})
          "chunks" -> load_chunks(s, %{})
          _ -> s
        end
      end)
      |> push_patch(to: ~p"/admin/files/#{socket.assigns.file.id}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_error", %{"event-id" => event_id}, socket) do
    event = Enum.find(socket.assigns.events, &(to_string(&1.id) == event_id))

    {:noreply,
     socket
     |> assign(:selected_error_event, event)
     |> Fluxon.open_dialog("error-details-modal")}
  end

  @impl true
  def handle_event("show_chunk", %{"chunk-id" => chunk_id}, socket) do
    chunk = Enum.find(socket.assigns.chunks, &(to_string(&1.id) == chunk_id))

    {:noreply,
     socket
     |> assign(:selected_chunk, chunk)
     |> Fluxon.open_dialog("chunk-details-modal")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <!-- Main Content -->
      <div class={[
        "flex-1",
        if(@active_tab in ["chunks", "history"], do: "flex flex-col overflow-hidden", else: "space-y-4 sm:space-y-6")
      ]}>
        <!-- Processing Pipeline Progress (Always Visible) -->
        <div class="bg-card border border-base shadow-sm rounded-lg p-4 sm:p-5 mb-4 sm:mb-6 shrink-0">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-sm font-medium text-foreground">Processing Pipeline</h2>
            <div class="flex gap-2">
              <%= if can_reset?(@file) do %>
                <.button phx-click="reset_file" variant="outline" size="sm">
                  <.icon name="hero-arrow-path" class="w-4 h-4 sm:mr-1.5" />
                  <span class="hidden sm:inline">Reset</span>
                </.button>
              <% end %>
              <%= if can_trigger_next_step?(@file) do %>
                <.button phx-click="start_processing" variant="solid" color="primary" size="sm">
                  <.icon name="hero-play" class="w-4 h-4 sm:mr-1.5" />
                  <span class="hidden sm:inline"><%= next_step_action_text(@file) %></span>
                  <span class="sm:hidden">Start</span>
                </.button>
              <% end %>
            </div>
          </div>
          <.progress_bar
            steps={pipeline_step_labels()}
            current_step={current_pipeline_step(@file)}
            status_text={pipeline_status_text(@file)}
            status={pipeline_status(@file)}
          />
        </div>

        <!-- Tabs -->
        <div class={["flex flex-col", if(@active_tab in ["chunks", "history"], do: "flex-1 min-h-0")]}>
          <div class="overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0">
            <.tabs>
              <.tabs_list variant="segmented" class="min-w-max">
                <:tab name="details" phx-click="switch_tab" phx-value-tab="details">
                  <.icon name="hero-document-text" class="w-4 h-4 sm:mr-1.5" />
                  <span class="hidden sm:inline">Details</span>
                </:tab>
                <:tab name="history" phx-click="switch_tab" phx-value-tab="history">
                  <.icon name="hero-clock" class="w-4 h-4 sm:mr-1.5" />
                  <span class="hidden sm:inline">History</span>
                  <span class="ml-1 px-1.5 py-0.5 text-xs rounded bg-muted text-muted-foreground"><%= get_total_count(@events_meta) %></span>
                </:tab>
                <:tab name="chunks" phx-click="switch_tab" phx-value-tab="chunks">
                  <.icon name="hero-squares-2x2" class="w-4 h-4 sm:mr-1.5" />
                  <span class="hidden sm:inline">Chunks</span>
                    <span class="ml-1 px-1.5 py-0.5 text-xs rounded bg-muted text-muted-foreground"><%= get_total_count(@meta) %></span>
                </:tab>
              </.tabs_list>
            </.tabs>
          </div>

          <!-- Tab Panels -->
          <div class={["mt-4", if(@active_tab in ["chunks", "history"], do: "flex flex-col flex-1 min-h-0")]}>
            <!-- Details Tab -->
            <%= if @active_tab == "details" do %>
            <div class="bg-card border border-base shadow-sm rounded-lg p-4 sm:p-6">
              <dl class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
                <div>
                  <dt class="text-sm font-medium text-muted-foreground">File Name</dt>
                  <dd class="mt-1 text-sm text-foreground break-words"><%= @file.name %></dd>
                </div>

                <div>
                  <dt class="text-sm font-medium text-muted-foreground">MIME Type</dt>
                  <dd class="mt-1 text-sm text-foreground break-all"><%= @file.mime_type %></dd>
                </div>

                <div>
                  <dt class="text-sm font-medium text-muted-foreground">Size</dt>
                  <dd class="mt-1 text-sm text-foreground">
                    <%= if @file.size_bytes, do: format_bytes(@file.size_bytes), else: "-" %>
                  </dd>
                </div>

                <div>
                  <dt class="text-sm font-medium text-muted-foreground">Sync Status</dt>
                  <dd class="mt-1">
                    <.badge color={sync_status_color(@file.sync_status)}>
                      <%= @file.sync_status %>
                    </.badge>
                  </dd>
                </div>

                <div>
                  <dt class="text-sm font-medium text-muted-foreground">Processing Status</dt>
                  <dd class="mt-1">
                    <.badge color={processing_status_color(@file.processing_status)}>
                      <%= @file.processing_status %>
                    </.badge>
                  </dd>
                </div>

                <div>
                  <dt class="text-sm font-medium text-muted-foreground">Processing Revision</dt>
                  <dd class="mt-1 text-sm text-foreground"><%= @file.processing_revision %></dd>
                </div>

                <div class="sm:col-span-2 lg:col-span-1">
                  <dt class="text-sm font-medium text-muted-foreground">Provider File ID</dt>
                  <dd class="mt-1 text-sm text-foreground font-mono text-xs break-all">
                    <%= @file.provider_file_id %>
                  </dd>
                </div>

                <div>
                  <dt class="text-sm font-medium text-muted-foreground">Connector</dt>
                  <dd class="mt-1 text-sm text-foreground">
                    <%= @file.connector_organization.connector.name %>
                  </dd>
                </div>

                <div>
                  <dt class="text-sm font-medium text-muted-foreground">Parent Folder</dt>
                  <dd class="mt-1 text-sm text-foreground font-mono text-xs break-all">
                    <%= @file.parent_folder_id || "-" %>
                  </dd>
                </div>

                <div>
                  <dt class="text-sm font-medium text-muted-foreground">Synced At</dt>
                  <dd class="mt-1 text-sm text-foreground">
                    <%= if @file.synced_at, do: format_datetime(@file.synced_at), else: "-" %>
                  </dd>
                </div>

                <div>
                  <dt class="text-sm font-medium text-muted-foreground">Last Modified</dt>
                  <dd class="mt-1 text-sm text-foreground">
                    <%= if @file.updated_at, do: format_datetime(@file.updated_at), else: "-" %>
                  </dd>
                </div>

                <div>
                  <dt class="text-sm font-medium text-muted-foreground">Created</dt>
                  <dd class="mt-1 text-sm text-foreground">
                    <%= if @file.inserted_at, do: format_datetime(@file.inserted_at), else: "-" %>
                  </dd>
                </div>
              </dl>
            </div>
          <% end %>

          <!-- History Tab -->
          <%= if @active_tab == "history" do %>
            <%= if @events == [] do %>
              <div class="bg-card border border-base shadow-sm rounded-lg p-6 sm:p-8 text-center">
                <.icon name="hero-clock" class="w-10 h-10 sm:w-12 sm:h-12 mx-auto text-muted-foreground mb-3" />
                <p class="text-muted-foreground">No processing history yet</p>
                <p class="text-sm text-muted-foreground mt-1">
                  Events will appear here once processing begins.
                </p>
              </div>
            <% else %>
              <div class="bg-card border border-base shadow-sm rounded-lg overflow-hidden flex flex-col flex-1 min-h-0">
                <div class="overflow-auto flex-1">
                  <.admin_table
                    id="events-table"
                    rows={@events}
                    meta={@events_meta}
                    path={~p"/admin/files/#{@file.id}"}
                    show_checkboxes={false}
                  >
                    <:col :let={event} label="Event">
                      <span class="text-sm font-medium text-foreground">
                        <%= format_event_title(event) %>
                      </span>
                    </:col>

                    <:col :let={event} label="From" class="w-28 hidden sm:table-cell" td_class="hidden sm:table-cell">
                      <span class="text-sm text-muted-foreground">
                        <%= event.from_status || "-" %>
                      </span>
                    </:col>

                    <:col :let={event} label="To" class="w-28 hidden sm:table-cell" td_class="hidden sm:table-cell">
                      <span class="text-sm text-foreground">
                        <%= event.to_status || "-" %>
                      </span>
                    </:col>

                    <:col :let={event} label="Error" class="w-20">
                      <%= if event.success == false and event.error_message do %>
                        <button
                          type="button"
                          phx-click="show_error"
                          phx-value-event-id={event.id}
                          class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs font-medium rounded bg-danger/10 text-danger hover:bg-danger/20 transition-colors"
                        >
                          View
                        </button>
                      <% else %>
                        <span class="text-muted-foreground">-</span>
                      <% end %>
                    </:col>

                    <:col :let={event} label="Duration" class="w-24 hidden md:table-cell" td_class="hidden md:table-cell">
                      <span class="text-xs text-muted-foreground font-mono">
                        <%= format_duration_if_present(event.duration_ms) || "-" %>
                      </span>
                    </:col>

                    <:col :let={event} label="Time" class="w-28">
                      <span class="text-xs text-muted-foreground whitespace-nowrap">
                        <%= format_relative_time(event.inserted_at) %>
                      </span>
                    </:col>
                  </.admin_table>
                </div>
              </div>
            <% end %>
          <% end %>

          <!-- Chunks Tab -->
          <%= if @active_tab == "chunks" do %>
            <%= if @chunks == [] do %>
              <div class="bg-card border border-base shadow-sm rounded-lg p-6 sm:p-8 text-center">
                <.icon name="hero-squares-2x2" class="w-10 h-10 sm:w-12 sm:h-12 mx-auto text-muted-foreground mb-3" />
                <p class="text-muted-foreground">No chunks yet</p>
                <p class="text-sm text-muted-foreground mt-1">
                  Chunks will appear here after the file is processed.
                </p>
              </div>
            <% else %>
              <div class="bg-card border border-base shadow-sm rounded-lg overflow-hidden flex flex-col flex-1 min-h-0">
                <div class="overflow-auto flex-1">
                  <.admin_table
                    id="chunks-table"
                    rows={@chunks}
                    meta={@meta}
                    path={~p"/admin/files/#{@file.id}"}
                    show_checkboxes={false}
                  >
                    <:col :let={chunk} label="#" class="w-16">
                      <span class="font-mono text-sm"><%= chunk.position %></span>
                    </:col>

                    <:col :let={chunk} label="Content">
                      <div class="max-w-xs sm:max-w-md lg:max-w-xl">
                        <p class="text-sm text-foreground line-clamp-2" title={chunk.content}>
                          <%= chunk.content %>
                        </p>
                      </div>
                    </:col>

                    <:col :let={chunk} label="Bytes" class="w-28 hidden sm:table-cell">
                      <span class="font-mono text-xs text-muted-foreground whitespace-nowrap">
                        <%= chunk.start_byte %> - <%= chunk.end_byte %>
                      </span>
                    </:col>

                    <:col :let={chunk} label="Rev" class="w-14">
                      <.badge color="info"><%= chunk.revision %></.badge>
                    </:col>

                    <:col :let={chunk} label="Vector" class="w-20 hidden lg:table-cell" td_class="hidden lg:table-cell">
                      <%= if chunk.has_embedding do %>
                        <.badge color="success">
                          <.icon name="hero-check-circle" class="w-3 h-3 mr-1" />
                          Yes
                        </.badge>
                      <% else %>
                        <.badge color="warning">
                          <.icon name="hero-clock" class="w-3 h-3 mr-1" />
                          Pending
                        </.badge>
                      <% end %>
                    </:col>

                    <:col :let={chunk} label="" class="w-12">
                      <.dropdown placement="bottom-end">
                        <:toggle>
                          <button
                            type="button"
                            class="p-1 rounded hover:bg-accent transition-colors text-muted-foreground hover:text-foreground"
                          >
                            <.icon name="hero-ellipsis-vertical" class="w-5 h-5" />
                          </button>
                        </:toggle>
                        <.dropdown_button phx-click="show_chunk" phx-value-chunk-id={chunk.id}>
                          <.icon name="hero-eye" class="w-4 h-4 mr-2" />
                          Show Chunk
                        </.dropdown_button>
                      </.dropdown>
                    </:col>
                  </.admin_table>
                </div>
              </div>
            <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <!-- Error Details Modal -->
    <.modal id="error-details-modal" class="max-w-2xl w-full">
      <%= if @selected_error_event do %>
        <div class="flex items-start gap-3 mb-4">
          <div class="w-10 h-10 rounded-full flex items-center justify-center bg-danger/20 text-danger flex-shrink-0">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
          </div>
          <div>
            <h3 class="text-base font-semibold leading-6 text-foreground">
              <%= format_event_title(@selected_error_event) %>
            </h3>
            <p class="text-sm text-muted-foreground mt-0.5">
              <%= format_relative_time(@selected_error_event.inserted_at) %>
              <%= if @selected_error_event.duration_ms do %>
                · <%= format_duration_if_present(@selected_error_event.duration_ms) %>
              <% end %>
            </p>
          </div>
        </div>

        <div class="space-y-4">
          <div class="bg-muted/30 border border-base rounded-lg p-4">
            <h4 class="text-sm font-medium text-foreground mb-2">Error Message</h4>
            <pre class="text-sm text-foreground whitespace-pre-wrap break-words font-mono bg-card p-3 rounded border border-base overflow-auto max-h-96"><%= @selected_error_event.error_message %></pre>
          </div>

          <dl class="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
            <div>
              <dt class="text-muted-foreground">From</dt>
              <dd class="font-mono text-foreground"><%= @selected_error_event.from_status || "-" %></dd>
            </div>
            <div>
              <dt class="text-muted-foreground">To</dt>
              <dd class="font-mono text-foreground"><%= @selected_error_event.to_status || "-" %></dd>
            </div>
            <div>
              <dt class="text-muted-foreground">Duration</dt>
              <dd class="font-mono text-foreground"><%= format_duration_if_present(@selected_error_event.duration_ms) || "-" %></dd>
            </div>
            <div>
              <dt class="text-muted-foreground">Error Type</dt>
              <dd class="font-mono text-foreground"><%= @selected_error_event.error_type || "-" %></dd>
            </div>
          </dl>
        </div>

        <div class="flex justify-end gap-3 mt-6">
          <.button
            variant="outline"
            phx-click={Fluxon.close_dialog("error-details-modal")}
          >
            Close
          </.button>
        </div>
      <% end %>
    </.modal>

    <!-- Chunk Details Modal -->
    <.modal id="chunk-details-modal" class="max-w-3xl w-full">
      <%= if @selected_chunk do %>
        <div class="flex items-start gap-3 mb-4">
          <div class="w-10 h-10 rounded-full flex items-center justify-center bg-primary/20 text-primary flex-shrink-0">
            <.icon name="hero-document-text" class="w-5 h-5" />
          </div>
          <div>
            <h3 class="text-base font-semibold leading-6 text-foreground">
              Chunk #<%= @selected_chunk.position %>
            </h3>
            <p class="text-sm text-muted-foreground mt-0.5">
              Revision <%= @selected_chunk.revision %>
              · Bytes <%= @selected_chunk.start_byte %> - <%= @selected_chunk.end_byte %>
            </p>
          </div>
        </div>

        <div class="space-y-4">
          <div class="bg-muted/30 border border-base rounded-lg p-4">
            <h4 class="text-sm font-medium text-foreground mb-2">Content</h4>
            <pre class="text-sm text-foreground whitespace-pre-wrap break-words font-mono bg-card p-3 rounded border border-base overflow-auto max-h-96"><%= @selected_chunk.content %></pre>
          </div>

          <%= if @selected_chunk.metadata && @selected_chunk.metadata != %{} do %>
            <div class="bg-muted/30 border border-base rounded-lg p-4">
              <h4 class="text-sm font-medium text-foreground mb-2">Metadata</h4>
              <pre class="text-sm text-muted-foreground whitespace-pre-wrap break-words font-mono bg-card p-3 rounded border border-base overflow-auto max-h-48"><%= Jason.encode!(@selected_chunk.metadata, pretty: true) %></pre>
            </div>
          <% end %>

          <dl class="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
            <div>
              <dt class="text-muted-foreground">Position</dt>
              <dd class="font-mono text-foreground"><%= @selected_chunk.position %></dd>
            </div>
            <div>
              <dt class="text-muted-foreground">Revision</dt>
              <dd class="font-mono text-foreground"><%= @selected_chunk.revision %></dd>
            </div>
            <div>
              <dt class="text-muted-foreground">Start Byte</dt>
              <dd class="font-mono text-foreground"><%= @selected_chunk.start_byte %></dd>
            </div>
            <div>
              <dt class="text-muted-foreground">End Byte</dt>
              <dd class="font-mono text-foreground"><%= @selected_chunk.end_byte %></dd>
            </div>
            <div>
              <dt class="text-muted-foreground">Vector Embedding</dt>
              <dd>
                <%= if @selected_chunk.has_embedding do %>
                  <.badge color="success">
                    <.icon name="hero-check-circle" class="w-3 h-3 mr-1" />
                    Generated
                  </.badge>
                <% else %>
                  <.badge color="warning">
                    <.icon name="hero-clock" class="w-3 h-3 mr-1" />
                    Pending
                  </.badge>
                <% end %>
              </dd>
            </div>
          </dl>
        </div>

        <div class="flex justify-end gap-3 mt-6">
          <.button
            variant="outline"
            phx-click={Fluxon.close_dialog("chunk-details-modal")}
          >
            Close
          </.button>
        </div>
      <% end %>
    </.modal>
    """
  end

  # Helper functions
  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_bytes(_), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M UTC")
  end

  defp sync_status_color("synced"), do: "success"
  defp sync_status_color("deleted"), do: "danger"
  defp sync_status_color(_), do: "info"

  defp processing_status_color("chunked"), do: "success"
  defp processing_status_color("ready"), do: "success"
  defp processing_status_color("downloading"), do: "warning"
  defp processing_status_color("chunking"), do: "warning"
  defp processing_status_color("embedding"), do: "warning"
  defp processing_status_color("failed"), do: "danger"
  defp processing_status_color(_), do: "info"

  defp get_total_count(meta) do
    case meta do
      %{total_count: count} when is_integer(count) -> count
      _ -> 0
    end
  end

  # External link helpers
  defp external_link(%{metadata: %{"web_view_link" => link}}) when is_binary(link), do: link
  defp external_link(_), do: nil

  defp connector_key(%{connector_organization: %{connector: %{key: key}}}), do: key
  defp connector_key(_), do: nil

  defp connector_icon(%{key: "google_drive"} = assigns) do
    ~H"""
    <svg viewBox="0 0 87.3 78" class="w-4 h-4">
      <path d="M6.6 66.85l3.85 6.65c.8 1.4 1.95 2.5 3.3 3.3l13.75-23.8H0c0 1.55.4 3.1 1.2 4.5l5.4 9.35z" fill="#0066DA"/>
      <path d="M43.65 25L29.9 1.2C28.55 2 27.4 3.1 26.6 4.5l-20.25 35c-.8 1.4-1.2 2.95-1.2 4.5h27.5l11-19z" fill="#00AC47"/>
      <path d="M73.55 76.8c1.35-.8 2.5-1.9 3.3-3.3l1.6-2.75 7.65-13.25c.8-1.4 1.2-2.95 1.2-4.5H59.85l5.85 10.15L73.55 76.8z" fill="#EA4335"/>
      <path d="M43.65 25L57.4 1.2C56.05.4 54.5 0 52.9 0H34.4c-1.6 0-3.15.45-4.5 1.2L43.65 25z" fill="#00832D"/>
      <path d="M59.85 53H27.5l-13.75 23.8c1.35.8 2.9 1.2 4.5 1.2h50.8c1.6 0 3.15-.45 4.5-1.2L59.85 53z" fill="#2684FC"/>
      <path d="M73.4 26.5l-10.1-17.5c-.8-1.4-1.95-2.5-3.3-3.3L43.65 25l16.2 28h27.45c0-1.55-.4-3.1-1.2-4.5l-12.7-22z" fill="#FFBA00"/>
    </svg>
    """
  end

  defp connector_icon(assigns) do
    ~H"""
    <.icon name="hero-cloud" class="w-4 h-4" />
    """
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  defp format_event_title(%{event: "claim_processing"}), do: "Processing Started"
  defp format_event_title(%{event: "chunking_complete"}), do: "Chunking Complete"
  defp format_event_title(%{event: "embedding_complete"}), do: "Embedding Complete"
  defp format_event_title(%{event: "processing_failed"}), do: "Processing Failed"

  defp format_event_title(%{event: event}),
    do: event |> String.replace("_", " ") |> String.capitalize()

  defp format_duration_if_present(nil), do: nil
  defp format_duration_if_present(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration_if_present(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration_if_present(ms), do: "#{Float.round(ms / 60_000, 1)}m"

  # Pipeline progress bar helpers
  # Processing statuses managed by Machinery state machine:
  # draft -> downloading -> chunking -> chunked -> embedding -> ready
  @statuses_order ~w(draft downloading chunking chunked embedding ready)

  defp pipeline_step_labels do
    ["Draft", "Downloading", "Chunking", "Chunked", "Embedding", "Ready"]
  end

  defp current_pipeline_step(file) do
    Enum.find_index(@statuses_order, &(&1 == file.processing_status)) || 0
  end

  defp pipeline_status(file) do
    case file.processing_status do
      "ready" -> :completed
      "failed" -> :failed
      _ -> :in_progress
    end
  end

  # Determine if we can trigger the next step
  defp can_trigger_next_step?(file) do
    file.sync_status == "synced" and file.processing_status in ["draft", "failed"]
  end

  # Can reset if file is not in draft (allows resetting stuck jobs too)
  defp can_reset?(file) do
    file.processing_status != "draft"
  end

  # Get the action button text based on current status
  defp next_step_action_text(file) do
    case file.processing_status do
      "draft" -> "Start Processing"
      "failed" -> "Retry Processing"
      _ -> nil
    end
  end

  defp pipeline_status_text(file) do
    case file.processing_status do
      "downloading" -> "Downloading file..."
      "chunking" -> "Chunking in progress..."
      "chunked" -> "Waiting for embedding"
      "embedding" -> "Generating embeddings..."
      "ready" -> "Processing complete"
      "failed" -> "Processing failed"

      "draft" ->
        if file.sync_status != "synced" do
          "Sync required first"
        else
          "Ready to start processing"
        end

      _ ->
        "Unknown status"
    end
  end
end
