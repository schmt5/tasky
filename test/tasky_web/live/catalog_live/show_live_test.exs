defmodule TaskyWeb.CatalogLive.ShowTest do
  use TaskyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.TasksFixtures

  alias Tasky.Courses
  alias Tasky.Tasks

  setup %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "tasky_uploads_test_#{System.unique_integer([:positive])}")
    prev = Application.get_env(:tasky, :uploads_dir)
    Application.put_env(:tasky, :uploads_dir, dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if prev, do: Application.put_env(:tasky, :uploads_dir, prev)
    end)

    author = user_scope_fixture(user_fixture(%{role: "teacher"}))
    viewer = user_fixture(%{role: "teacher"})
    viewer_scope = user_scope_fixture(viewer)

    course = course_fixture(scope: author, attrs: %{name: "Geteilter Kurs"})

    %{
      conn: log_in_user(conn, viewer),
      author: author,
      viewer_scope: viewer_scope,
      course: course
    }
  end

  test "renders the units without the author's release state", %{
    conn: conn,
    author: author,
    course: course
  } do
    task_fixture(author, %{
      name: "Freigegebene Einheit",
      position: 0,
      status: "published",
      locked: true,
      course_id: course.id
    })

    published = catalog_course_fixture(scope: author, course: course)

    {:ok, lv, html} = live(conn, ~p"/catalog/#{published}")

    assert html =~ "Freigegebene Einheit"
    assert html =~ "Du siehst diesen Kurs nur zum Lesen"
    # The author's release state is theirs, not a claim about the copy.
    refute html =~ "Veröffentlicht</span>"
    refute html =~ "Gesperrt"
    assert has_element?(lv, "#import-catalog-course")
  end

  test "expanding a unit mounts the read-only viewer with its content", %{
    conn: conn,
    author: author,
    course: course
  } do
    task = task_fixture(author, %{name: "Mit Inhalt", position: 0, course_id: course.id})

    {:ok, _task} =
      Tasks.save_task_content(author, task, %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Lektionstext"}]}
        ]
      })

    published = catalog_course_fixture(scope: author, course: course)

    {:ok, lv, html} = live(conn, ~p"/catalog/#{published}")

    refute has_element?(lv, "#catalog-unit-viewer-#{task.id}")
    assert html =~ "Inhalt anzeigen"

    html = lv |> element("#toggle-catalog-unit-#{task.id}") |> render_click()

    assert has_element?(
             lv,
             ~s{#catalog-unit-viewer-#{task.id}[phx-hook="ExamReadOnlyViewer"][phx-update="ignore"]}
           )

    assert html =~ "Lektionstext"
    assert html =~ "Inhalt ausblenden"
  end

  test "the import modal warns that everything arrives as a draft", %{
    conn: conn,
    author: author,
    course: course
  } do
    published = catalog_course_fixture(scope: author, course: course)

    {:ok, lv, _html} = live(conn, ~p"/catalog/#{published}")

    html = lv |> element("#import-catalog-course") |> render_click()

    assert has_element?(lv, "#import-catalog-course-modal")
    assert html =~ "als Entwurf und entsperrt"
    assert html =~ "Lernende und Abgaben werden nicht kopiert"
  end

  test "importing creates an own copy of unlocked drafts and navigates there", %{
    conn: conn,
    author: author,
    course: course,
    viewer_scope: viewer_scope
  } do
    task_fixture(author, %{
      name: "Freigegebene Einheit",
      position: 0,
      status: "published",
      locked: true,
      course_id: course.id
    })

    published = catalog_course_fixture(scope: author, course: course)

    {:ok, lv, _html} = live(conn, ~p"/catalog/#{published}")

    lv |> element("#import-catalog-course") |> render_click()
    lv |> element("#confirm-import-catalog-course") |> render_click()

    assert [copy] = Courses.list_courses(viewer_scope)
    assert copy.name == "Geteilter Kurs"
    assert_redirect(lv, ~p"/courses/#{copy}")

    assert [unit] = Tasks.list_tasks_by_course(copy.id)
    assert unit.status == "draft"
    refute unit.locked
  end

  test "a course with files shows the progress modal before redirecting", %{
    conn: conn,
    author: author,
    course: course,
    viewer_scope: viewer_scope
  } do
    task = task_fixture(author, %{name: "Mit Datei", position: 0, course_id: course.id})

    path = Path.join(System.tmp_dir!(), "src_#{System.unique_integer([:positive])}")
    File.write!(path, "bytes")
    on_exit(fn -> File.rm(path) end)

    {:ok, stored} = Tasky.Uploads.save_task_attachment(task.id, path, "arbeitsblatt.pdf")

    {:ok, _attachment} =
      Tasks.create_task_attachment(
        author,
        task,
        Map.put(stored, :original_name, "arbeitsblatt.pdf")
      )

    published = catalog_course_fixture(scope: author, course: course)

    {:ok, lv, _html} = live(conn, ~p"/catalog/#{published}")

    lv |> element("#import-catalog-course") |> render_click()
    html = lv |> element("#confirm-import-catalog-course") |> render_click()

    assert html =~ "Kurs wird übernommen"
    assert html =~ "0/1"

    assert [copy] = Courses.list_courses(viewer_scope)
    assert_redirect(lv, ~p"/courses/#{copy}")
  end

  test "an attachment is offered for download from the preview", %{
    conn: conn,
    author: author,
    course: course
  } do
    task = task_fixture(author, %{name: "Mit Datei", position: 0, course_id: course.id})

    path = Path.join(System.tmp_dir!(), "src_#{System.unique_integer([:positive])}")
    File.write!(path, "bytes")
    on_exit(fn -> File.rm(path) end)

    {:ok, stored} = Tasky.Uploads.save_task_attachment(task.id, path, "arbeitsblatt.pdf")

    {:ok, _attachment} =
      Tasks.create_task_attachment(
        author,
        task,
        Map.put(stored, :original_name, "arbeitsblatt.pdf")
      )

    published = catalog_course_fixture(scope: author, course: course)

    {:ok, lv, _html} = live(conn, ~p"/catalog/#{published}")
    lv |> element("#toggle-catalog-unit-#{task.id}") |> render_click()

    assert has_element?(
             lv,
             ~s{a[href="/uploads/tasks/#{task.id}/attachments/#{stored.stored_filename}"]}
           )
  end

  test "a course that is not in the catalog is a 404", %{conn: conn, course: course} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/catalog/#{course}") end
  end

  test "a malformed toggle_unit id does not take the LiveView down", %{
    conn: conn,
    author: author,
    course: course
  } do
    published = catalog_course_fixture(scope: author, course: course)
    {:ok, lv, _html} = live(conn, ~p"/catalog/#{published}")

    # `String.to_integer/1` raised here, so anything a client can push from the
    # console killed the process — a cheap self-DoS and log flood.
    assert render_click(lv, "toggle_unit", %{"id" => "not-a-number"})
    assert render(lv) =~ "Geteilter Kurs"
  end
end
