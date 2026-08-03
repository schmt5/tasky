defmodule TaskyWeb.CourseLive.ShowTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.TasksFixtures

  alias Tasky.Courses
  alias Tasky.Tasks

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    course = course_fixture(scope: scope, attrs: %{name: "Original"})
    task = task_fixture(scope, %{name: "Einheit 1", position: 0, course_id: course.id})

    %{conn: log_in_user(conn, teacher), scope: scope, course: course, task: task}
  end

  # The unit as it is actually stored, ignoring whatever the LiveView renders.
  defp reload(task), do: Tasky.Repo.get!(Tasky.Tasks.Task, task.id)

  describe "KI-Link" do
    test "the header offers the action", %{conn: conn, course: course} do
      {:ok, lv, html} = live(conn, ~p"/courses/#{course}")

      assert has_element?(lv, "#share-course")
      assert html =~ "KI-Link"
      refute has_element?(lv, "#share-course-modal")
    end

    test "opening it creates the slug and shows the public URL", %{
      conn: conn,
      course: course,
      scope: scope
    } do
      refute course.share_slug

      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")
      html = lv |> element("#share-course") |> render_click()

      slug = Courses.get_course!(scope, course.id).share_slug

      assert has_element?(lv, "#share-course-modal")
      assert is_binary(slug)
      assert html =~ "/share/course/#{slug}"
      assert html =~ "Jede Person mit diesem Link kann den gesamten Kursinhalt lesen"
    end

    test "reopening keeps the same link", %{conn: conn, course: course, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")

      lv |> element("#share-course") |> render_click()
      lv |> element("#share-course-modal button[phx-click='close_share']") |> render_click()
      lv |> element("#share-course") |> render_click()

      {:ok, shared} = Courses.ensure_share_slug(scope, Courses.get_course!(scope, course.id))

      assert has_element?(
               lv,
               "#share-course-url[value='#{url(~p"/share/course/#{shared.share_slug}")}']"
             )
    end

    test "the copy button pushes the URL to the clipboard", %{conn: conn, course: course} do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")
      lv |> element("#share-course") |> render_click()

      lv |> element("#copy-share-url") |> render_click()

      assert_push_event(lv, "copy-to-clipboard", %{text: text})
      assert text =~ "/share/course/"
    end

    test "closing it hides the modal", %{conn: conn, course: course} do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")
      lv |> element("#share-course") |> render_click()

      lv |> element("#share-course-modal button[phx-click='close_share']") |> render_click()

      refute has_element?(lv, "#share-course-modal")
    end
  end

  describe "Inhalt duplizieren" do
    test "the header offers the action next to Bearbeiten", %{conn: conn, course: course} do
      {:ok, lv, html} = live(conn, ~p"/courses/#{course}")

      assert has_element?(lv, "#duplicate-course")
      assert html =~ "Inhalt duplizieren"
    end

    test "the action asks for confirmation in a modal, not a native dialog", %{
      conn: conn,
      course: course
    } do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")

      refute has_element?(lv, "#duplicate-course[data-confirm]")
      refute has_element?(lv, "#duplicate-course-modal")

      html = lv |> element("#duplicate-course") |> render_click()

      assert has_element?(lv, "dialog#duplicate-course-modal.modal-open")
      assert html =~ "Lernende und Abgaben werden nicht kopiert."

      lv |> element("#duplicate-course-modal button", "Abbrechen") |> render_click()
      refute has_element?(lv, "#duplicate-course-modal")
    end

    test "duplicating navigates to the new course", %{conn: conn, scope: scope, course: course} do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")

      lv |> element("#duplicate-course") |> render_click()

      assert {:error, {:live_redirect, %{to: to}}} =
               lv |> element("#confirm-duplicate-course") |> render_click()

      [copy] = Enum.reject(Courses.list_courses(scope), &(&1.id == course.id))
      assert to == ~p"/courses/#{copy}"
      assert copy.name == "Kopie von — Original"

      assert [copied_task] = Tasks.list_tasks_by_course(copy.id)
      assert copied_task.name == "Einheit 1"
    end

    test "a course with files shows copy progress before redirecting", %{
      conn: conn,
      scope: scope,
      course: course,
      task: task
    } do
      path = Path.join(System.tmp_dir!(), "src_#{System.unique_integer([:positive])}")
      File.write!(path, "bytes")
      on_exit(fn -> File.rm(path) end)

      {:ok, stored} = Tasky.Uploads.save_task_attachment(task.id, path, "arbeitsblatt.pdf")

      {:ok, _attachment} =
        Tasks.create_task_attachment(task, Map.put(stored, :original_name, "arbeitsblatt.pdf"))

      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")
      lv |> element("#duplicate-course") |> render_click()

      # The records are committed synchronously, so the copy phase must not
      # hold up the reply — the dialog is up while the bytes are still moving.
      html = lv |> element("#confirm-duplicate-course") |> render_click()
      assert html =~ "Kurs wird dupliziert"
      assert html =~ "0/1"

      [copy] = Enum.reject(Courses.list_courses(scope), &(&1.id == course.id))
      assert_redirect(lv, ~p"/courses/#{copy}")
    end
  end

  describe "learning unit actions dropdown" do
    test "the row offers a single actions menu instead of a flat button row", %{
      conn: conn,
      course: course,
      task: task
    } do
      {:ok, lv, html} = live(conn, ~p"/courses/#{course}")

      assert has_element?(lv, ~s{label#task-actions-#{task.id}[aria-label="Aktionen"]})
      assert has_element?(lv, ~s{button[phx-click="open_rename"][phx-value-id="#{task.id}"]})
      assert html =~ "Bearbeiten"

      # The unit name is the only way into the content editor; the row's old
      # duplicate "Bearbeiten" link is gone — the dropdown entry is a button.
      assert has_element?(lv, ~s{a[href="/tasks/#{task.id}/content"]}, "Einheit 1")
      refute has_element?(lv, ~s{a[href="/tasks/#{task.id}/content"]}, "Bearbeiten")
    end

    test "toggle_status flips the unit between draft and published", %{
      conn: conn,
      course: course,
      task: task
    } do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")
      selector = ~s{button[phx-click="toggle_status"][phx-value-id="#{task.id}"]}

      lv |> element(selector) |> render_click()
      assert reload(task).status == "published"

      lv |> element(selector) |> render_click()
      assert reload(task).status == "draft"
    end

    test "toggle_locked locks and releases the unit", %{conn: conn, course: course, task: task} do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")
      selector = ~s{button[phx-click="toggle_locked"][phx-value-id="#{task.id}"]}

      html = lv |> element(selector) |> render_click()

      assert reload(task).locked
      assert html =~ "Gesperrt"
      assert html =~ "Freigeben"

      lv |> element(selector) |> render_click()
      refute reload(task).locked
    end

    test "delete_task removes the unit", %{conn: conn, course: course, task: task} do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")

      render_click(lv, "delete_task", %{"id" => task.id})

      assert Tasks.list_tasks_by_course(course.id) == []
      assert render(lv) =~ "Noch keine Lerneinheiten"
    end
  end

  describe "erweiterte Lerneinheit" do
    test "the row marks an extended unit and explains what it means", %{
      conn: conn,
      scope: scope,
      course: course
    } do
      task_fixture(scope, %{
        name: "Vertiefung",
        position: 1,
        course_id: course.id,
        extended: true
      })

      {:ok, _lv, html} = live(conn, ~p"/courses/#{course}")

      assert html =~ "Erweitert"
      assert html =~ "zählt nicht zum Pflicht-Fortschritt"
    end

    test "a mandatory unit shows no extension chip", %{conn: conn, course: course} do
      {:ok, _lv, html} = live(conn, ~p"/courses/#{course}")

      refute html =~ "Erweitert"
    end

    test "the edit modal turns a unit into an extension and back", %{
      conn: conn,
      course: course,
      task: task
    } do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")

      lv
      |> element(~s{button[phx-click="open_rename"][phx-value-id="#{task.id}"]})
      |> render_click()

      assert has_element?(lv, "#rename-task-form")

      html =
        lv
        |> form("#rename-task-form", task: %{name: "Einheit 1", extended: "true"})
        |> render_submit()

      assert reload(task).extended
      assert html =~ "Erweitert"

      lv
      |> element(~s{button[phx-click="open_rename"][phx-value-id="#{task.id}"]})
      |> render_click()

      lv
      |> form("#rename-task-form", task: %{name: "Einheit 1", extended: "false"})
      |> render_submit()

      refute reload(task).extended
    end
  end

  describe "renaming a learning unit" do
    test "saving a new name updates the unit and its row", %{
      conn: conn,
      course: course,
      task: task
    } do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")

      lv
      |> element(~s{button[phx-click="open_rename"][phx-value-id="#{task.id}"]})
      |> render_click()

      assert has_element?(lv, "#rename-task-form")

      html =
        lv
        |> form("#rename-task-form", task: %{name: "Kapitel 1 – Grundlagen"})
        |> render_submit()

      assert reload(task).name == "Kapitel 1 – Grundlagen"
      assert html =~ "Kapitel 1 – Grundlagen"
      refute has_element?(lv, "#rename-task-form")
    end

    test "a blank name keeps the modal open and the name unchanged", %{
      conn: conn,
      course: course,
      task: task
    } do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")

      lv
      |> element(~s{button[phx-click="open_rename"][phx-value-id="#{task.id}"]})
      |> render_click()

      lv |> form("#rename-task-form", task: %{name: "   "}) |> render_submit()

      assert reload(task).name == "Einheit 1"
      assert has_element?(lv, "#rename-task-form")
    end

    test "Abbrechen closes the modal without saving", %{
      conn: conn,
      course: course,
      task: task
    } do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")

      lv
      |> element(~s{button[phx-click="open_rename"][phx-value-id="#{task.id}"]})
      |> render_click()

      render_click(lv, "close_rename", %{})

      refute has_element?(lv, "#rename-task-form")
      assert reload(task).name == "Einheit 1"
    end

    test "a teacher cannot rename a unit they do not own", %{conn: conn, task: task} do
      other = user_fixture(%{role: "teacher"})
      other_course = course_fixture(scope: user_scope_fixture(other))

      {:ok, lv, _html} = live(log_in_user(conn, other), ~p"/courses/#{other_course}")

      # `Tasks.get_task!/2` refuses the foreign id, taking the LiveView down
      # with it rather than handing over someone else's unit.
      Process.flag(:trap_exit, true)
      catch_exit(render_click(lv, "open_rename", %{"id" => task.id}))

      assert reload(task).name == "Einheit 1"
    end
  end
end
