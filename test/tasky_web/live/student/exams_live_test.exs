defmodule TaskyWeb.Student.ExamsLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp assigned_exam(status \\ "open") do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    exam = exam_fixture(scope: scope, status: status, participation_mode: "assigned")
    %{teacher: teacher, scope: scope, exam: exam}
  end

  defp finish(scope, exam) do
    {:ok, exam} = Exams.update_exam_status(scope, exam, "finished")
    exam
  end

  describe "the exam list" do
    test "lists an assigned exam with its join link", %{conn: conn} do
      %{scope: scope, exam: exam} = assigned_exam()
      student = user_fixture(%{role: "student"})
      {:ok, submission} = Exams.assign_student(scope, exam, student.id)

      {:ok, _view, html} = conn |> log_in_user(student) |> live(~p"/student/exams")

      assert html =~ exam.name
      assert html =~ "Zugewiesen"
      assert html =~ "Zur Prüfung"
      assert html =~ "/guest/exam/#{submission.exam_token}"
    end

    test "shows only the student's own assignment", %{conn: conn} do
      %{scope: scope, exam: exam} = assigned_exam()
      mine = user_fixture(%{role: "student"})
      theirs = user_fixture(%{role: "student"})
      {:ok, own} = Exams.assign_student(scope, exam, mine.id)
      {:ok, other} = Exams.assign_student(scope, exam, theirs.id)

      {:ok, _view, html} = conn |> log_in_user(mine) |> live(~p"/student/exams")

      assert html =~ own.exam_token
      refute html =~ other.exam_token
    end

    test "a running exam offers to continue", %{conn: conn} do
      %{scope: scope, exam: exam} = assigned_exam("running")
      student = user_fixture(%{role: "student"})
      {:ok, _} = Exams.assign_student(scope, exam, student.id)

      {:ok, _view, html} = conn |> log_in_user(student) |> live(~p"/student/exams")

      assert html =~ "Läuft"
      assert html =~ "Prüfung fortsetzen"
    end

    test "a submitted exam offers no link until it is returned", %{conn: conn} do
      %{scope: scope, exam: exam} = assigned_exam("running")
      student = user_fixture(%{role: "student"})
      {:ok, submission} = Exams.assign_student(scope, exam, student.id)
      {:ok, _} = Exams.submit_exam_submission(submission)

      {:ok, _view, html} = conn |> log_in_user(student) |> live(~p"/student/exams")

      assert html =~ "Abgegeben"
      refute html =~ "/guest/exam/"
      refute html =~ "Prüfung ansehen"
    end

    test "a returned exam links to the detail view and shows the mark", %{conn: conn} do
      %{scope: scope, exam: exam} = assigned_exam("running")
      student = user_fixture(%{role: "student"})
      {:ok, submission} = Exams.assign_student(scope, exam, student.id)
      {:ok, submission} = Exams.submit_exam_submission(submission)
      {:ok, _} = Exams.set_submission_mark(scope, submission, 5.25)
      exam = finish(scope, exam)
      {:ok, _} = Exams.return_exam(scope, exam, %{show_points_and_mark: true})

      {:ok, _view, html} = conn |> log_in_user(student) |> live(~p"/student/exams")

      assert html =~ "Zurückgegeben"
      assert html =~ "Prüfung ansehen"
      assert html =~ "5.25"
    end

    test "anonymous exams never appear", %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      scope = user_scope_fixture(teacher)
      exam = exam_fixture(scope: scope, status: "open", participation_mode: "anonymous")
      _submission = exam_submission_fixture(exam)
      student = user_fixture(%{role: "student"})

      {:ok, _view, html} = conn |> log_in_user(student) |> live(~p"/student/exams")

      refute html =~ exam.name
      assert html =~ "Noch keine Prüfungen"
    end

    test "the list updates live when the teacher starts the exam", %{conn: conn} do
      %{scope: scope, exam: exam} = assigned_exam()
      student = user_fixture(%{role: "student"})
      {:ok, _} = Exams.assign_student(scope, exam, student.id)

      {:ok, view, html} = conn |> log_in_user(student) |> live(~p"/student/exams")
      assert html =~ "Zugewiesen"

      {:ok, _} = Exams.update_exam_status(scope, exam, "running")

      assert render(view) =~ "Läuft"
    end
  end

  describe "the returned exam" do
    setup %{conn: conn} do
      %{scope: scope, exam: exam} = assigned_exam("running")
      student = user_fixture(%{role: "student"})
      {:ok, submission} = Exams.assign_student(scope, exam, student.id)

      {:ok, submission} =
        Exams.update_exam_submission_content(submission, %{
          "type" => "doc",
          "content" => [
            %{
              "type" => "paragraph",
              "content" => [%{"type" => "text", "text" => "Meine Antwort"}]
            }
          ]
        })

      {:ok, submission} = Exams.submit_exam_submission(submission)
      exam = finish(scope, exam)

      %{conn: log_in_user(conn, student), scope: scope, exam: exam, submission: submission}
    end

    test "renders the content the teacher released", %{conn: conn, scope: scope, exam: exam} do
      {:ok, _} = Exams.return_exam(scope, exam, %{show_content: true})

      {:ok, _view, html} = live(conn, ~p"/student/exams/#{exam.id}")

      assert html =~ "Meine Antwort"
      refute html =~ "Musterlösung"
    end

    test "adds the sample solution when released", %{conn: conn, scope: scope, exam: exam} do
      {:ok, _} =
        Exams.return_exam(scope, exam, %{show_content: true, show_sample_solution: true})

      {:ok, _view, html} = live(conn, ~p"/student/exams/#{exam.id}")

      assert html =~ "Musterlösung"
    end

    test "hides points and mark when they were not released", %{
      conn: conn,
      scope: scope,
      exam: exam
    } do
      {:ok, _} =
        Exams.return_exam(scope, exam, %{show_content: true, show_points_and_mark: false})

      {:ok, _view, html} = live(conn, ~p"/student/exams/#{exam.id}")

      refute html =~ "Note"
    end

    test "an exam that was not returned is not reachable", %{conn: conn, exam: exam} do
      assert {:error, {:live_redirect, %{to: "/student/exams"}}} =
               live(conn, ~p"/student/exams/#{exam.id}")
    end

    test "withdrawing the return closes the page again", %{
      conn: conn,
      scope: scope,
      exam: exam
    } do
      {:ok, exam} = Exams.return_exam(scope, exam, %{show_content: true})
      assert {:ok, _view, _html} = live(conn, ~p"/student/exams/#{exam.id}")

      {:ok, exam} = Exams.withdraw_exam_return(scope, exam)

      assert {:error, {:live_redirect, %{to: "/student/exams"}}} =
               live(conn, ~p"/student/exams/#{exam.id}")
    end

    test "a foreign exam is not reachable", %{conn: conn} do
      %{scope: other_scope, exam: other_exam} = assigned_exam("running")
      other_exam = finish(other_scope, other_exam)
      {:ok, other_exam} = Exams.return_exam(other_scope, other_exam, %{show_content: true})

      assert {:error, {:live_redirect, %{to: "/student/exams"}}} =
               live(conn, ~p"/student/exams/#{other_exam.id}")
    end
  end
end
