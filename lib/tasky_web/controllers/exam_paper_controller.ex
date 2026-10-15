defmodule TaskyWeb.ExamPaperController do
  @moduledoc """
  Renders the paper version of an exam to PDF, synchronously
  (`Tasky.ExamPaperPdf`, Typst in-process).

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
  alias Tasky.Exams.ExportRunner

  def download(conn, %{"id" => exam_id}) do
    exam = Exams.get_exam!(conn.assigns.current_scope, exam_id)

    case Tasky.ExamPaperPdf.render(exam) do
      {:ok, pdf} ->
        filename = "#{ExportRunner.sanitize_filename(exam.name)}-Papierversion.pdf"

        send_download(conn, {:binary, pdf},
          filename: filename,
          content_type: "application/pdf"
        )

      {:error, reason} ->
        Logger.error("Papierversion-PDF für Prüfung #{exam.id} fehlgeschlagen: #{reason}")

        conn
        |> put_status(:internal_server_error)
        |> text(
          "Die Papierversion konnte nicht erstellt werden. " <>
            "Bitte versuche es in einem Moment noch einmal."
        )
    end
  end
end
