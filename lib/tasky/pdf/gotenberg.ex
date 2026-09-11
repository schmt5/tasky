defmodule Tasky.PDF.Gotenberg do
  @moduledoc """
  Thin HTTP client for [Gotenberg](https://gotenberg.dev) — a stateless
  service that converts URLs / HTML / Office docs to PDF.

  Configured via `:tasky, :gotenberg_url`. When that's nil, the service is
  considered unavailable and `enabled?/0` returns false.
  """

  @timeout 60_000
  @max_retries 2

  @doc """
  Worst-case wall time of one `url_to_pdf/2` call: every attempt can burn the
  full receive timeout, plus Req's backoff between them.

  `Tasky.Exams.ExportRunner` derives its per-submission task timeout from this
  so the two cannot disagree. They did: the client could spend ~273 s while the
  runner killed the task at 120 s, meaning a render that actually needed its
  retries could never finish — and the kill lost the submission's identity, so
  the failure manifest could only say "Unbekannte Abgabe".
  """
  def max_attempt_time_ms, do: (@max_retries + 1) * @timeout + 10_000

  @doc """
  Returns true when a Gotenberg base URL is configured.
  """
  def enabled? do
    not is_nil(base_url())
  end

  @doc """
  Renders the given URL to PDF via Gotenberg's Chromium route.

  Options:

    * `:wait_for_expression` — defaults to `"window.printReady === true"`, the
      flag the print-view LiveView sets once its React renderer is done.
    * `:print_background` — `false` by default, so Chromium drops backgrounds
      and only borders print. Pass `true` where a tint carries meaning (the
      callout colours). Borders print either way.
    * `:max_retries` — defaults to #{@max_retries}. A background export can
      afford `max_attempt_time_ms/0` worth of retries; an interactive click
      cannot, so the paper route passes `0`.

  Both of the latter are appended to the form **only when set**, which keeps
  the existing submission-export request byte-identical.
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

        form =
          if Keyword.get(opts, :print_background, false),
            do: form ++ [printBackground: "true"],
            else: form

        case Req.post(
               url: "#{base}/forms/chromium/convert/url",
               form_multipart: form,
               receive_timeout: @timeout,
               connect_options: [transport_opts: [inet6: true]],
               # Transient failures (429/5xx/timeouts) get a couple of
               # backed-off retries instead of failing the whole export.
               retry: :transient,
               max_retries: Keyword.get(opts, :max_retries, @max_retries)
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
