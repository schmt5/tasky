defmodule TaskyWeb.UploadController do
  @moduledoc """
  Serves user-uploaded files (exam images and exam attachments). Public on
  purpose — filenames are unguessable UUIDs — so that both the browser and
  Gotenberg's headless Chrome can load `<img>` sources without carrying an
  auth token. Storage is behind `Tasky.Storage`: local files are sent
  directly, remote objects redirect to a presigned URL.
  """
  use TaskyWeb, :controller

  import TaskyWeb.StorageServing

  alias Tasky.Exams
  alias Tasky.Uploads

  def show(conn, %{"exam_id" => exam_id, "filename" => filename}) do
    case Uploads.fetch_exam_image(exam_id, filename) do
      {:ok, {source, content_type}} -> serve_inline(conn, source, content_type)
      {:error, _} -> conn |> put_status(:not_found) |> text("Not found")
    end
  end

  @doc """
  Serves a teacher attachment (Anhang) as a download carrying the original
  filename. Looked up by the stored UUID filename.
  """
  def attachment(conn, %{"exam_id" => exam_id, "filename" => filename}) do
    with attachment when not is_nil(attachment) <-
           Exams.get_exam_attachment_by_stored_filename(exam_id, filename),
         {:ok, source} <-
           Uploads.fetch_attachment(exam_id, attachment.stored_filename,
             disposition: {"attachment", attachment.original_name},
             content_type: attachment.content_type
           ) do
      serve_download(conn, source, attachment.original_name, attachment.content_type)
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end

  def task_image(conn, %{"task_id" => task_id, "filename" => filename}) do
    case Uploads.fetch_task_image(task_id, filename) do
      {:ok, {source, content_type}} -> serve_inline(conn, source, content_type)
      {:error, _} -> conn |> put_status(:not_found) |> text("Not found")
    end
  end

  @doc """
  Serves a learning-unit attachment as a download carrying the original
  filename. Looked up by the stored UUID filename.
  """
  def task_attachment(conn, %{"task_id" => task_id, "filename" => filename}) do
    with attachment when not is_nil(attachment) <-
           Tasky.Tasks.get_task_attachment_by_stored_filename(task_id, filename),
         {:ok, source} <-
           Uploads.fetch_task_attachment(task_id, attachment.stored_filename,
             disposition: {"attachment", attachment.original_name},
             content_type: attachment.content_type
           ) do
      serve_download(conn, source, attachment.original_name, attachment.content_type)
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end
end
