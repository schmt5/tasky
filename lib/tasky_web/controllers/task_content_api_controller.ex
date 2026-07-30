defmodule TaskyWeb.TaskContentApiController do
  use TaskyWeb, :controller

  import TaskyWeb.ApiHelpers

  alias Tasky.Tasks

  def update(conn, %{"id" => id, "content" => content}) when is_map(content) do
    scope = conn.assigns.current_scope
    task = Tasks.get_task!(scope, id)

    render_save_result(conn, Tasks.save_task_content(scope, task, content))
  end

  def update(conn, _params) do
    json_error(conn, :bad_request, "Missing or invalid content field")
  end
end
