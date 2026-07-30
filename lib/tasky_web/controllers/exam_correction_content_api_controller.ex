defmodule TaskyWeb.ExamCorrectionContentApiController do
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

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
    scope = conn.assigns.current_scope
    exam = Exams.get_exam!(scope, exam_id)
    submission = Exams.get_submission!(exam, submission_id)

    render_save_result(
      conn,
      Exams.update_corrected_part_content(scope, submission, part_id, nodes)
    )
  rescue
    ArgumentError ->
      json_error(conn, :unprocessable_entity, "Unknown part_id")
  end

  def update(conn, _params) do
    json_error(conn, :bad_request, "Missing or invalid params")
  end
end
