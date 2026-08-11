defmodule TaskyWeb.Student.SolutionFileController do
  @moduledoc """
  Lets a logged-in student download a learning unit's solution file — but only
  once the solution has been released for them.

  Das Tor sitzt in `Tasky.Tasks.get_solution_file_for_student/3`. Ist es zu,
  antworten wir 404 statt 403: dass es zu dieser Lerneinheit überhaupt eine
  Lösungsdatei gibt, ist selbst schon eine Information.
  """
  use TaskyWeb, :controller

  import TaskyWeb.StorageServing

  alias Tasky.Tasks
  alias Tasky.Uploads

  def download(conn, %{"task_id" => task_id, "file_id" => file_id}) do
    with {:ok, task, file} <-
           Tasks.get_solution_file_for_student(conn.assigns.current_scope, task_id, file_id),
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
