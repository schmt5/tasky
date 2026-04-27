defmodule TaskyWeb.ExamSampleSolutionApiController do
  use TaskyWeb, :controller

  alias Tasky.Exams

  def update_part(conn, %{"id" => id, "part_id" => part_id, "nodes" => nodes})
      when is_list(nodes) do
    exam = Exams.get_exam!(conn.assigns.current_scope, id)

    case Exams.update_sample_solution_part_content(exam, part_id, nodes) do
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

  def update_part(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing or invalid params"})
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
