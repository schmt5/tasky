defmodule TaskyWeb.Guest.ExamSubmissionContentApiController do
  use TaskyWeb, :controller

  alias Tasky.Exams

  def update(conn, %{"token" => token, "content" => content}) when is_map(content) do
    submission = Exams.get_exam_submission_by_token!(token)

    case Exams.update_exam_submission_content(submission, content) do
      {:ok, updated} ->
        json(conn, %{ok: true, updated_at: updated.updated_at})

      {:error, :already_submitted} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Submission already submitted"})

      {:error, :exam_not_running} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Exam is not running"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid content", details: translate_errors(changeset)})
    end
  end

  def update(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing or invalid content field"})
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
