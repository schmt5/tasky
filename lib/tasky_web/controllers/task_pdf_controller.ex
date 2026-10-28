defmodule TaskyWeb.TaskPdfController do
  @moduledoc """
  Renders a learning unit to PDF, synchronously (`Tasky.TaskPdf`, Typst
  in-process) — as a blank worksheet or with the sample solution.

  Reached with `target="_blank"` from the course page, for the same reasons
  as `TaskyWeb.ExamPaperController`: the LiveView socket is untouched and a
  failure stays visible as a readable page.
  """

  use TaskyWeb, :controller

  require Logger

  alias Tasky.Exams.ExportRunner
  alias Tasky.Tasks

  def worksheet(conn, %{"id" => task_id}), do: download(conn, task_id, :worksheet)

  def solution(conn, %{"id" => task_id}), do: download(conn, task_id, :solution)

  defp download(conn, task_id, variant) do
    task = Tasks.get_task!(conn.assigns.current_scope, task_id)

    case Tasky.TaskPdf.render(task, variant) do
      {:ok, pdf} ->
        filename = "#{ExportRunner.sanitize_filename(task.name)}-#{suffix(variant)}.pdf"

        send_download(conn, {:binary, pdf},
          filename: filename,
          content_type: "application/pdf"
        )

      {:error, reason} ->
        Logger.error("PDF (#{variant}) für Lerneinheit #{task.id} fehlgeschlagen: #{reason}")

        conn
        |> put_status(:internal_server_error)
        |> text(
          "Das PDF konnte nicht erstellt werden. " <>
            "Bitte versuche es in einem Moment noch einmal."
        )
    end
  end

  defp suffix(:worksheet), do: "Arbeitsblatt"
  defp suffix(:solution), do: "Musterloesung"
end
