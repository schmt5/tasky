defmodule TaskyWeb.ExamPaperLayoutApiController do
  @moduledoc """
  Autosave target of the paper-version editor (`TaskyWeb.ExamLive.Paper`).

  Receives the whole document like every other editor, but only the answer-box
  line counts are persisted — see `Tasky.Exams.update_paper_layout/3`. The
  exam's `content` is never written from here.
  """

  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.Exams

  def update(conn, %{"id" => id, "content" => content}) when is_map(content) do
    scope = conn.assigns.current_scope
    exam = Exams.get_exam!(scope, id)

    render_save_result(conn, Exams.update_paper_layout(scope, exam, content))
  end

  def update(conn, _params) do
    json_error(conn, :bad_request, "Missing or invalid content field")
  end
end
