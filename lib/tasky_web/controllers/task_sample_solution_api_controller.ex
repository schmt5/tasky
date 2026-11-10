defmodule TaskyWeb.TaskSampleSolutionApiController do
  @moduledoc """
  Autosave-Endpunkt des Musterlösungs-Editors einer Lerneinheit: wie bei
  Prüfungen eine Knotenliste pro Frage (`part_id`).
  """
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.Tasks

  def update_part(conn, %{"id" => id, "part_id" => part_id, "nodes" => nodes})
      when is_list(nodes) do
    scope = conn.assigns.current_scope
    task = Tasks.get_task!(scope, id)

    case Tasks.save_sample_solution_part(scope, task, part_id, nodes) do
      {:error, :unknown_part} -> json_error(conn, :unprocessable_entity, "Unbekannte Frage.")
      result -> render_save_result(conn, result)
    end
  end

  def update_part(conn, _params) do
    json_error(conn, :bad_request, "Ungültige Anfrage.")
  end
end
