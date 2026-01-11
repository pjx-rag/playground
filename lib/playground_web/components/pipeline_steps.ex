defmodule PlaygroundWeb.Components.PipelineSteps do
  @moduledoc """
  A simple progress bar component for showing pipeline/workflow progress.

  Uses Fluxon theming for consistent styling across light/dark modes.
  """
  use Phoenix.Component

  @doc """
  Renders a simple progress bar with step labels.

  ## Examples

      <.progress_bar
        steps={["Draft", "Downloading", "Chunking", "Chunked", "Embedding", "Ready"]}
        current_step={2}
        status_text="Downloading file..."
      />

  ## Attributes

  - `steps` - List of step label strings
  - `current_step` - 0-based index of the current step
  - `status_text` - Text description of current status
  - `status` - One of: :in_progress, :completed, :failed (affects color)
  """
  attr :steps, :list, required: true, doc: "List of step label strings"
  attr :current_step, :integer, required: true, doc: "0-based index of current step"
  attr :status_text, :string, required: true, doc: "Current status description"
  attr :status, :atom, default: :in_progress, doc: "One of :in_progress, :completed, :failed"
  attr :class, :string, default: nil

  def progress_bar(assigns) do
    total_steps = length(assigns.steps)
    # Calculate percentage: completed steps / total steps
    # If on step 0, show small progress; if completed, show 100%
    progress_percent =
      cond do
        assigns.status == :completed -> 100
        assigns.current_step == 0 -> 0
        true -> round(assigns.current_step / (total_steps - 1) * 100)
      end

    assigns = assign(assigns, :progress_percent, progress_percent)
    assigns = assign(assigns, :total_steps, total_steps)

    ~H"""
    <div class={@class}>
      <h4 class="sr-only">Status</h4>
      <p class={["text-sm font-medium", status_text_class(@status)]}>
        <%= @status_text %>
      </p>
      <div aria-hidden="true" class="mt-4">
        <div class="overflow-hidden rounded-full bg-muted">
          <div
            style={"width: #{@progress_percent}%"}
            class={["h-2 rounded-full transition-all duration-500", progress_bar_class(@status)]}
          />
        </div>
        <div class={[
          "mt-4 hidden text-sm font-medium sm:grid",
          grid_cols_class(@total_steps)
        ]}>
          <%= for {step, index} <- Enum.with_index(@steps) do %>
            <div class={[
              step_label_position(index, @total_steps),
              step_label_class(index, @current_step, @status)
            ]}>
              <%= step %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp status_text_class(:completed), do: "text-success"
  defp status_text_class(:failed), do: "text-danger"
  defp status_text_class(_), do: "text-foreground"

  defp progress_bar_class(:completed), do: "bg-success"
  defp progress_bar_class(:failed), do: "bg-danger"
  defp progress_bar_class(_), do: "bg-primary"

  defp grid_cols_class(2), do: "grid-cols-2"
  defp grid_cols_class(3), do: "grid-cols-3"
  defp grid_cols_class(4), do: "grid-cols-4"
  defp grid_cols_class(5), do: "grid-cols-5"
  defp grid_cols_class(6), do: "grid-cols-6"
  defp grid_cols_class(7), do: "grid-cols-7"
  defp grid_cols_class(_), do: "grid-cols-6"

  defp step_label_position(0, _total), do: "text-left"
  defp step_label_position(index, total) when index == total - 1, do: "text-right"
  defp step_label_position(_, _), do: "text-center"

  defp step_label_class(index, current_step, status) do
    cond do
      status == :failed and index <= current_step -> "text-danger"
      index < current_step -> "text-primary"
      index == current_step -> "text-primary"
      true -> "text-muted-foreground"
    end
  end
end
