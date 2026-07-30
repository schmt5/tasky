defmodule TaskyWeb.Student.TaskLiveTest do
  use TaskyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.TasksFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Courses

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    student = user_fixture(%{role: "student"})
    {:ok, course} = Courses.create_course(Scope.for_user(teacher), %{name: "Testkurs"})
    task = task_fixture(teacher, %{name: "Testaufgabe", course_id: course.id})

    %{conn: log_in_user(conn, student), student: student, course: course, task: task}
  end

  test "enrolled student can open the task", %{
    conn: conn,
    student: student,
    course: course,
    task: task
  } do
    {:ok, _} = Courses.enroll_student(course.id, student.id)

    {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}")
    assert html =~ "Testaufgabe"
  end

  test "student not enrolled in the course is redirected and no submission is created", %{
    conn: conn,
    student: student,
    task: task
  } do
    assert {:error, {:live_redirect, %{to: "/student/courses"}}} =
             live(conn, ~p"/student/tasks/#{task.id}")

    refute Tasky.Tasks.get_submission_for_student(task.id, student.id)
  end

  test "malformed task id redirects instead of crashing", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/student/courses"}}} =
             live(conn, "/student/tasks/not-a-number")
  end

  test "autosave API rejects a non-enrolled student", %{conn: conn, task: task} do
    conn =
      put(conn, "/api/student/tasks/#{task.id}/answers", %{
        "content" => %{"type" => "doc", "content" => []}
      })

    assert json_response(conn, 404)
  end
end
