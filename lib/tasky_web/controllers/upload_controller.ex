defmodule TaskyWeb.UploadController do
  @moduledoc """
  Serves user-uploaded files (exam images and exam attachments) from the
  configured uploads directory. Public on purpose — filenames are unguessable
  UUIDs — so that both the browser and Gotenberg's headless Chrome can load
  `<img>` sources without carrying an auth token.
  """
  use TaskyWeb, :controller

  alias Tasky.Exams
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

  @doc """
  Serves a teacher attachment (Anhang) as a download carrying the original
  filename. Looked up by the stored UUID filename.
  """
  def attachment(conn, %{"exam_id" => exam_id, "filename" => filename}) do
    with attachment when not is_nil(attachment) <-
           Exams.get_exam_attachment_by_stored_filename(exam_id, filename),
         {:ok, path} <- Uploads.attachment_path(exam_id, attachment.stored_filename) do
      send_download(conn, {:file, path},
        filename: attachment.original_name,
        content_type: attachment.content_type
      )
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end

  def task_image(conn, %{"task_id" => task_id, "filename" => filename}) do
    case Uploads.fetch_task_image(task_id, filename) do
      {:ok, {path, content_type}} ->
        conn
        |> put_resp_header("content-type", content_type)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_file(200, path)

      {:error, _} ->
        conn |> put_status(:not_found) |> text("Not found")
    end
  end

  @doc """
  Serves a learning-unit attachment as a download carrying the original
  filename. Looked up by the stored UUID filename.
  """
  def task_attachment(conn, %{"task_id" => task_id, "filename" => filename}) do
    with attachment when not is_nil(attachment) <-
           Tasky.Tasks.get_task_attachment_by_stored_filename(task_id, filename),
         {:ok, path} <- Uploads.task_attachment_path(task_id, attachment.stored_filename) do
      send_download(conn, {:file, path},
        filename: attachment.original_name,
        content_type: attachment.content_type
      )
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end
end
