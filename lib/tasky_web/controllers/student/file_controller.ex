defmodule TaskyWeb.Student.FileController do
  @moduledoc """
  Lets a logged-in student re-download their own uploaded answer file for a
  learning unit (task). Access is limited to the student's own submission.
  """
  use TaskyWeb, :controller

  import TaskyWeb.StorageServing

  alias Tasky.Tasks
  alias Tasky.Uploads

  def download(conn, %{"task_id" => task_id, "field_id" => field_id}) do
    user = conn.assigns.current_scope.user

    with submission when not is_nil(submission) <-
           Tasks.get_submission_for_student(task_id, user.id),
         file when not is_nil(file) <- Tasks.get_submission_file(submission, field_id),
         {:ok, source} <-
           Uploads.fetch_task_submission_file(
             submission.task_id,
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
