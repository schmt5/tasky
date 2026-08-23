defmodule TaskyWeb.ExamCockpitAssignmentLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ClassesFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp setup_exam(mode, status \\ "open") do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    exam = exam_fixture(scope: scope, status: status, participation_mode: mode)
    %{teacher: teacher, scope: scope, exam: exam}
  end

  defp open_cockpit(conn, teacher, exam) do
    conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/cockpit")
  end

  describe "anonymous mode" do
    test "still shows the enrollment link and no assignment card", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("anonymous")
      {:ok, _view, html} = open_cockpit(conn, teacher, exam)

      assert html =~ "Einschreibelink"
      assert html =~ exam.enrollment_token
      refute html =~ "Teilnehmende zuweisen"
    end

    test "keeps the participant resume link in the row menu", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("anonymous")
      submission = exam_submission_fixture(exam)
      {:ok, _view, html} = open_cockpit(conn, teacher, exam)

      assert html =~ "Teilnehmerlink kopieren"
      assert html =~ submission.exam_token
    end
  end

  describe "assigned mode" do
    test "shows the assignment card instead of the enrollment link", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("assigned")
      {:ok, _view, html} = open_cockpit(conn, teacher, exam)

      assert html =~ "Teilnehmende zuweisen"
      refute html =~ "Einschreibelink"
      assert html =~ "Noch keine Teilnehmenden zugewiesen."
    end

    # The exam_token is a cookie-less bearer credential for one submission.
    # Surfacing it to a teacher in an assigned session defeats the mode.
    test "never puts a participant token or link in the page", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = setup_exam("assigned")
      student = user_fixture(%{role: "student"})
      {:ok, submission} = Exams.assign_student(scope, exam, student.id)

      {:ok, _view, html} = open_cockpit(conn, teacher, exam)

      refute html =~ "/guest/exam/"
      refute html =~ submission.exam_token
      refute html =~ "Teilnehmerlink kopieren"
      assert html =~ "Zuweisung entfernen"
    end

    test "assigns a single student and updates the roster", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("assigned")
      student = user_fixture(%{role: "student", firstname: "Lena", lastname: "Meier"})
      {:ok, view, html} = open_cockpit(conn, teacher, exam)

      assert html =~ "Lena"

      html = view |> element("#assign-student-#{student.id}") |> render_click()

      assert html =~ "Lena Meier"
      assert html =~ "Noch nicht begonnen"
      refute html =~ "assign-student-#{student.id}"
      assert [%{user_id: uid}] = Exams.list_exam_submissions(exam)
      assert uid == student.id
    end

    test "assigns a whole class at once", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("assigned")
      class = class_fixture()
      _a = user_fixture(%{role: "student", class_id: class.id})
      _b = user_fixture(%{role: "student", class_id: class.id})
      {:ok, view, _html} = open_cockpit(conn, teacher, exam)

      html =
        view
        |> form("#assign-class-filter", %{"class_id" => to_string(class.id)})
        |> render_change()

      assert html =~ "Alle zuweisen"

      html = view |> element("#assign-all-btn") |> render_click()

      assert html =~ "2 Teilnehmende zugewiesen."
      assert length(Exams.list_exam_submissions(exam)) == 2
      assert html =~ "Keine weiteren Lernenden zum Zuweisen."
    end

    test "the class filter narrows the candidate list", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("assigned")
      class = class_fixture()
      inside = user_fixture(%{role: "student", class_id: class.id})
      outside = user_fixture(%{role: "student"})
      {:ok, view, html} = open_cockpit(conn, teacher, exam)

      assert html =~ inside.email
      assert html =~ outside.email

      html =
        view
        |> form("#assign-class-filter", %{"class_id" => to_string(class.id)})
        |> render_change()

      assert html =~ inside.email
      refute html =~ outside.email
    end

    test "removes an assignment and puts the student back on the list", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = setup_exam("assigned")
      student = user_fixture(%{role: "student"})
      {:ok, submission} = Exams.assign_student(scope, exam, student.id)
      {:ok, view, _html} = open_cockpit(conn, teacher, exam)

      html = view |> element("#unassign-#{submission.id}") |> render_click()

      assert Exams.list_exam_submissions(exam) == []
      assert html =~ "assign-student-#{student.id}"
    end

    test "offers no removal once the participant has submitted", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = setup_exam("assigned", "running")
      student = user_fixture(%{role: "student"})
      {:ok, submission} = Exams.assign_student(scope, exam, student.id)
      {:ok, _submission} = Exams.submit_exam_submission(submission)

      {:ok, _view, html} = open_cockpit(conn, teacher, exam)

      assert html =~ "Abgegeben"
      refute html =~ "unassign-#{submission.id}"
    end

    test "assignment stays possible while the exam is running", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("assigned", "running")
      student = user_fixture(%{role: "student"})
      {:ok, view, html} = open_cockpit(conn, teacher, exam)

      assert html =~ "Teilnehmende zuweisen"
      view |> element("#assign-student-#{student.id}") |> render_click()

      assert length(Exams.list_exam_submissions(exam)) == 1
    end

    test "the assignment card disappears once the exam is finished", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("assigned", "finished")
      {:ok, _view, html} = open_cockpit(conn, teacher, exam)

      refute html =~ "Teilnehmende zuweisen"
      assert html =~ "Prüfung beendet"
    end
  end
end
