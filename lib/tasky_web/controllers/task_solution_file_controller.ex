defmodule TaskyWeb.TaskSolutionFileController do
  @moduledoc """
  Lets teachers/admins download a learning unit's solution file. The task is
  resolved through the caller's scope, so teachers only reach their own units.
  """
  use TaskyWeb, :controller

  import TaskyWeb.StorageServing

  alias Tasky.Tasks
  alias Tasky.Uploads

  def download(conn, %{"id" => task_id, "file_id" => file_id}) do
    task = Tasks.get_task!(conn.assigns.current_scope, task_id)

    with file when not is_nil(file) <- Tasks.get_task_solution_file(task, file_id),
         {:ok, source} <-
           Uploads.fetch_task_solution_file(task.id, file.stored_filename,
             disposition: {"attachment", file.original_name},
             content_type: file.content_type
           ) do
      serve_download(conn, source, file.original_name, file.content_type)
    else
      _ -> conn |> put_status(:not_found) |> text("Not found")
    end
  end
end
