defmodule TaskyWeb.SubmissionFileController do
  @moduledoc """
  Lets teachers/admins download a student's uploaded answer file. The exam is
  resolved through the caller's scope, so teachers only reach their own exams.
  """
  use TaskyWeb, :controller

  import TaskyWeb.StorageServing

  alias Tasky.Exams
  alias Tasky.Uploads

  def download(conn, %{"id" => exam_id, "submission_id" => submission_id, "file_id" => file_id}) do
    exam = Exams.get_exam!(conn.assigns.current_scope, exam_id)

    with submission when not is_nil(submission) <- Exams.get_submission(exam, submission_id),
         file when not is_nil(file) <- Exams.get_submission_file_by_id(submission, file_id),
         {:ok, source} <-
           Uploads.fetch_submission_file(exam.id, submission.id, file.stored_filename,
             disposition: {"attachment", file.original_name},
             content_type: file.content_type
           ) do
      serve_download(conn, source, file.original_name, file.content_type)
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end
end
