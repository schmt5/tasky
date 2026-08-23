defmodule TaskyWeb.GuestExamLiveTest do
  use TaskyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp running_exam_with_submission do
    exam = exam_fixture(status: "running", attrs: %{name: "Live Prüfung"})
    submission = exam_submission_fixture(exam)

    %{exam: exam, submission: submission}
  end

  defp open_exam(conn, submission) do
    live(conn, ~p"/guest/exam/#{submission.exam_token}")
  end

  describe "enrollment" do
    test "enroll page is reachable while the exam is running", %{conn: conn} do
      %{exam: exam} = running_exam_with_submission()

      {:ok, _view, html} = live(conn, ~p"/guest/enroll/#{exam.enrollment_token}")
      assert html =~ "Melde dich für die Prüfung an"
    end

    test "enrolling during a running exam lands directly in the editor", %{conn: conn} do
      %{exam: exam} = running_exam_with_submission()

      {:ok, view, _html} = live(conn, ~p"/guest/enroll/#{exam.enrollment_token}")

      assert {:error, {:live_redirect, %{to: "/guest/exam/" <> token}}} =
               view
               |> form("#enrollment-form",
                 enrollment: %{firstname: "Lena", lastname: "Späti", email: "lena@example.com"}
               )
               |> render_submit()

      {:ok, _view, html} = live(conn, ~p"/guest/exam/#{token}")
      assert html =~ "Abgeben"
    end

    test "the enroll page is dead for an assigned-mode exam", %{conn: conn} do
      anonymous = exam_fixture(status: "open", participation_mode: "anonymous")
      token = anonymous.enrollment_token

      {:ok, _} =
        anonymous
        |> Ecto.Changeset.change(%{participation_mode: "assigned"})
        |> Tasky.Repo.update()

      {:ok, _view, html} = live(conn, ~p"/guest/enroll/#{token}")
      assert html =~ "Einschreibelink ungültig"
    end
  end

  describe "assigned participants" do
    import Tasky.AccountsFixtures

    setup do
      teacher = user_fixture(%{role: "teacher"})
      scope = user_scope_fixture(teacher)
      exam = exam_fixture(scope: scope, status: "running", participation_mode: "assigned")
      student = user_fixture(%{role: "student"})
      {:ok, submission} = Exams.assign_student(scope, exam, student.id)

      %{exam: exam, student: student, submission: submission}
    end

    test "the owner can open their own submission", %{
      conn: conn,
      student: student,
      submission: submission
    } do
      {:ok, _view, html} = conn |> log_in_user(student) |> open_exam(submission)
      assert html =~ "Abgeben"
    end

    # The token has to keep working without a session (SEB), but a logged-in
    # classmate pasting someone else's token is refused.
    test "another logged-in student cannot open it", %{conn: conn, submission: submission} do
      classmate = user_fixture(%{role: "student"})

      {:ok, _view, html} = conn |> log_in_user(classmate) |> open_exam(submission)
      refute html =~ "Abgeben"
      assert html =~ "ungültig"
    end

    test "a cookie-less request still works (this is the SEB path)", %{
      conn: conn,
      submission: submission
    } do
      {:ok, _view, html} = open_exam(conn, submission)
      assert html =~ "Abgeben"
    end

    test "after submitting, a logged-in participant is offered the way home", %{
      conn: conn,
      student: student,
      submission: submission
    } do
      {:ok, view, _html} = conn |> log_in_user(student) |> open_exam(submission)

      render_click(view, "show_submit_modal")
      render_hook(view, "submit_check_result", %{"ok" => true})
      render_click(view, "confirm_submit_exam")

      assert has_element?(view, "#back-home-btn[href=\"/\"]")
    end
  end

  describe "submit flow" do
    test "opening the modal starts in checking state with submit disabled", %{conn: conn} do
      %{submission: submission} = running_exam_with_submission()
      {:ok, view, _html} = open_exam(conn, submission)

      html = render_click(view, "show_submit_modal")

      assert html =~ "submit-check-pending"
      assert html =~ "Deine Antworten werden gespeichert"
      assert has_element?(view, "#confirm-submit-btn[disabled]")
    end

    test "successful flush check enables the submit button", %{conn: conn} do
      %{submission: submission} = running_exam_with_submission()
      {:ok, view, _html} = open_exam(conn, submission)

      render_click(view, "show_submit_modal")
      html = render_hook(view, "submit_check_result", %{"ok" => true})

      refute html =~ "submit-check-pending"
      refute has_element?(view, "#confirm-submit-btn[disabled]")
      assert html =~ "Jetzt abgeben"
    end

    test "failed flush check shows error, disables submit and offers retry", %{conn: conn} do
      %{submission: submission} = running_exam_with_submission()
      {:ok, view, _html} = open_exam(conn, submission)

      render_click(view, "show_submit_modal")
      html = render_hook(view, "submit_check_result", %{"ok" => false})

      assert html =~ "submit-check-error"
      assert html =~ "konnten nicht gespeichert werden"
      assert has_element?(view, "#confirm-submit-btn[disabled]")
      assert html =~ "Erneut versuchen"

      # Retry flips back to checking
      html = render_click(view, "retry_submit_check")
      assert html =~ "submit-check-pending"
    end

    test "confirm_submit_exam is ignored while the flush check has not passed", %{conn: conn} do
      %{submission: submission} = running_exam_with_submission()
      {:ok, view, _html} = open_exam(conn, submission)

      render_click(view, "show_submit_modal")
      render_hook(view, "submit_check_result", %{"ok" => false})
      render_click(view, "confirm_submit_exam")

      refute Exams.get_exam_submission_by_token!(submission.exam_token).submitted
    end

    test "confirm_submit_exam submits after a successful flush check", %{conn: conn} do
      %{submission: submission} = running_exam_with_submission()
      {:ok, view, _html} = open_exam(conn, submission)

      render_click(view, "show_submit_modal")
      render_hook(view, "submit_check_result", %{"ok" => true})
      html = render_click(view, "confirm_submit_exam")

      assert Exams.get_exam_submission_by_token!(submission.exam_token).submitted
      assert html =~ "abgegeben.</em>"
    end

    # The exact submission time was noise on a screen whose job is to say
    # "you are done" — it lives on in the teacher's cockpit.
    test "the submitted screen names no submission time", %{conn: conn} do
      %{submission: submission} = running_exam_with_submission()
      {:ok, view, _html} = open_exam(conn, submission)

      render_click(view, "show_submit_modal")
      render_hook(view, "submit_check_result", %{"ok" => true})
      html = render_click(view, "confirm_submit_exam")

      refute html =~ "Abgegeben am"
    end

    # An anonymous guest has no home in this app to return to.
    test "an anonymous participant gets no home button", %{conn: conn} do
      %{submission: submission} = running_exam_with_submission()
      {:ok, view, _html} = open_exam(conn, submission)

      render_click(view, "show_submit_modal")
      render_hook(view, "submit_check_result", %{"ok" => true})
      render_click(view, "confirm_submit_exam")

      refute has_element?(view, "#back-home-btn")
    end
  end

  describe "malformed upload params" do
    setup %{conn: conn} do
      %{submission: submission} = running_exam_with_submission()
      {:ok, view, _html} = open_exam(conn, submission)
      %{view: view}
    end

    test "an unknown field-id on cancel does not take the LiveView down", %{view: view} do
      # `:"answer_field_#{field_id}"` minted an atom per distinct value — a
      # guest holding only an exam token could walk the VM to its atom limit —
      # and `cancel_upload/3` raises for a name that was never allowed.
      before = :erlang.system_info(:atom_count)

      for id <- ["not-a-number", "999999", "<script>", ""] do
        assert render_click(view, "cancel_answer_upload", %{"ref" => "0", "field-id" => id})
      end

      assert :erlang.system_info(:atom_count) == before
      assert render(view) =~ "Live Prüfung"
    end

    test "an unknown field-id on delete does not take the LiveView down", %{view: view} do
      # A non-numeric id reached an integer column and raised Ecto.Query.CastError.
      assert render_click(view, "delete_answer_file", %{"field-id" => "not-a-number"})
      assert render(view) =~ "Live Prüfung"
    end
  end
end
