defmodule TaskyWeb.ExamCorrectionContentApiController do
  use TaskyWeb, :controller

  alias Tasky.Exams

  def update(
        conn,
        %{
          "id" => exam_id,
          "submission_id" => submission_id,
          "part_id" => part_id,
          "nodes" => nodes
        }
      )
      when is_list(nodes) do
    exam = Exams.get_exam!(conn.assigns.current_scope, exam_id)

    submission =
      Tasky.Repo.get_by!(Tasky.Exams.ExamSubmission,
        id: submission_id,
        exam_id: exam.id
      )

    case Exams.update_corrected_part_content(submission, part_id, nodes) do
      {:ok, updated} ->
        json(conn, %{ok: true, updated_at: updated.updated_at})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid content", details: translate_errors(changeset)})
    end
  rescue
    ArgumentError ->
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "Unknown part_id"})
  end

  def update(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing or invalid params"})
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
