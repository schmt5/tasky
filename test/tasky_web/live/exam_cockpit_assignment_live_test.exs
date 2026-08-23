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

  # The assignment UI lives behind the "Lernende zuweisen" header button,
  # so every assignment test has to open the dialog first.
  defp open_assign_dialog(view) do
    view |> element("#add-participants-btn") |> render_click()
  end

  describe "anonymous mode" do
    test "still shows the enrollment link and no assignment card", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("anonymous")
      {:ok, _view, html} = open_cockpit(conn, teacher, exam)

      assert html =~ "Einschreibelink"
      assert html =~ exam.enrollment_token
      refute html =~ "add-participants-btn"
      refute html =~ "Lernende zuweisen"
    end

    test "keeps the participant resume link in the row menu", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("anonymous")
      submission = exam_submission_fixture(exam)
      {:ok, _view, html} = open_cockpit(conn, teacher, exam)

      assert html =~ "Teilnahmelink kopieren"
      assert html =~ submission.exam_token
    end
  end

  describe "assigned mode" do
    test "offers the assignment dialog instead of the enrollment link", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("assigned")
      {:ok, view, html} = open_cockpit(conn, teacher, exam)

      assert html =~ "Lernende zuweisen"
      refute html =~ "Einschreibelink"
      assert html =~ "Noch keine Teilnehmenden zugewiesen."

      # The assignment card itself only appears once the dialog is opened.
      refute html =~ "Lernende auswählen"
      assert open_assign_dialog(view) =~ "Lernende auswählen"
    end

    test "closes the assignment dialog again", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("assigned")
      {:ok, view, _html} = open_cockpit(conn, teacher, exam)

      assert open_assign_dialog(view) =~ "assign-participants-modal"

      html = view |> element("#close-assign-modal-btn") |> render_click()

      refute html =~ "assign-participants-modal"
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
      refute html =~ "Teilnahmelink kopieren"
      assert html =~ "Zuweisung entfernen"
    end

    test "assigns a single student and updates the roster", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("assigned")
      student = user_fixture(%{role: "student", firstname: "Lena", lastname: "Meier"})
      {:ok, view, _html} = open_cockpit(conn, teacher, exam)

      assert open_assign_dialog(view) =~ "Lena"

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
      open_assign_dialog(view)

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
      {:ok, view, _html} = open_cockpit(conn, teacher, exam)
      html = open_assign_dialog(view)

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

      view |> element("#unassign-#{submission.id}") |> render_click()

      assert Exams.list_exam_submissions(exam) == []
      assert open_assign_dialog(view) =~ "assign-student-#{student.id}"
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

      assert html =~ "Lernende zuweisen"
      open_assign_dialog(view)
      view |> element("#assign-student-#{student.id}") |> render_click()

      assert length(Exams.list_exam_submissions(exam)) == 1
    end

    test "the assignment button disappears once the exam is finished", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam("assigned", "finished")
      {:ok, _view, html} = open_cockpit(conn, teacher, exam)

      refute html =~ "add-participants-btn"
      refute html =~ "Lernende zuweisen"
      assert html =~ "Prüfung beendet"
    end
  end

  # The participant label is computed inside a LiveView stream item, so it only
  # changes when the stream is re-streamed. Nothing did that on a status change,
  # which left a running exam reading "Im Warteraum" in the cockpit while the
  # participants were already working.
  describe "participant status label" do
    defp track_present(exam, submission) do
      {:ok, _ref} =
        TaskyWeb.Presence.track(
          self(),
          "exam_waiting:#{exam.id}",
          submission.exam_token,
          %{firstname: submission.firstname, lastname: submission.lastname, in_seb: false}
        )

      :ok
    end

    defp assign_present_student(scope, exam) do
      student = user_fixture(%{role: "student"})
      {:ok, submission} = Exams.assign_student(scope, exam, student.id)
      :ok = track_present(exam, submission)
      submission
    end

    test "says \"Im Warteraum\" for a present participant before the start", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = setup_exam("assigned")
      assign_present_student(scope, exam)

      {:ok, _view, html} = open_cockpit(conn, teacher, exam)

      assert html =~ "Im Warteraum"
      assert html =~ "1 online"
    end

    test "switches to \"In Bearbeitung\" when the exam is started elsewhere", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = setup_exam("assigned")
      assign_present_student(scope, exam)

      {:ok, view, html} = open_cockpit(conn, teacher, exam)
      assert html =~ "Im Warteraum"

      # Started from outside this LiveView — the same path a second teacher tab
      # or ExamLive.Show takes. The cockpit has to pick it up over PubSub.
      {:ok, _exam} = Exams.update_exam_status(scope, exam, "running")

      html = render(view)
      assert html =~ "In Bearbeitung"
      refute html =~ "Im Warteraum"
    end

    test "switches when the cockpit itself starts the exam", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = setup_exam("assigned")
      assign_present_student(scope, exam)

      {:ok, view, _html} = open_cockpit(conn, teacher, exam)

      view |> element("button[phx-value-action=start_exam]") |> render_click()

      view
      |> element("#start-exam-modal button[phx-click=confirm_action]")
      |> render_click()

      # The label arrives with the broadcast the event handler triggered, which
      # lands in the mailbox after the event itself — so it is not in the click's
      # own diff.
      html = render(view)

      assert html =~ "In Bearbeitung"
      refute html =~ "Im Warteraum"
    end

    test "drops the assignment button when the exam is finished elsewhere", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = setup_exam("assigned", "running")
      assign_present_student(scope, exam)

      {:ok, view, html} = open_cockpit(conn, teacher, exam)
      assert html =~ "add-participants-btn"

      {:ok, _exam} = Exams.update_exam_status(scope, exam, "finished")

      html = render(view)
      refute html =~ "add-participants-btn"
      refute html =~ "In Bearbeitung"
      assert html =~ "Prüfung beendet"
    end
  end
end
