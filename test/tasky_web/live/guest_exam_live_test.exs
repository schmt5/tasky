defmodule TaskyWeb.GuestExamLiveTest do
  use TaskyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures

  alias Tasky.Exams

  defp running_exam_with_submission do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    {:ok, exam} =
      Exams.create_exam(scope, %{
        name: "Live Prüfung",
        content: %{"type" => "doc", "content" => []}
      })

    {:ok, exam} = Exams.open_exam_session(exam)
    {:ok, exam} = Exams.update_exam_status(exam, "running")

    {:ok, submission} =
      Exams.create_exam_submission(exam, %{"firstname" => "Max", "lastname" => "Muster"})

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
               |> form("#enrollment-form", enrollment: %{firstname: "Lena", lastname: "Späti"})
               |> render_submit()

      {:ok, _view, html} = live(conn, ~p"/guest/exam/#{token}")
      assert html =~ "Abgeben"
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
      assert html =~ "Prüfung abgegeben"
    end
  end
end
