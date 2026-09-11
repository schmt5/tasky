defmodule TaskyWeb.ExamPaperController do
  @moduledoc """
  Renders the paper version of an exam to PDF, synchronously.

  Not routed through `Tasky.Exams.ExportRunner`: that one requires a non-empty
  submission list, names files after the student and always builds a ZIP. A
  blank exam has no submission and is a single PDF, so a nil-submission branch
  through its partition / zip / manifest steps would be more surface than this
  controller.

  Reached with `target="_blank"` rather than a `push_event` download, which
  buys two things: the LiveView socket is untouched (the navigation happens in
  another tab), and a failure stays *visible* — the German error below renders
  as a readable page there, where `push_event` would swallow it into
  `console.error` and `<a download>` would save it as a file.
  """

  use TaskyWeb, :controller

  require Logger

  alias Tasky.Exams
  alias Tasky.Exams.ExamPrintToken
  alias Tasky.Exams.ExportRunner
  alias Tasky.PDF.Gotenberg

  def download(conn, %{"id" => exam_id}) do
    scope = conn.assigns.current_scope
    exam = Exams.get_exam!(scope, exam_id)

    cond do
      not Gotenberg.enabled?() ->
        unavailable(conn, "PDF-Dienst (Gotenberg) ist nicht konfiguriert.")

      is_nil(ExportRunner.callback_base_url()) ->
        unavailable(conn, "GOTENBERG_CALLBACK_URL ist nicht gesetzt.")

      true ->
        render_pdf(conn, scope, exam)
    end
  end

  defp render_pdf(conn, scope, exam) do
    token =
      ExamPrintToken.sign(conn.private.phoenix_endpoint, scope.user.id, to_string(exam.id), %{})

    url =
      "#{ExportRunner.callback_base_url()}/print/exam-paper/#{exam.id}?token=#{URI.encode(token)}"

    # max_retries: 0 — Gotenberg's default budget is worth
    # `max_attempt_time_ms/0` (~190 s), which is fine for a background export
    # and unacceptable for someone waiting on a click.
    case Gotenberg.url_to_pdf(url, print_background: true, max_retries: 0) do
      {:ok, pdf} ->
        filename = "#{ExportRunner.sanitize_filename(exam.name)}-Papierversion.pdf"

        send_download(conn, {:binary, pdf},
          filename: filename,
          content_type: "application/pdf"
        )

      {:error, reason} ->
        Logger.error(
          "Papierversion-PDF für Prüfung #{exam.id} fehlgeschlagen: #{inspect(reason)}"
        )

        conn
        |> put_status(:bad_gateway)
        |> text(
          "Die Papierversion konnte nicht erstellt werden. " <>
            "Bitte im Browser drucken (Cmd/Ctrl+P)."
        )
    end
  end

  defp unavailable(conn, message) do
    conn
    |> put_status(:service_unavailable)
    |> text(message)
  end
end
