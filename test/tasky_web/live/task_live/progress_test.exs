defmodule TaskyWeb.TaskLive.ProgressTest do
  @moduledoc """
  Das Review einer Lerneinheit aus Sicht der Lehrperson: Feedback speichern,
  genehmigen, zurückgeben.
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
    student = user_fixture(%{role: "student", firstname: "Mia", lastname: "Muster"})
    teacher_scope = Scope.for_user(teacher)
    student_scope = Scope.for_user(student)

    {:ok, course} = Courses.create_course(teacher_scope, %{name: "Testkurs"})
    task = task_fixture(teacher_scope, %{name: "Testaufgabe", course_id: course.id})
    {:ok, _} = Courses.enroll_student(course.id, student.id)

    {:ok, submission} = Tasks.get_or_create_submission(student_scope, task.id)
    {:ok, submission} = Tasks.complete_task(student_scope, submission.id)

    %{
      conn: log_in_user(conn, teacher),
      student: student,
      task: task,
      submission: submission
    }
  end

  defp open_review(conn, task, student) do
    {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}")

    lv
    |> element("button[phx-click='show_submission'][phx-value-student-id='#{student.id}']")
    |> render_click()

    lv
  end

  defp submit_feedback(lv, params) do
    lv |> form("form[phx-submit='save_feedback']") |> render_submit(params)
  end

  test "sending back stores the feedback, closes the modal and reports it", %{
    conn: conn,
    task: task,
    student: student,
    submission: submission
  } do
    lv = open_review(conn, task, student)

    html =
      submit_feedback(lv, %{
        "submission" => %{"feedback" => "Bitte ergänze Aufgabe 2"},
        "verdict" => "review_denied"
      })

    assert html =~ "zur Überarbeitung zurückgegeben"
    # Modal ist zu: kein Feedback-Formular mehr im DOM.
    refute has_element?(lv, "form[phx-submit='save_feedback']")

    reloaded = Tasks.get_submission_for_student(task.id, student.id)
    assert reloaded.id == submission.id
    assert reloaded.status == "review_denied"
    assert reloaded.feedback == "Bitte ergänze Aufgabe 2"
    assert %DateTime{} = reloaded.feedback_at
  end

  test "approving without feedback leaves no feedback trace", %{
    conn: conn,
    task: task,
    student: student
  } do
    lv = open_review(conn, task, student)

    html =
      submit_feedback(lv, %{
        "submission" => %{"feedback" => ""},
        "verdict" => "review_approved"
      })

    assert html =~ "genehmigt"

    reloaded = Tasks.get_submission_for_student(task.id, student.id)
    assert reloaded.status == "review_approved"
    assert reloaded.feedback == nil
    assert reloaded.feedback_at == nil
  end

  test "saving feedback without a verdict keeps the modal and the status", %{
    conn: conn,
    task: task,
    student: student
  } do
    lv = open_review(conn, task, student)

    submit_feedback(lv, %{"submission" => %{"feedback" => "Zwischenstand notiert"}})

    assert has_element?(lv, "form[phx-submit='save_feedback']")

    reloaded = Tasks.get_submission_for_student(task.id, student.id)
    assert reloaded.status == "completed"
    assert reloaded.feedback == "Zwischenstand notiert"
  end

  test "a foreign teacher gets no access to the unit's progress", %{
    conn: conn,
    task: task
  } do
    other_teacher = user_fixture(%{role: "teacher"})
    conn = conn |> Phoenix.ConnTest.recycle() |> log_in_user(other_teacher)

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/progress/#{task.id}") end
  end
end
