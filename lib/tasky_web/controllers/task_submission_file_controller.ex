defmodule TaskyWeb.TaskSubmissionFileController do
  @moduledoc """
  Lets teachers/admins download a student's uploaded answer file for a
  learning unit (task). The task is resolved through the caller's scope, so
  teachers only reach their own tasks.
  """
  use TaskyWeb, :controller

  import TaskyWeb.StorageServing

  alias Tasky.Tasks
  alias Tasky.Uploads

  def download(conn, %{"id" => task_id, "submission_id" => submission_id, "file_id" => file_id}) do
    task = Tasks.get_task!(conn.assigns.current_scope, task_id)

    with submission when not is_nil(submission) <- Tasks.get_submission(task, submission_id),
         file when not is_nil(file) <- Tasks.get_submission_file_by_id(submission, file_id),
         {:ok, source} <-
           Uploads.fetch_task_submission_file(task.id, submission.id, file.stored_filename,
             disposition: {"attachment", file.original_name},
             content_type: file.content_type
           ) do
      serve_download(conn, source, file.original_name, file.content_type)
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end
end
