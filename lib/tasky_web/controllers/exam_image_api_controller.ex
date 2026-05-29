defmodule TaskyWeb.ExamImageApiController do
  use TaskyWeb, :controller

  alias Tasky.{Exams, Uploads}

  def create(conn, %{"id" => id, "image" => %Plug.Upload{} = upload}) do
    # Authorize: raises if the exam isn't visible to the current scope.
    _exam = Exams.get_exam!(conn.assigns.current_scope, id)

    case Uploads.save_exam_image(id, upload) do
      {:ok, url} ->
        json(conn, %{url: url})

      {:error, :unsupported_type} ->
        error(conn, :unprocessable_entity, "Nicht unterstütztes Bildformat.")

      {:error, :too_large} ->
        error(conn, :request_entity_too_large, "Bild ist zu groß (max. 10 MB).")

      {:error, _} ->
        error(conn, :unprocessable_entity, "Bild konnte nicht gespeichert werden.")
    end
  end

  def create(conn, _params) do
    error(conn, :bad_request, "Kein Bild übermittelt.")
  end

  defp error(conn, status, message) do
    conn |> put_status(status) |> json(%{error: message})
  end
end
