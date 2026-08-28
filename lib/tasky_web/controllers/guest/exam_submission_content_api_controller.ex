defmodule TaskyWeb.Guest.ExamSubmissionContentApiController do
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.Exams

  def update(conn, %{"token" => token, "content" => content}) when is_map(content) do
    # `TaskyWeb.Plugs.SebGuard` has already loaded this submission when the exam
    # runs with SEB; reuse it rather than hitting the database twice on what is
    # the hottest write path in the app.
    submission =
      conn.assigns[:seb_submission] || Exams.get_exam_submission_by_token!(token)

    case Exams.update_exam_submission_content(submission, content) do
      {:error, :already_submitted} ->
        json_error(conn, :conflict, "Submission already submitted")

      {:error, :exam_not_running} ->
        json_error(conn, :conflict, "Exam is not running")

      result ->
        render_save_result(conn, result)
    end
  end

  def update(conn, _params) do
    json_error(conn, :bad_request, "Missing or invalid content field")
  end
end
