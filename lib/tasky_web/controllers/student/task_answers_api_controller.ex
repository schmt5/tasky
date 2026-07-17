defmodule TaskyWeb.Student.TaskAnswersApiController do
  @moduledoc """
  Autosave endpoint for a student's answer doc on a learning unit (task).
  Session-authenticated; the student must be enrolled in the task's course
  and the submission still editable (not completed/approved).
  """
  use TaskyWeb, :controller

  alias Tasky.{Courses, Tasks}
  alias Tasky.Tasks.{Task, TaskSubmission}

  def update(conn, %{"id" => task_id, "content" => content}) when is_map(content) do
    scope = conn.assigns.current_scope
    user = scope.user

    with %Task{} = task <- Tasks.get_task_for_student(task_id),
         true <- Courses.enrolled?(task.course_id, user.id),
         %TaskSubmission{} = submission <- Tasks.get_submission_for_student(task.id, user.id) do
      case Tasks.save_student_answers(scope, submission, content) do
        {:ok, updated} ->
          json(conn, %{ok: true, updated_at: updated.updated_at})

        {:error, :not_editable} ->
          error(conn, :conflict, "Die Aufgabe ist bereits abgeschlossen.")

        {:error, :unauthorized} ->
          error(conn, :forbidden, "Keine Berechtigung.")

        {:error, _changeset} ->
          error(conn, :unprocessable_entity, "Antworten konnten nicht gespeichert werden.")
      end
    else
      _ -> error(conn, :not_found, "Aufgabe nicht gefunden.")
    end
  end

  def update(conn, _params) do
    error(conn, :bad_request, "Missing or invalid content field")
  end

  defp error(conn, status, message) do
    conn |> put_status(status) |> json(%{error: message})
  end
end
