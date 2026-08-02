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

  describe "Fortschritt mit erweiterten Lerneinheiten" do
    # Adds units to the course of the outer setup, which already contains one
    # completed mandatory unit ("Testaufgabe").
    defp add_unit(teacher_scope, course, name, attrs) do
      task_fixture(
        teacher_scope,
        Map.merge(%{name: name, course_id: course.id, status: "published"}, attrs)
      )
    end

    test "an extension is left out of the bar and counted on its own", %{
      conn: conn,
      teacher_scope: teacher_scope,
      student_scope: student_scope,
      course: course
    } do
      add_unit(teacher_scope, course, "Pflicht 2", %{position: 1})
      extension = add_unit(teacher_scope, course, "Vertiefung", %{position: 2, extended: true})

      {:ok, sub} = Tasks.get_or_create_submission(student_scope, extension.id)
      {:ok, _} = Tasks.complete_task(student_scope, sub.id)

      {:ok, _lv, html} = live(conn, ~p"/student/courses/#{course.id}")

      # 1 von 2 Pflichtaufgaben erledigt — die erledigte Erweiterung zählt nicht mit.
      assert html =~ "50%"
      assert html =~ "1 / 2 Pflichtaufgaben"
      assert html =~ "+1 Erweiterung"
      assert html =~ "Erweitert · freiwillig"
    end

    test "open extensions do not hold the bar back", %{
      conn: conn,
      teacher_scope: teacher_scope,
      course: course
    } do
      add_unit(teacher_scope, course, "Vertiefung A", %{position: 1, extended: true})
      add_unit(teacher_scope, course, "Vertiefung B", %{position: 2, extended: true})

      {:ok, _lv, html} = live(conn, ~p"/student/courses/#{course.id}")

      # Die einzige Pflichtaufgabe ist im Setup schon erledigt.
      assert html =~ "100%"
      assert html =~ "Alle Pflichtaufgaben erledigt!"
      assert html =~ "1 / 1 Pflichtaufgaben"
    end

    test "a course of nothing but extensions has no mandatory work to show", %{
      conn: conn,
      teacher_scope: teacher_scope,
      student_scope: student_scope
    } do
      {:ok, course} = Courses.create_course(teacher_scope, %{name: "Nur Freiwilliges"})
      {:ok, _} = Courses.enroll_student(course.id, student_scope.user.id)
      add_unit(teacher_scope, course, "Vertiefung", %{position: 0, extended: true})

      {:ok, _lv, html} = live(conn, ~p"/student/courses/#{course.id}")

      assert html =~ "Keine Pflichtaufgaben"
      assert html =~ "100%"
      refute html =~ "Alle Pflichtaufgaben erledigt!"
    end

    test "the active-unit pointer skips an extension while mandatory work is open", %{
      conn: conn,
      teacher_scope: teacher_scope,
      student_scope: student_scope,
      course: course
    } do
      extension = add_unit(teacher_scope, course, "Vertiefung", %{position: 1, extended: true})
      pflicht = add_unit(teacher_scope, course, "Pflicht 2", %{position: 2})

      {:ok, _} = Tasks.get_or_create_submission(student_scope, extension.id)
      {:ok, _} = Tasks.get_or_create_submission(student_scope, pflicht.id)

      {:ok, lv, _html} = live(conn, ~p"/student/courses/#{course.id}")

      # Die offene Pflichtaufgabe ist "dran" (blau hervorgehoben), nicht die
      # davor stehende Erweiterung — beide heissen "Starten".
      assert has_element?(lv, ~s(a[href="/student/tasks/#{pflicht.id}"].bg-sky-500))
      refute has_element?(lv, ~s(a[href="/student/tasks/#{extension.id}"].bg-sky-500))
    end
  end
end
