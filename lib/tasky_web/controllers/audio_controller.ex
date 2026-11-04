defmodule TaskyWeb.AudioController do
  @moduledoc """
  Plays the file of an audio block to its teacher (editor, preview,
  correction), with no limit. Learners load it through
  `TaskyWeb.Guest.AudioController` / `TaskyWeb.Student.AudioController`, which
  check their plays.

  The path mirrors the node's `src`: `/uploads/exams/:id/:file` is played at
  `/exams/:id/audio/:file`.
  """
  use TaskyWeb, :controller

  import TaskyWeb.StorageServing

  alias Tasky.{Exams, Tasks, Uploads}

  def exam(conn, %{"id" => id, "filename" => filename}) do
    exam = Exams.get_exam!(conn.assigns.current_scope, id)
    serve(conn, Uploads.fetch_audio("/uploads/exams/#{exam.id}/#{filename}", :exams, exam.id))
  end

  def task(conn, %{"id" => id, "filename" => filename}) do
    task = Tasks.get_task!(conn.assigns.current_scope, id)
    serve(conn, Uploads.fetch_audio("/uploads/tasks/#{task.id}/#{filename}", :tasks, task.id))
  end

  defp serve(conn, {:ok, {source, content_type}}), do: serve_media(conn, source, content_type)
  defp serve(conn, _error), do: conn |> put_status(:not_found) |> text("Nicht gefunden")
end
