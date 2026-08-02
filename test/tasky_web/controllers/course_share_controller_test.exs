defmodule TaskyWeb.CourseShareControllerTest do
  use TaskyWeb.ConnCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.TasksFixtures

  alias Tasky.Courses

  setup %{conn: conn} do
    scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
    course = course_fixture(scope: scope, attrs: %{name: "Webbau", description: "Grundlagen"})
    {:ok, course} = Courses.ensure_share_slug(scope, course)

    %{conn: conn, scope: scope, course: course}
  end

  defp unit(scope, course, attrs) do
    {content, attrs} = Map.pop(attrs, :content)
    task = task_fixture(scope, Map.merge(%{course_id: course.id, position: 0}, attrs))

    # Content has its own changeset (see Tasks.save_task_content/3) and is not
    # castable through create_task.
    if content do
      {:ok, task} = Tasky.Tasks.save_task_content(scope, task, content)
      task
    else
      task
    end
  end

  defp paragraph(string) do
    %{
      "type" => "doc",
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => string}]}
      ]
    }
  end

  test "serves the whole course as plain-text markdown without a login", %{
    conn: conn,
    scope: scope,
    course: course
  } do
    unit(scope, course, %{
      name: "Einstieg",
      position: 0,
      status: "published",
      content: paragraph("HTML ist eine Auszeichnungssprache.")
    })

    unit(scope, course, %{name: "Vertiefung", position: 1, content: paragraph("CSS gestaltet.")})

    conn = get(conn, ~p"/share/course/#{course.share_slug}")

    assert response_content_type(conn, :text) =~ "charset=utf-8"
    body = response(conn, 200)

    assert body =~ "# Webbau"
    assert body =~ "Grundlagen"
    assert body =~ "## 1. Einstieg"
    assert body =~ "HTML ist eine Auszeichnungssprache."
    assert body =~ "## 2. Vertiefung"
    assert body =~ "CSS gestaltet."
  end

  test "includes drafts and marks them", %{conn: conn, scope: scope, course: course} do
    unit(scope, course, %{name: "Rohfassung", status: "draft", content: paragraph("Entwurfstext")})

    body = conn |> get(~p"/share/course/#{course.share_slug}") |> response(200)

    assert body =~ "Entwurfstext"
    assert body =~ "_Entwurf_"
  end

  test "makes image sources absolute", %{conn: conn, scope: scope, course: course} do
    content = %{
      "type" => "doc",
      "content" => [%{"type" => "image", "attrs" => %{"src" => "/uploads/tasks/1/a.png"}}]
    }

    unit(scope, course, %{name: "Bild", content: content})

    body = conn |> get(~p"/share/course/#{course.share_slug}") |> response(200)

    assert body =~ "#{TaskyWeb.Endpoint.url()}/uploads/tasks/1/a.png"
  end

  test "answers an unknown slug with 404", %{conn: conn} do
    conn = get(conn, ~p"/share/course/#{"nicht-vergeben"}")

    assert response(conn, 404) =~ "Kurs nicht gefunden."
  end

  test "accepts a request that only wants text/plain", %{conn: conn, course: course} do
    conn =
      conn
      |> put_req_header("accept", "text/plain")
      |> get(~p"/share/course/#{course.share_slug}")

    assert response(conn, 200) =~ "# Webbau"
  end

  test "does not leak submissions or student data", %{conn: conn, scope: scope, course: course} do
    student = user_fixture(%{role: "student", email: "lernende@example.com"})
    enroll_fixture(course, student)
    unit(scope, course, %{name: "Einstieg", content: paragraph("Inhalt")})

    body = conn |> get(~p"/share/course/#{course.share_slug}") |> response(200)

    refute body =~ "lernende@example.com"
  end
end
