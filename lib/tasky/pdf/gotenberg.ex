defmodule Tasky.PDF.Gotenberg do
  @moduledoc """
  Thin HTTP client for [Gotenberg](https://gotenberg.dev) — a stateless
  service that converts URLs / HTML / Office docs to PDF.

  Configured via `:tasky, :gotenberg_url`. When that's nil, the service is
  considered unavailable and `enabled?/0` returns false.
  """

  @timeout 90_000

  @doc """
  Returns true when a Gotenberg base URL is configured.
  """
  def enabled? do
    not is_nil(base_url())
  end

  @doc """
  Renders the given URL to PDF via Gotenberg's Chromium route.

  `wait_for_expression` defaults to `"window.printReady === true"` — the
  print-view LiveView sets that flag once its React renderer is done.
  """
  def url_to_pdf(url, opts \\ []) when is_binary(url) do
    case base_url() do
      nil ->
        {:error, :not_configured}

      base ->
        wait_for = Keyword.get(opts, :wait_for_expression, "window.printReady === true")

        form = [
          url: url,
          waitForExpression: wait_for,
          paperWidth: "8.27",
          paperHeight: "11.7",
          marginTop: "0.4",
          marginBottom: "0.4",
          marginLeft: "0.4",
          marginRight: "0.4"
        ]

        case Req.post(
               url: "#{base}/forms/chromium/convert/url",
               form_multipart: form,
               receive_timeout: @timeout
             ) do
          {:ok, %Req.Response{status: 200, body: pdf_binary}} ->
            {:ok, pdf_binary}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:gotenberg_http_error, status, body}}

          {:error, reason} ->
            {:error, {:gotenberg_transport_error, reason}}
        end
    end
  end

  defp base_url, do: Application.get_env(:tasky, :gotenberg_url)
end
