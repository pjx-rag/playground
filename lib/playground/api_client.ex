defmodule Playground.APIClient do
  @moduledoc """
  Behaviour for API client modules.

  All external API services should implement this behaviour to ensure
  consistent interface and required functionality like health checks.

  ## Example

      defmodule Playground.Services.StripeAPI do
        @behaviour Playground.APIClient

        @impl true
        def service_name, do: "stripe"

        @impl true
        def base_url, do: "https://api.stripe.com"

        @impl true
        def health_check do
          # Implement health check logic
          {:ok, %{status: :healthy, latency_ms: 45}}
        end

        @impl true
        def default_headers do
          [
            {"authorization", "Bearer " <> api_key()},
            {"content-type", "application/json"}
          ]
        end

        # Service-specific functions
        def create_customer(params) do
          request(:post, "/v1/customers", params)
        end
      end

  """

  @typedoc "Health check result indicating service status"
  @type health_result :: {:ok, health_info()} | {:error, term()}

  @typedoc "Health check info map"
  @type health_info :: %{
          status: :healthy | :degraded | :unhealthy,
          latency_ms: non_neg_integer(),
          message: String.t() | nil
        }

  @doc """
  Returns the service name identifier (e.g., "stripe", "twilio").
  Used for logging and metrics.
  """
  @callback service_name() :: String.t()

  @doc """
  Returns the base URL for the API.
  """
  @callback base_url() :: String.t()

  @doc """
  Performs a health check against the API.

  Should return quickly and indicate if the service is available.
  Consider implementing a lightweight endpoint check (like /health or /ping)
  or a simple authenticated request.
  """
  @callback health_check() :: health_result()

  @doc """
  Returns default headers to include with every request.

  Typically includes authentication headers, content-type, etc.
  """
  @callback default_headers() :: [{String.t(), String.t()}]

  @doc """
  Optional callback for request timeout in milliseconds.
  Defaults to 30_000 (30 seconds) if not implemented.
  """
  @callback request_timeout() :: pos_integer()

  @doc """
  Optional callback for retry configuration.
  Returns a keyword list with retry options.
  """
  @callback retry_options() :: keyword()

  @optional_callbacks [request_timeout: 0, retry_options: 0]
end
