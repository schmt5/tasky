defmodule TaskyWeb.ExamContentApiController do
  use TaskyWeb, :controller

  alias Tasky.Exams

  def update(conn, %{"id" => id, "content" => content}) when is_map(content) do
    exam = Exams.get_exam!(conn.assigns.current_scope, id)

    case Exams.update_exam(exam, %{content: content}) do
      {:ok, updated} ->
        json(conn, %{ok: true, updated_at: updated.updated_at})

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
