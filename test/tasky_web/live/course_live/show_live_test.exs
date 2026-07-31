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
      assert html =~ "Umbenennen"

      # The unit name is the only way into the content editor; the row's old
      # duplicate "Bearbeiten" link is gone.
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
