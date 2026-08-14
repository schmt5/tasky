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

  test "sending back asks for confirmation in a modal instead of a native dialog", %{
    conn: conn,
    task: task,
    student: student
  } do
    lv = open_review(conn, task, student)

    refute has_element?(lv, "#return-submission[data-confirm]")
    refute has_element?(lv, "#return-submission-modal")

    html =
      submit_feedback(lv, %{
        "submission" => %{"feedback" => "Bitte ergänze Aufgabe 2"},
        "verdict" => "review_denied"
      })

    assert has_element?(lv, "dialog#return-submission-modal.modal-open")
    assert html =~ "Zur Überarbeitung zurückgeben"
    assert html =~ "Das erfasste Feedback wird mitgeschickt."

    # Nichts passiert, solange nicht bestätigt wurde.
    assert Tasks.get_submission_for_student(task.id, student.id).status == "completed"

    lv |> element("#return-submission-modal button", "Abbrechen") |> render_click()

    refute has_element?(lv, "#return-submission-modal")
    # Die Einreichung bleibt offen, damit weitergearbeitet werden kann.
    assert has_element?(lv, "form[phx-submit='save_feedback']")
  end

  test "sending back stores the feedback, closes the modal and reports it", %{
    conn: conn,
    task: task,
    student: student,
    submission: submission
  } do
    lv = open_review(conn, task, student)

    submit_feedback(lv, %{
      "submission" => %{"feedback" => "Bitte ergänze Aufgabe 2"},
      "verdict" => "review_denied"
    })

    html = lv |> element("#confirm-return-submission") |> render_click()

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

  describe "Freigabe der Musterlösung" do
    test "bietet im Modus never keinen Freigeben-Knopf", %{
      conn: conn,
      task: task,
      student: student
    } do
      lv = open_review(conn, task, student)

      refute has_element?(lv, "button[phx-click='release_solution']")
      assert render(lv) =~ "Für diese Lerneinheit ausgeblendet"
    end

    test "gibt für eine/n Lernende/n frei", %{
      conn: conn,
      task: task,
      student: student,
      submission: submission
    } do
      {:ok, _} =
        Tasks.update_task(Scope.for_user(user_of(task)), task, %{solution_release_mode: "manual"})

      lv = open_review(conn, task, student)

      html =
        lv |> element("button[phx-click='release_solution']") |> render_click()

      assert html =~ "Freigegeben am"
      refute has_element?(lv, "button[phx-click='release_solution']")

      assert %DateTime{} =
               Tasky.Repo.reload!(submission).solution_released_at
    end

    test "meldet eine automatische Freigabe statt eines Knopfes", %{
      conn: conn,
      task: task,
      student: student
    } do
      {:ok, _} =
        Tasks.update_task(Scope.for_user(user_of(task)), task, %{
          solution_release_mode: "on_complete"
        })

      lv = open_review(conn, task, student)

      assert render(lv) =~ "Automatisch freigegeben"
      refute has_element?(lv, "button[phx-click='release_solution']")
    end
  end

  describe "Bulk-Freigabe" do
    test "zeigt im Modus never keine Bulk-Aktionen", %{conn: conn, task: task} do
      {:ok, _lv, html} = live(conn, ~p"/progress/#{task.id}")

      assert html =~ "Wird Lernenden nicht angezeigt"
      assert html =~ "Modus ändern"
      refute html =~ "phx-click=\"release_selected\""
      refute html =~ "phx-click=\"open_release_all_confirm\""
    end

    test "gibt nach Bestätigung für alle frei", %{
      conn: conn,
      task: task,
      submission: submission
    } do
      {:ok, _} =
        Tasks.update_task(Scope.for_user(user_of(task)), task, %{solution_release_mode: "manual"})

      {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}")

      lv |> element("button[phx-click='open_release_all_confirm']") |> render_click()
      assert has_element?(lv, "#release-all-modal")

      html = lv |> element("#confirm-release-all") |> render_click()

      assert html =~ "freigegeben"
      assert %DateTime{} = Tasky.Repo.reload!(submission).solution_released_at
    end

    test "gibt nur die Auswahl frei", %{
      conn: conn,
      task: task,
      student: student,
      submission: submission
    } do
      teacher_scope = Scope.for_user(user_of(task))
      {:ok, task} = Tasks.update_task(teacher_scope, task, %{solution_release_mode: "manual"})

      other = user_fixture(%{role: "student"})
      {:ok, _} = Courses.enroll_student(task.course_id, other.id)
      {:ok, other_submission} = Tasks.get_or_create_submission(Scope.for_user(other), task.id)

      {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}")

      # Nichts ausgewählt → Knopf ist gesperrt.
      assert lv
             |> element("button[phx-click='release_selected']")
             |> render() =~ "disabled"

      lv
      |> element("input[phx-value-submission-id='#{submission.id}']")
      |> render_click()

      lv |> element("button[phx-click='release_selected']") |> render_click()

      assert %DateTime{} = Tasky.Repo.reload!(submission).solution_released_at
      refute Tasky.Repo.reload!(other_submission).solution_released_at

      _ = student
    end

    test "ist idempotent — der erste Zeitstempel bleibt", %{
      conn: conn,
      task: task,
      submission: submission
    } do
      teacher_scope = Scope.for_user(user_of(task))
      {:ok, task} = Tasks.update_task(teacher_scope, task, %{solution_release_mode: "manual"})
      {:ok, _} = Tasks.release_solution(teacher_scope, task, submission.id)
      first = Tasky.Repo.reload!(submission).solution_released_at

      {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}")
      lv |> element("button[phx-click='open_release_all_confirm']") |> render_click()
      lv |> element("#confirm-release-all") |> render_click()

      assert Tasky.Repo.reload!(submission).solution_released_at == first
    end

    test "zeigt den Freigabestatus in der Tabelle", %{conn: conn, task: task} do
      teacher_scope = Scope.for_user(user_of(task))
      {:ok, task} = Tasks.update_task(teacher_scope, task, %{solution_release_mode: "manual"})

      {:ok, lv, html} = live(conn, ~p"/progress/#{task.id}")
      assert html =~ "Nicht freigegeben"

      lv |> element("button[phx-click='open_release_all_confirm']") |> render_click()
      html = lv |> element("#confirm-release-all") |> render_click()

      assert html =~ "Freigegeben"
    end
  end

  describe "Korrektur-Seite" do
    test "ist aus dem Review-Modal erreichbar", %{
      conn: conn,
      task: task,
      student: student,
      submission: submission
    } do
      lv = open_review(conn, task, student)

      assert has_element?(
               lv,
               "a[href='/progress/#{task.id}/correction/#{submission.id}']"
             )
    end

    test "zeigt die Antworten der/des Lernenden im Korrektur-Editor", %{
      conn: conn,
      task: task,
      submission: submission
    } do
      {:ok, _lv, html} = live(conn, ~p"/progress/#{task.id}/correction/#{submission.id}")

      assert html =~ "task-correction-editor-#{submission.id}"
      assert html =~ "Mia Muster"
      assert html =~ "Noch nicht freigegeben" or html =~ "ausgeblendet"
    end

    test "gibt von der Korrektur-Seite aus frei", %{
      conn: conn,
      task: task,
      submission: submission
    } do
      {:ok, _} =
        Tasks.update_task(Scope.for_user(user_of(task)), task, %{solution_release_mode: "manual"})

      {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}/correction/#{submission.id}")

      html = lv |> element("button[phx-click='release_solution']") |> render_click()

      assert html =~ "Freigegeben am"
      assert %DateTime{} = Tasky.Repo.reload!(submission).solution_released_at
    end

    test "leitet bei unbekannter Abgabe zurück", %{conn: conn, task: task} do
      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, ~p"/progress/#{task.id}/correction/999999")

      assert path == "/progress/#{task.id}"
    end

    test "eine fremde Lehrperson kommt nicht hinein", %{
      conn: conn,
      task: task,
      submission: submission
    } do
      other = user_fixture(%{role: "teacher"})
      conn = conn |> Phoenix.ConnTest.recycle() |> log_in_user(other)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/progress/#{task.id}/correction/#{submission.id}")
      end
    end
  end

  defp user_of(task), do: Tasky.Repo.get!(Tasky.Accounts.User, task.user_id)

  test "a foreign teacher gets no access to the unit's progress", %{
    conn: conn,
    task: task
  } do
    other_teacher = user_fixture(%{role: "teacher"})
    conn = conn |> Phoenix.ConnTest.recycle() |> log_in_user(other_teacher)

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/progress/#{task.id}") end
  end

  describe "navigate_submission robustness" do
    test "navigating before a submission is selected does not crash", %{conn: conn, task: task} do
      {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}")

      # `Enum.find_index/2` returns nil here, and `nil - 1` raised.
      assert render_click(lv, "navigate_submission", %{"direction" => "prev"})
      assert render_click(lv, "navigate_submission", %{"direction" => "next"})
      assert render(lv) =~ "Testaufgabe"
    end

    test "selecting a student without a submission does not crash the view", %{
      conn: conn,
      task: task,
      student: student
    } do
      # `show_submission` accepts any enrolled student, but the navigation list
      # only holds those *with* a submission — so the selected id can be absent
      # from it, and both the handler and `render/1` did `index + 1` on nil.
      other = user_fixture(%{role: "student", firstname: "Ohne", lastname: "Abgabe"})
      course_id = Tasky.Repo.get!(Tasky.Tasks.Task, task.id).course_id
      {:ok, _} = Courses.enroll_student(course_id, other.id)

      {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}")

      assert render_click(lv, "show_submission", %{"student-id" => to_string(other.id)})
      assert render_click(lv, "navigate_submission", %{"direction" => "next"})
      assert render(lv) =~ student.lastname
    end
  end
end
