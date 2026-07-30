defmodule TaskyWeb.ExamSampleSolutionApiController do
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.Exams

  def update_part(conn, %{"id" => id, "part_id" => part_id, "nodes" => nodes})
      when is_list(nodes) do
    scope = conn.assigns.current_scope
    exam = Exams.get_exam!(scope, id)

    render_save_result(conn, Exams.save_sample_solution_part(scope, exam, part_id, nodes))
  rescue
    ArgumentError ->
      json_error(conn, :unprocessable_entity, "Unknown part_id")
  end

  def update_part(conn, _params) do
    json_error(conn, :bad_request, "Missing or invalid params")
  end
end
