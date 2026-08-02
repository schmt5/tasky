defmodule TaskyWeb.CourseShareController do
  @moduledoc """
  Serves a whole course as one Markdown document under its share slug —
  the link a teacher hands to an AI tool ("lies dir diesen Kurs durch und
  erstelle Prüfungsaufgaben").

  Public by design: the 128-bit `courses.share_slug` is the only credential,
  the same model as an exam submission token. The route is rate limited in the
  router so the slug cannot be probed.

  The body is Markdown but the content type is `text/plain`, so browsers show
  it inline instead of downloading it and every fetcher accepts it.
  """

  use TaskyWeb, :controller

  alias Tasky.Courses
  alias Tasky.Courses.CourseExport
  alias Tasky.Tasks

  def show(conn, %{"share_slug" => slug}) do
    case Courses.get_course_by_share_slug(slug) do
      nil ->
        conn
        |> put_resp_content_type("text/plain", "utf-8")
        |> send_resp(:not_found, "Kurs nicht gefunden.\n")

      course ->
        markdown =
          CourseExport.to_markdown(
            course,
            Tasks.list_tasks_for_export(course.id),
            base_url: TaskyWeb.Endpoint.url()
          )

        conn
        |> put_resp_content_type("text/plain", "utf-8")
        |> send_resp(:ok, markdown)
    end
  end
end
