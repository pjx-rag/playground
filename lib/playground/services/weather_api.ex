defmodule Playground.Services.WeatherAPI do
  @moduledoc """
  Weather API service using Open-Meteo (free, no API key required).

  Open-Meteo provides free weather data including current conditions,
  forecasts, and historical data.

  ## Usage

      # Health check
      {:ok, %{status: :healthy}} = WeatherAPI.health_check()

      # Get current weather for a location
      {:ok, weather} = WeatherAPI.get_current_weather(52.52, 13.41) # Berlin

      # Get weather forecast
      {:ok, forecast} = WeatherAPI.get_forecast(40.71, -74.01) # New York

  """

  @behaviour Playground.APIClient

  alias Playground.ReqPlugins.APILogger

  @base_url "https://api.open-meteo.com"

  # =============================================================================
  # APIClient Behaviour Implementation
  # =============================================================================

  @impl Playground.APIClient
  def service_name, do: "weather"

  @impl Playground.APIClient
  def base_url, do: @base_url

  @impl Playground.APIClient
  def health_check do
    start_time = System.monotonic_time(:millisecond)

    case req() |> Req.get(url: "/v1/forecast", params: [latitude: 0, longitude: 0, current_weather: true]) |> normalize_response() do
      {:ok, _response} ->
        latency = System.monotonic_time(:millisecond) - start_time

        {:ok,
         %{
           status: :healthy,
           latency_ms: latency,
           message: nil
         }}

      {:error, %{status: status}} ->
        {:ok,
         %{
           status: :unhealthy,
           latency_ms: 0,
           message: "API returned status #{status}"
         }}

      {:error, %{reason: reason}} ->
        {:ok,
         %{
           status: :unhealthy,
           latency_ms: 0,
           message: "Connection error: #{inspect(reason)}"
         }}
    end
  end

  @impl Playground.APIClient
  def default_headers do
    [{"accept", "application/json"}]
  end

  @impl Playground.APIClient
  def request_timeout, do: 10_000

  # =============================================================================
  # API Endpoints
  # =============================================================================

  @doc """
  Gets current weather for a location.

  ## Parameters
    - latitude: Latitude of the location
    - longitude: Longitude of the location

  ## Example

      {:ok, weather} = WeatherAPI.get_current_weather(52.52, 13.41)
      # => %{
      #   "current_weather" => %{
      #     "temperature" => 15.2,
      #     "windspeed" => 12.5,
      #     "weathercode" => 3
      #   }
      # }

  """
  def get_current_weather(latitude, longitude) do
    req()
    |> Req.get(url: "/v1/forecast", params: [latitude: latitude, longitude: longitude, current_weather: true])
    |> normalize_response()
  end

  @doc """
  Gets weather forecast for a location.

  Returns hourly and daily forecasts for the next 7 days.

  ## Parameters
    - latitude: Latitude of the location
    - longitude: Longitude of the location
    - opts: Optional parameters
      - days: Number of forecast days (1-16, default 7)

  """
  def get_forecast(latitude, longitude, opts \\ []) do
    days = Keyword.get(opts, :days, 7)

    req()
    |> Req.get(
      url: "/v1/forecast",
      params: [
        latitude: latitude,
        longitude: longitude,
        daily: "temperature_2m_max,temperature_2m_min,precipitation_sum,weathercode",
        timezone: "auto",
        forecast_days: days
      ]
    )
    |> normalize_response()
  end

  @doc """
  Gets weather for a city by name.

  Supported cities: new_york, london, tokyo, sydney, berlin, paris, los_angeles, san_francisco
  """
  def get_weather_for_city(city) do
    case city_coordinates(city) do
      nil -> {:error, %{reason: :unknown_city, message: "Unknown city: #{city}"}}
      coords -> get_current_weather(coords.lat, coords.lon)
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp req do
    Req.new(base_url: @base_url, headers: default_headers(), receive_timeout: request_timeout())
    |> APILogger.attach(service: service_name())
  end

  defp normalize_response({:ok, %Req.Response{status: status, body: body, headers: headers}}) when status in 200..299 do
    {:ok, %{status: status, body: body, headers: headers}}
  end

  defp normalize_response({:ok, %Req.Response{status: status, body: body, headers: headers}}) do
    {:error, %{status: status, body: body, headers: headers}}
  end

  defp normalize_response({:error, exception}) do
    {:error, %{reason: exception, message: Exception.message(exception)}}
  end

  defp city_coordinates(city) do
    cities = %{
      "new_york" => %{lat: 40.71, lon: -74.01},
      "london" => %{lat: 51.51, lon: -0.13},
      "tokyo" => %{lat: 35.68, lon: 139.69},
      "sydney" => %{lat: -33.87, lon: 151.21},
      "berlin" => %{lat: 52.52, lon: 13.41},
      "paris" => %{lat: 48.85, lon: 2.35},
      "los_angeles" => %{lat: 34.05, lon: -118.24},
      "san_francisco" => %{lat: 37.77, lon: -122.42}
    }

    Map.get(cities, String.downcase(city))
  end
end
