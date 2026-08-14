defmodule TaskyWeb.Guest.FileController do
  @moduledoc """
  Lets a student re-download their own uploaded answer file. Access is gated
  by the submission's unguessable exam token in the URL.
  """
  use TaskyWeb, :controller

  import TaskyWeb.StorageServing

  alias Tasky.Exams
  alias Tasky.Uploads
  alias TaskyWeb.Params

  def download(conn, %{"exam_token" => exam_token, "field_id" => field_id}) do
    # `field_id` reaches an integer column, so a non-numeric path segment raises
    # an Ecto.Query.CastError — a 500 where a 404 is the honest answer.
    with field_id when is_integer(field_id) <- Params.int(field_id),
         submission when not is_nil(submission) <-
           Exams.get_exam_submission_by_token(exam_token),
         file when not is_nil(file) <- Exams.get_submission_file(submission, field_id),
         {:ok, source} <-
           Uploads.fetch_submission_file(
             submission.exam_id,
             submission.id,
             file.stored_filename,
             disposition: {"attachment", file.original_name},
             content_type: file.content_type
           ) do
      serve_download(conn, source, file.original_name, file.content_type)
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end
end
