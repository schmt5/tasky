defmodule TaskyWeb.ExamContentApiController do
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.Exams

  def update(conn, %{"id" => id, "content" => content}) when is_map(content) do
    scope = conn.assigns.current_scope
    exam = Exams.get_exam!(scope, id)

    render_save_result(conn, Exams.save_exam_structure(scope, exam, content))
  end

  def update(conn, _params) do
    json_error(conn, :bad_request, "Missing or invalid content field")
  end
end
