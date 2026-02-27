defmodule Tasky.Tally.Client do
  @moduledoc """
  Client for interacting with the Tally.so API.
  """

  require Logger

  @base_url "https://api.tally.so"
  @api_key "YOUR_API_KEY_HERE"

  @doc """
  Lists all forms from Tally.

  Returns `{:ok, forms}` on success or `{:error, reason}` on failure.
  """
  def list_forms do
    url = "#{@base_url}/forms"

    case Req.get(url, auth: {:bearer, @api_key}) do
      {:ok, %Req.Response{status: 200, body: %{"data" => forms}}} ->
        {:ok, forms}

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

  @doc """
  Gets a single form by ID.

  Returns `{:ok, form}` on success or `{:error, reason}` on failure.
  """
  def get_form(form_id) do
    url = "#{@base_url}/forms/#{form_id}"

    case Req.get(url, auth: {:bearer, @api_key}) do
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

  @doc """
  Builds the public form URL for a given form ID.
  """
  def form_url(form_id) do
    "https://tally.so/r/#{form_id}"
  end
end
