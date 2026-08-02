defmodule TaskyWeb.CourseLive.AddTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.TasksFixtures

  alias Tasky.Tasks

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    course = course_fixture(scope: scope, attrs: %{name: "Original"})

    %{conn: log_in_user(conn, teacher), scope: scope, course: course}
  end

  defp created_task(course_id), do: course_id |> Tasks.list_tasks_by_course() |> List.last()

  test "creates a mandatory draft unit by default", %{conn: conn, course: course} do
    {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/add")

    lv |> form("#add-task-form", task: %{name: "Kapitel 1"}) |> render_submit()

    task = created_task(course.id)
    assert task.name == "Kapitel 1"
    assert task.status == "draft"
    refute task.extended
  end

  test "creates an extended unit when the checkbox is ticked", %{conn: conn, course: course} do
    {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/add")

    lv
    |> form("#add-task-form", task: %{name: "Vertiefung", extended: "true"})
    |> render_submit()

    task = created_task(course.id)
    assert task.name == "Vertiefung"
    assert task.extended
  end

  test "the checkbox explains that the unit is voluntary", %{conn: conn, course: course} do
    {:ok, _lv, html} = live(conn, ~p"/courses/#{course}/add")

    assert html =~ "Erweiterte Lerneinheit"
    assert html =~ "zählt nicht zum Fortschrittsbalken"
  end

  test "a blank name keeps the form on screen and creates nothing", %{
    conn: conn,
    course: course
  } do
    {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/add")

    html = lv |> form("#add-task-form", task: %{name: "   "}) |> render_submit()

    assert html =~ "Name darf nicht leer sein."
    assert Tasks.list_tasks_by_course(course.id) == []
  end

  test "the new unit is appended behind the existing ones", %{
    conn: conn,
    scope: scope,
    course: course
  } do
    task_fixture(scope, %{name: "Einheit 1", position: 0, course_id: course.id})
    task_fixture(scope, %{name: "Einheit 2", position: 1, course_id: course.id})

    {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/add")
    lv |> form("#add-task-form", task: %{name: "Einheit 3"}) |> render_submit()

    assert created_task(course.id).position == 2
  end
end
