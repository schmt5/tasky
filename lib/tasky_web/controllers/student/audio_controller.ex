defmodule TaskyWeb.Student.AudioController do
  @moduledoc """
  A student's audio blocks in a learning unit: the play state (`start`,
  `progress`, `finish`, JSON) and the file itself (`show`), which is only
  handed out while `Tasky.Tasks.learner_audio_source/3` allows it.
  """
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers
  import TaskyWeb.StorageServing

  alias Tasky.Tasks
  alias Tasky.Tasks.{Task, TaskSubmission}
  alias TaskyWeb.Params

  def show(conn, %{"task_id" => task_id, "audio_id" => audio_id}) do
    scope = conn.assigns.current_scope

    with task_id when is_integer(task_id) <- Params.int(task_id),
         {:ok, {source, content_type}} <- Tasks.learner_audio_source(scope, task_id, audio_id) do
      serve_media(conn, source, content_type)
    else
      {:error, :not_playable} -> conn |> put_status(:forbidden) |> text("Nicht freigegeben")
      _ -> conn |> put_status(:not_found) |> text("Nicht gefunden")
    end
  end

  def start(conn, %{"id" => id, "audio_id" => audio_id}),
    do: play(conn, id, &Tasks.start_audio_play(&1, &2, audio_id))

  def progress(conn, %{"id" => id, "audio_id" => audio_id} = params),
    do: play(conn, id, &Tasks.record_audio_progress(&1, &2, audio_id, params["position"]))

  def finish(conn, %{"id" => id, "audio_id" => audio_id}),
    do: play(conn, id, &Tasks.finish_audio_play(&1, &2, audio_id))

  # Same gate as the answer autosave (TaskAnswersApiController): enrolled,
  # unit open, own submission.
  defp play(conn, task_id, fun) do
    scope = conn.assigns.current_scope

    with task_id when is_integer(task_id) <- Params.int(task_id),
         %Task{status: "open"} = task <- Tasks.get_task_for_student(scope, task_id),
         %TaskSubmission{} = submission <-
           Tasks.get_submission_for_student(task.id, scope.user.id) do
      render_audio_play(conn, fun.(scope, submission))
    else
      _ -> json_error(conn, :not_found, "Aufgabe nicht gefunden.")
    end
  end
end
