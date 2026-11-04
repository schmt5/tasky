defmodule TaskyWeb.Guest.AudioController do
  @moduledoc """
  An exam participant's audio blocks: the play state (`start`, `progress`,
  `finish`, JSON) and the file itself (`show`), which is only handed out while
  `Tasky.Exams.learner_audio_source/2` allows it. Gated by the exam token, like
  the rest of the guest surface.
  """
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers
  import TaskyWeb.StorageServing

  alias Tasky.Exams

  def show(conn, %{"exam_token" => token, "audio_id" => audio_id}) do
    case Exams.learner_audio_source(token, audio_id) do
      {:ok, {source, content_type}} ->
        serve_media(conn, source, content_type)

      {:error, :not_playable} ->
        conn |> put_status(:forbidden) |> text("Nicht freigegeben")

      {:error, _} ->
        conn |> put_status(:not_found) |> text("Nicht gefunden")
    end
  end

  def start(conn, %{"token" => token, "audio_id" => audio_id}),
    do: render_audio_play(conn, Exams.start_audio_play(load_submission(conn, token), audio_id))

  def progress(conn, %{"token" => token, "audio_id" => audio_id} = params) do
    submission = load_submission(conn, token)
    render_audio_play(conn, Exams.record_audio_progress(submission, audio_id, params["position"]))
  end

  def finish(conn, %{"token" => token, "audio_id" => audio_id}),
    do: render_audio_play(conn, Exams.finish_audio_play(load_submission(conn, token), audio_id))

  # See ExamSubmissionContentApiController: reuse what SebGuard loaded.
  defp load_submission(conn, token) do
    conn.assigns[:seb_submission] || Exams.get_submission_for_write_by_token!(token)
  end
end
