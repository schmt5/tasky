defmodule TaskyWeb.ExamImageApiController do
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.{Exams, Uploads}

  def create(conn, %{"id" => id, "image" => %Plug.Upload{} = upload}) do
    # Authorize: raises if the exam isn't visible to the current scope.
    _exam = Exams.get_exam!(conn.assigns.current_scope, id)

    case Uploads.save_exam_image(id, upload) do
      {:ok, url} ->
        json(conn, %{url: url})

      {:error, :unsupported_type} ->
        json_error(conn, :unprocessable_entity, "Nicht unterstütztes Bildformat.")

      {:error, :invalid_image} ->
        json_error(conn, :unprocessable_entity, "Datei ist kein gültiges Bild.")

      {:error, :too_large} ->
        json_error(conn, :request_entity_too_large, "Bild ist zu gross (max. 10 MB).")

      {:error, _} ->
        json_error(conn, :unprocessable_entity, "Bild konnte nicht gespeichert werden.")
    end
  end

  def create(conn, _params) do
    json_error(conn, :bad_request, "Kein Bild übermittelt.")
  end
end
