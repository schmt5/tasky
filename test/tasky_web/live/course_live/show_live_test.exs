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
    task_fixture(scope, %{name: "Einheit 1", position: 0, course_id: course.id})

    %{conn: log_in_user(conn, teacher), scope: scope, course: course}
  end

  describe "Inhalt duplizieren" do
    test "the header offers the action next to Bearbeiten", %{conn: conn, course: course} do
      {:ok, lv, html} = live(conn, ~p"/courses/#{course}")

      assert has_element?(lv, "#duplicate-course")
      assert html =~ "Inhalt duplizieren"
    end

    test "duplicating navigates to the new course", %{conn: conn, scope: scope, course: course} do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}")

      assert {:error, {:live_redirect, %{to: to}}} =
               lv |> element("#duplicate-course") |> render_click()

      [copy] = Enum.reject(Courses.list_courses(scope), &(&1.id == course.id))
      assert to == ~p"/courses/#{copy}"
      assert copy.name == "Kopie von — Original"

      assert [copied_task] = Tasks.list_tasks_by_course(copy.id)
      assert copied_task.name == "Einheit 1"
    end
  end
end
