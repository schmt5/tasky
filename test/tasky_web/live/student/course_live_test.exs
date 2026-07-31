defmodule TaskyWeb.Student.CourseLiveTest do
  @moduledoc """
  Die Kurs-Timeline der Lernenden: Feedback-Hinweis nur mit Text, und eine
  zurückgegebene Lerneinheit muss von hier aus überarbeitbar sein.
  """
  use TaskyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.TasksFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Courses
  alias Tasky.Tasks

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    student = user_fixture(%{role: "student"})
    teacher_scope = Scope.for_user(teacher)
    student_scope = Scope.for_user(student)

    {:ok, course} = Courses.create_course(teacher_scope, %{name: "Testkurs"})

    task =
      task_fixture(teacher_scope, %{
        name: "Testaufgabe",
        course_id: course.id,
        status: "published"
      })

    {:ok, _} = Courses.enroll_student(course.id, student.id)
    {:ok, submission} = Tasks.get_or_create_submission(student_scope, task.id)
    {:ok, submission} = Tasks.complete_task(student_scope, submission.id)

    %{
      conn: log_in_user(conn, student),
      teacher_scope: teacher_scope,
      student_scope: student_scope,
      course: course,
      task: task,
      submission: submission
    }
  end

  test "no feedback pill when the verdict carried no text", %{
    conn: conn,
    teacher_scope: teacher_scope,
    course: course,
    submission: submission
  } do
    {:ok, _} = Tasks.review_submission(teacher_scope, submission.id, "review_approved")

    {:ok, lv, html} = live(conn, ~p"/student/courses/#{course.id}")

    refute html =~ "Feedback"
    refute has_element?(lv, "button[phx-click='show_feedback']")
  end

  test "feedback pill opens the feedback text", %{
    conn: conn,
    teacher_scope: teacher_scope,
    course: course,
    submission: submission
  } do
    {:ok, _} =
      Tasks.review_submission(teacher_scope, submission.id, "review_approved", %{
        feedback: "Sauber gelöst, weiter so"
      })

    {:ok, lv, _html} = live(conn, ~p"/student/courses/#{course.id}")

    html =
      lv
      |> element("button[phx-click='show_feedback']")
      |> render_click()

    assert html =~ "Sauber gelöst, weiter so"
  end

  test "a returned unit can be reached and revised from the timeline", %{
    conn: conn,
    teacher_scope: teacher_scope,
    course: course,
    task: task,
    submission: submission
  } do
    {:ok, _} =
      Tasks.review_submission(teacher_scope, submission.id, "review_denied", %{
        feedback: "Bitte Aufgabe 2 ergänzen"
      })

    {:ok, lv, html} = live(conn, ~p"/student/courses/#{course.id}")

    assert html =~ "Zur Überarbeitung"
    assert has_element?(lv, ~s(a[href="/student/tasks/#{task.id}"]), "Überarbeiten")

    # Der Link führt in die bearbeitbare Einheit, das Feedback bleibt sichtbar.
    {:ok, _task_lv, task_html} = live(conn, ~p"/student/tasks/#{task.id}")

    assert task_html =~ "Zur Überarbeitung zurückgegeben"
    assert task_html =~ "Bitte Aufgabe 2 ergänzen"

    assert Tasks.get_submission_for_student(task.id, submission.student_id).status ==
             "in_revision"
  end

  test "opening a returned unit in preview mode does not change its status", %{
    conn: conn,
    teacher_scope: teacher_scope,
    task: task,
    submission: submission
  } do
    {:ok, _} = Tasks.review_submission(teacher_scope, submission.id, "review_denied")

    {:ok, _lv, _html} = live(conn, ~p"/student/tasks/#{task.id}?preview=true")

    assert Tasks.get_submission_for_student(task.id, submission.student_id).status ==
             "review_denied"
  end
end
