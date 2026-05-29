defmodule TaskyWeb.UploadController do
  @moduledoc """
  Serves user-uploaded files (exam images) from the configured uploads
  directory. Public on purpose — filenames are unguessable UUIDs — so that
  both the browser and Gotenberg's headless Chrome can load `<img>` sources
  without carrying an auth token.
  """
  use TaskyWeb, :controller

  alias Tasky.Uploads

  def show(conn, %{"exam_id" => exam_id, "filename" => filename}) do
    case Uploads.fetch_exam_image(exam_id, filename) do
      {:ok, {path, content_type}} ->
        conn
        |> put_resp_header("content-type", content_type)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_file(200, path)

      {:error, _} ->
        conn |> put_status(:not_found) |> text("Not found")
    end
  end
end
