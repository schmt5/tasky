defmodule TaskyWeb.TaskSubmissionFileController do
  @moduledoc """
  Lets teachers/admins download a student's uploaded answer file for a
  learning unit (task). The task is resolved through the caller's scope, so
  teachers only reach their own tasks.
  """
  use TaskyWeb, :controller

  alias Tasky.Repo
  alias Tasky.Tasks
  alias Tasky.Tasks.TaskSubmission
  alias Tasky.Uploads

  def download(conn, %{"id" => task_id, "submission_id" => submission_id, "file_id" => file_id}) do
    task = Tasks.get_task!(conn.assigns.current_scope, task_id)

    with submission when not is_nil(submission) <-
           Repo.get_by(TaskSubmission, id: submission_id, task_id: task.id),
         file when not is_nil(file) <- Tasks.get_submission_file_by_id(submission, file_id),
         {:ok, path} <-
           Uploads.task_submission_file_path(task.id, submission.id, file.stored_filename) do
      send_download(conn, {:file, path},
        filename: file.original_name,
        content_type: file.content_type
      )
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end
end
