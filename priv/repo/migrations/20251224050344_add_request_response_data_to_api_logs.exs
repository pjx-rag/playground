defmodule Playground.Repo.Migrations.AddRequestResponseDataToApiLogs do
  use Ecto.Migration

  def change do
    alter table(:api_request_logs) do
      add :url, :string
      add :request_headers, :map, default: %{}
      add :request_body, :text
      add :response_headers, :map, default: %{}
      add :response_body, :text
      add :error_message, :text
    end
  end
end
