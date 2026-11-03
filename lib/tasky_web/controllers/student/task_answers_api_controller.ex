defmodule TaskyWeb.Student.TaskAnswersApiController do
  @moduledoc """
  Autosave endpoint for a student's answer doc on a learning unit (task).
  Session-authenticated; the student must be enrolled in the task's course,
  the unit must be `open` (not `locked`), and the submission still editable
  (not completed/approved).
  """
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.Tasks
  alias Tasky.Tasks.{Task, TaskSubmission}

  # The native answer fields send only their values; the server sets them into
  # its own skeleton (`Tasks.save_student_answer_fields/3`).
  def update(conn, %{"id" => task_id} = params)
      when is_map_key(params, "answers") or is_map_key(params, "choices") do
    answers = Map.take(params, ["answers", "choices"])

    save(conn, task_id, &Tasks.save_student_answer_fields(&1, &2, answers))
  end

  # The whole doc, from a student still on the Tiptap editor.
  def update(conn, %{"id" => task_id, "content" => content}) when is_map(content) do
    save(conn, task_id, &Tasks.save_student_answers(&1, &2, content))
  end

  def update(conn, _params) do
    json_error(conn, :bad_request, "Ungültiger Inhalt.")
  end

  defp save(conn, task_id, save_fun) do
    scope = conn.assigns.current_scope
    user = scope.user

    # `locked` ("Bald verfügbar") must be refused here too — `TaskLive.mount`
    # redirects away from a locked unit, so without this the autosave endpoint
    # is the one way into it.
    with %Task{status: "open"} = task <- Tasks.get_task_for_student(scope, task_id),
         %TaskSubmission{} = submission <- Tasks.get_submission_for_student(task.id, user.id) do
      case save_fun.(scope, submission) do
        {:error, :not_editable} ->
          json_error(conn, :conflict, "Die Aufgabe ist bereits als erledigt markiert.")

        {:error, :too_long} ->
          json_error(conn, :unprocessable_entity, "Eine Antwort ist zu lang.")

        result ->
          render_save_result(conn, result)
      end
    else
      _ -> json_error(conn, :not_found, "Aufgabe nicht gefunden.")
    end
  end
end
