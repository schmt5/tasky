defmodule TaskyWeb.TaskCorrectionContentApiController do
  @moduledoc """
  Autosave-Endpunkt des Korrektur-Editors einer Lerneinheit.

  Wie beim Musterlösungs-Endpunkt kommt das ganze Dokument (`content`) statt
  einer Knotenliste pro Frage — Lerneinheiten kennen keine Teilaufgaben.
  """
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.Tasks

  def update(conn, %{"id" => id, "submission_id" => submission_id, "content" => content})
      when is_map(content) do
    scope = conn.assigns.current_scope
    task = Tasks.get_task!(scope, id)

    case Tasks.save_correction_content(scope, task, submission_id, content) do
      {:error, :not_reviewable} ->
        json_error(conn, :conflict, "Diese Abgabe ist noch nicht eingereicht.")

      {:error, :not_found} ->
        json_error(conn, :not_found, "Abgabe nicht gefunden")

      result ->
        render_save_result(conn, result)
    end
  end

  def update(conn, _params) do
    json_error(conn, :bad_request, "Missing or invalid content field")
  end
end
