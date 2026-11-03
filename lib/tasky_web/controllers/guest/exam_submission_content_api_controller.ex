defmodule TaskyWeb.Guest.ExamSubmissionContentApiController do
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.Exams

  # The native answer fields send only their values; the server sets them into
  # its own skeleton (`Exams.save_exam_submission_answers/2`).
  def update(conn, %{"token" => token} = params)
      when is_map_key(params, "answers") or is_map_key(params, "choices") do
    submission = load_submission(conn, token)
    answers = Map.take(params, ["answers", "choices"])

    render_result(conn, Exams.save_exam_submission_answers(submission, answers))
  end

  # The whole doc: a free-document exam, or a learner still on the Tiptap
  # editor (`Exams.update_exam_submission_content/2`).
  def update(conn, %{"token" => token, "content" => content}) when is_map(content) do
    submission = load_submission(conn, token)

    render_result(conn, Exams.update_exam_submission_content(submission, content))
  end

  def update(conn, _params) do
    json_error(conn, :bad_request, "Ungültiger Inhalt.")
  end

  # `TaskyWeb.Plugs.SebGuard` has already loaded this submission when the exam
  # runs with SEB; reuse it rather than hitting the database twice on what is
  # the hottest write path in the app. Otherwise only its ids are loaded — the
  # write re-reads both rows under lock anyway.
  defp load_submission(conn, token) do
    conn.assigns[:seb_submission] || Exams.get_submission_for_write_by_token!(token)
  end

  defp render_result(conn, result) do
    case result do
      {:error, :already_submitted} ->
        json_error(conn, :conflict, "Die Abgabe ist bereits eingereicht.")

      {:error, :exam_not_running} ->
        json_error(conn, :conflict, "Die Prüfung läuft nicht.")

      {:error, :too_long} ->
        json_error(conn, :unprocessable_entity, "Eine Antwort ist zu lang.")

      result ->
        render_save_result(conn, result)
    end
  end
end
