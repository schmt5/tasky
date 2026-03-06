defmodule Tasky.Tally.Client do
  @moduledoc """
  Client for interacting with the Tally.so API.
  """

  require Logger

  @base_url "https://api.tally.so"

  @doc """
  Lists all forms from Tally.

  Returns `{:ok, forms}` on success or `{:error, reason}` on failure.
  """
  def list_forms(current_scope) do
    api_key = get_api_key(current_scope)

    if is_nil(api_key) || api_key == "" do
      {:error, :api_key_not_configured}
    else
      url = "#{@base_url}/forms"

      case Req.get(url, auth: {:bearer, api_key}) do
        {:ok, %Req.Response{status: 200, body: %{"items" => forms}}} ->
          {:ok, forms}

        {:ok, %Req.Response{status: 401}} ->
          Logger.error("Tally API: Unauthorized")
          {:error, :unauthorized}

        {:ok, %Req.Response{status: status}} ->
          Logger.error("Tally API returned status code: #{status}")
          {:error, :api_error}

        {:error, exception} ->
          Logger.error("Failed to connect to Tally API: #{inspect(exception)}")
          {:error, :connection_error}
      end
    end
  end

  @doc """
  Gets a single form by ID.

  Returns `{:ok, form}` on success or `{:error, reason}` on failure.
  """
  def get_form(current_scope, form_id) do
    api_key = get_api_key(current_scope)

    if is_nil(api_key) || api_key == "" do
      {:error, :api_key_not_configured}
    else
      url = "#{@base_url}/forms/#{form_id}"

      case Req.get(url, auth: {:bearer, api_key}) do
        {:ok, %Req.Response{status: 200, body: form}} ->
          {:ok, form}

        {:ok, %Req.Response{status: 404}} ->
          {:error, :not_found}

        {:ok, %Req.Response{status: 401}} ->
          {:error, :unauthorized}

        {:ok, %Req.Response{status: status}} ->
          Logger.error("Tally API returned status code: #{status}")
          {:error, :api_error}

        {:error, exception} ->
          Logger.error("Failed to connect to Tally API: #{inspect(exception)}")
          {:error, :connection_error}
      end
    end
  end

  @doc """
  Creates a webhook for a form.

  Returns `{:ok, webhook}` on success or `{:error, reason}` on failure.

  ## Options
    * `:signing_secret` - Optional secret used to sign webhook payloads
    * `:http_headers` - Optional custom HTTP headers (list of maps with "name" and "value" keys)
    * `:external_subscriber` - Optional identifier for the external subscriber
  """
  def create_webhook(current_scope, form_id, webhook_url, opts \\ []) do
    api_key = get_api_key(current_scope)

    if is_nil(api_key) || api_key == "" do
      {:error, :api_key_not_configured}
    else
      url = "#{@base_url}/webhooks"

      body = %{
        "formId" => form_id,
        "url" => webhook_url,
        "eventTypes" => ["FORM_RESPONSE"]
      }

      body =
        body
        |> maybe_put("signingSecret", Keyword.get(opts, :signing_secret))
        |> maybe_put("httpHeaders", Keyword.get(opts, :http_headers))
        |> maybe_put("externalSubscriber", Keyword.get(opts, :external_subscriber))

      case Req.post(url, auth: {:bearer, api_key}, json: body) do
        {:ok, %Req.Response{status: 201, body: webhook}} ->
          {:ok, webhook}

        {:ok, %Req.Response{status: 401}} ->
          Logger.error("Tally API: Unauthorized")
          {:error, :unauthorized}

        {:ok, %Req.Response{status: 400, body: error_body}} ->
          Logger.error("Tally API: Bad request - #{inspect(error_body)}")
          {:error, :bad_request}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error("Tally API returned status code: #{status}, body: #{inspect(body)}")
          {:error, :api_error}

        {:error, exception} ->
          Logger.error("Failed to connect to Tally API: #{inspect(exception)}")
          {:error, :connection_error}
      end
    end
  end

  @doc """
  Builds the public form URL for a given form ID.
  """
  def form_url(form_id) do
    "https://tally.so/r/#{form_id}"
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp get_api_key(current_scope) do
    case current_scope do
      %{user: %{tally_api_key: api_key}} when is_binary(api_key) -> api_key
      _ -> nil
    end
  end
end
