defmodule TaskyWeb.Student.TaskAnswersApiController do
  @moduledoc """
  Autosave endpoint for a student's answer doc on a learning unit (task).
  Session-authenticated; the student must be enrolled in the task's course
  and the submission still editable (not completed/approved).
  """
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.Tasks
  alias Tasky.Tasks.{Task, TaskSubmission}

  def update(conn, %{"id" => task_id, "content" => content}) when is_map(content) do
    scope = conn.assigns.current_scope
    user = scope.user

    with %Task{} = task <- Tasks.get_task_for_student(scope, task_id),
         %TaskSubmission{} = submission <- Tasks.get_submission_for_student(task.id, user.id) do
      case Tasks.save_student_answers(scope, submission, content) do
        {:error, :not_editable} ->
          json_error(conn, :conflict, "Die Aufgabe ist bereits abgeschlossen.")

        result ->
          render_save_result(conn, result)
      end
    else
      _ -> json_error(conn, :not_found, "Aufgabe nicht gefunden.")
    end
  end

  def update(conn, _params) do
    json_error(conn, :bad_request, "Missing or invalid content field")
  end
end
