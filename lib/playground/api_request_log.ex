defmodule Playground.APIRequestLog do
  @moduledoc """
  Schema for persisting API request logs.

  Used for long-term storage and analysis of API requests.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [:service, :method, :status_code, :success],
    sortable: [:inserted_at, :duration_ms, :service, :method, :status_code],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    },
    default_limit: 50
  }

  schema "api_request_logs" do
    field :service, :string
    field :method, :string
    field :path, :string
    field :url, :string
    field :status_code, :string
    field :duration_ms, :integer
    field :success, :boolean, default: true
    field :request_id, :string
    field :metadata, :map, default: %{}
    field :request_headers, :map, default: %{}
    field :request_body, :string
    field :response_headers, :map, default: %{}
    field :response_body, :string
    field :error_message, :string
    field :cost_usd, :decimal
    field :tokens_prompt, :integer
    field :tokens_completion, :integer
    field :tokens_total, :integer

    timestamps(type: :utc_datetime)
  end

  @required_fields [:service, :method, :path, :duration_ms]
  @optional_fields [
    :url,
    :status_code,
    :success,
    :request_id,
    :metadata,
    :request_headers,
    :request_body,
    :response_headers,
    :response_body,
    :error_message,
    :cost_usd,
    :tokens_prompt,
    :tokens_completion,
    :tokens_total
  ]

  def changeset(log, attrs) do
    attrs = normalize_status(attrs)

    log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> put_request_id()
  end

  defp normalize_status(attrs) when is_map(attrs) do
    case Map.get(attrs, :status_code) || Map.get(attrs, "status_code") do
      status_code when is_integer(status_code) ->
        attrs
        |> Map.put(:status_code, to_string(status_code))
        |> Map.delete("status_code")

      _ ->
        attrs
    end
  end

  defp put_request_id(changeset) do
    case get_field(changeset, :request_id) do
      nil ->
        id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
        put_change(changeset, :request_id, id)

      _ ->
        changeset
    end
  end
end
