defmodule TaskyWeb.TaskSampleSolutionApiController do
  @moduledoc """
  Autosave-Endpunkt des Musterlösungs-Editors einer Lerneinheit.

  Anders als bei Prüfungen kommt hier das *ganze* Dokument (`content`) statt
  einer Knotenliste pro Frage: Lerneinheiten kennen keine Teilaufgaben, es
  gibt also nichts zu splicen.
  """
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.Tasks

  def update(conn, %{"id" => id, "content" => content}) when is_map(content) do
    scope = conn.assigns.current_scope
    task = Tasks.get_task!(scope, id)

    render_save_result(conn, Tasks.save_sample_solution(scope, task, content))
  end

  def update(conn, _params) do
    json_error(conn, :bad_request, "Missing or invalid content field")
  end
end
