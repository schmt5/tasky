defmodule TaskyWeb.AudioUploadApiController do
  @moduledoc """
  Uploads the file of an audio block (`audio` node) into an exam or a
  learning unit. Same shape as the image upload; see `Tasky.Uploads.save_exam_audio/2`.
  """
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.{Exams, Tasks, Uploads}

  def exam(conn, %{"id" => id, "audio" => %Plug.Upload{} = upload}) do
    # Authorize: raises if the exam isn't visible to the current scope.
    exam = Exams.get_exam!(conn.assigns.current_scope, id)
    # The canonical id, not the param: "05" finds exam 5 but would store the
    # file where `fetch_audio/3` never looks.
    render_upload(conn, Uploads.save_exam_audio(exam.id, upload))
  end

  def exam(conn, _params), do: json_error(conn, :bad_request, "Keine Audiodatei übermittelt.")

  def task(conn, %{"id" => id, "audio" => %Plug.Upload{} = upload}) do
    task = Tasks.get_task!(conn.assigns.current_scope, id)
    render_upload(conn, Uploads.save_task_audio(task.id, upload))
  end

  def task(conn, _params), do: json_error(conn, :bad_request, "Keine Audiodatei übermittelt.")

  defp render_upload(conn, result) do
    case result do
      {:ok, url} ->
        json(conn, %{url: url})

      {:error, :unsupported_type} ->
        json_error(conn, :unprocessable_entity, "Nur MP3- und M4A-Dateien sind möglich.")

      {:error, :invalid_audio} ->
        json_error(conn, :unprocessable_entity, "Datei ist keine gültige Audiodatei.")

      {:error, :too_large} ->
        json_error(conn, :request_entity_too_large, "Audiodatei ist zu gross (max. 10 MB).")

      # A storage outage is transient, so it must not come back as a 4xx the
      # client treats as final.
      {:error, :storage_failed} ->
        json_error(
          conn,
          :service_unavailable,
          "Speicher nicht erreichbar. Bitte erneut versuchen."
        )

      {:error, _} ->
        json_error(conn, :unprocessable_entity, "Audiodatei konnte nicht gespeichert werden.")
    end
  end
end
