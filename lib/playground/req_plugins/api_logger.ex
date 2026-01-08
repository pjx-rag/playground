defmodule Playground.ReqPlugins.APILogger do
  @moduledoc """
  Req plugin that logs API requests to the database.

  ## Usage

      Req.new()
      |> Playground.ReqPlugins.APILogger.attach(service: "weather")
      |> Req.get!("/endpoint")

  ## Options

    * `:service` - Required. The service name for logging (e.g., "weather", "stripe")

  """

  require Logger

  @filtered_headers ~w[authorization bearer token api-key x-api-key cookie set-cookie]
  @max_body_size 50_000

  @doc """
  Attaches the API logger plugin to a Req request.
  """
  def attach(request, opts \\ []) do
    service = Keyword.fetch!(opts, :service)

    request
    |> Req.Request.register_options([:api_logger_service, :api_logger_start_time])
    |> Req.Request.merge_options(api_logger_service: service)
    |> Req.Request.prepend_request_steps(api_logger_start: &record_start_time/1)
    |> Req.Request.append_response_steps(api_logger: &log_response/1)
    |> Req.Request.append_error_steps(api_logger_error: &log_error/1)
  end

  defp record_start_time(request) do
    Req.Request.merge_options(request, api_logger_start_time: System.monotonic_time(:millisecond))
  end

  defp log_response({request, response}) do
    log_to_db(request, {:ok, response})
    {request, response}
  end

  defp log_error({request, exception}) do
    log_to_db(request, {:error, exception})
    {request, exception}
  end

  defp log_to_db(request, result) do
    service = request.options[:api_logger_service]
    url = URI.to_string(request.url)
    path = request.url.path || "/"
    path_with_query = if request.url.query, do: "#{path}?#{request.url.query}", else: path

    {status, response_headers, response_body, error_message, success} =
      case result do
        {:ok, %Req.Response{status: status, headers: headers, body: body}} ->
          {status, headers, body, nil, status in 200..299}

        {:error, %Req.TransportError{reason: reason}} ->
          {"error", %{}, nil, "Transport error: #{inspect(reason)}", false}

        {:error, exception} ->
          {"error", %{}, nil, Exception.message(exception), false}
      end

    # Extract request body from options
    request_body =
      cond do
        request.options[:json] -> request.options[:json]
        request.options[:body] -> request.options[:body]
        request.options[:form] -> request.options[:form]
        true -> nil
      end

    log_data = %{
      service: service,
      method: to_string(request.method) |> String.upcase(),
      path: path_with_query,
      url: url,
      status_code: status,
      duration_ms: get_duration(request),
      success: success,
      request_headers: filter_headers(request.headers),
      request_body: format_body(request_body),
      response_headers: filter_headers(response_headers),
      response_body: format_body(response_body),
      error_message: error_message
    }

    # Log to console
    log_metadata = [
      service: service,
      method: log_data.method,
      path: path_with_query,
      status_code: status
    ]

    if success do
      Logger.info("API Request", log_metadata)
    else
      Logger.warning("API Request Failed", log_metadata)
    end

    # Persist to database
    persist_to_db(log_data)
  end

  defp get_duration(request) do
    case request.options[:api_logger_start_time] do
      nil -> 0
      start_time -> System.monotonic_time(:millisecond) - start_time
    end
  end

  defp filter_headers(headers) when is_map(headers) do
    Enum.into(headers, %{}, fn {key, value} ->
      key_str = to_string(key)

      if String.downcase(key_str) in @filtered_headers do
        {key_str, "[FILTERED]"}
      else
        {key_str, format_header_value(value)}
      end
    end)
  end

  defp filter_headers(headers) when is_list(headers) do
    Enum.into(headers, %{}, fn {key, value} ->
      key_str = to_string(key)

      if String.downcase(key_str) in @filtered_headers do
        {key_str, "[FILTERED]"}
      else
        {key_str, format_header_value(value)}
      end
    end)
  end

  defp filter_headers(_), do: %{}

  defp format_header_value(values) when is_list(values), do: Enum.join(values, ", ")
  defp format_header_value(value), do: to_string(value)

  defp format_body(nil), do: nil
  defp format_body(""), do: nil

  defp format_body(body) when is_binary(body) do
    if String.length(body) > @max_body_size do
      String.slice(body, 0, @max_body_size) <> "...[truncated]"
    else
      body
    end
  end

  defp format_body(body) when is_map(body) or is_list(body) do
    case Jason.encode(body, pretty: true) do
      {:ok, json_string} ->
        if String.length(json_string) > @max_body_size do
          String.slice(json_string, 0, @max_body_size) <> "...[truncated]"
        else
          json_string
        end

      {:error, _} ->
        inspect(body, limit: 1000)
    end
  end

  defp format_body(body), do: inspect(body, limit: 1000)

  defp persist_to_db(log_data) do
    Task.start(fn ->
      try do
        %Playground.APIRequestLog{}
        |> Playground.APIRequestLog.changeset(log_data)
        |> Playground.Repo.insert()
      rescue
        e ->
          Logger.warning("Failed to persist API request log: #{inspect(e)}")
      end
    end)
  end
end
