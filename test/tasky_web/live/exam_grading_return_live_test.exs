defmodule TaskyWeb.ExamGradingReturnLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp graded_exam(mode) do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    exam = exam_fixture(scope: scope, status: "running", participation_mode: mode)

    submission =
      case mode do
        "assigned" ->
          student = user_fixture(%{role: "student"})
          {:ok, submission} = Exams.assign_student(scope, exam, student.id)
          submission

        "anonymous" ->
          exam_submission_fixture(exam)
      end

    {:ok, submission} = Exams.submit_exam_submission(submission)
    {:ok, exam} = Exams.update_exam_status(scope, exam, "finished")

    # The grading table sends an exam without a mark step to the configuration
    # page first. `exam_fixture/1` deliberately leaves it nil — that is the
    # honest state of a fresh exam — so these tests pick the step themselves.
    {:ok, exam, 0} = Exams.set_mark_step(scope, exam, "0.25")

    %{teacher: teacher, scope: scope, exam: exam, submission: submission}
  end

  defp open_grading(conn, teacher, exam) do
    conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading")
  end

  test "the return button appears only in assigned mode", %{conn: conn} do
    %{teacher: teacher, exam: exam} = graded_exam("anonymous")
    {:ok, _view, html} = open_grading(conn, teacher, exam)

    refute html =~ "Prüfung zurückgeben"
    assert html =~ "Exportieren"
  end

  test "returning stores the chosen options on the exam", %{conn: conn} do
    %{teacher: teacher, scope: scope, exam: exam} = graded_exam("assigned")
    {:ok, view, html} = open_grading(conn, teacher, exam)

    assert html =~ "Prüfung zurückgeben"

    html = view |> element("#open-return-modal-btn") |> render_click()
    assert html =~ "Musterlösung anzeigen"

    # Default: content + correction + points, no sample solution. Turn the
    # sample solution on to prove the toggles are wired to the return options.
    view
    |> element(~s(#return-modal input[phx-value-option="show_sample_solution"]))
    |> render_click()

    view |> element("#confirm-return-btn") |> render_click()

    reloaded = Exams.get_exam!(scope, exam.id)
    assert Exams.returned?(reloaded)
    assert reloaded.return_show_content
    assert reloaded.return_show_correction
    assert reloaded.return_show_points_and_mark
    assert reloaded.return_show_sample_solution
  end

  test "show_correction is cleared when show_content is turned off", %{conn: conn} do
    %{teacher: teacher, scope: scope, exam: exam} = graded_exam("assigned")
    {:ok, view, _html} = open_grading(conn, teacher, exam)

    view |> element("#open-return-modal-btn") |> render_click()

    html =
      view
      |> element(~s(#return-modal input[phx-value-option="show_content"]))
      |> render_click()

    # The correction box is now disabled, and turning it on is a no-op.
    assert html =~ "cursor-not-allowed"

    view |> element("#confirm-return-btn") |> render_click()

    reloaded = Exams.get_exam!(scope, exam.id)
    refute reloaded.return_show_content
    refute reloaded.return_show_correction
  end

  test "a returned exam shows the badge and can be withdrawn", %{conn: conn} do
    %{teacher: teacher, scope: scope, exam: exam} = graded_exam("assigned")
    {:ok, exam} = Exams.return_exam(scope, exam, %{show_content: true, show_correction: true})

    {:ok, view, html} = open_grading(conn, teacher, exam)

    assert html =~ "Zurückgegeben am"
    refute html =~ "Prüfung zurückgeben"

    html = view |> element("#withdraw-return-btn") |> render_click()

    assert html =~ "Prüfung zurückgeben"
    refute Exams.returned?(Exams.get_exam!(scope, exam.id))
  end

  test "the modal pre-fills with what the exam was returned with", %{conn: conn} do
    %{teacher: teacher, scope: scope, exam: exam} = graded_exam("assigned")

    {:ok, exam} =
      Exams.return_exam(scope, exam, %{show_content: false, show_points_and_mark: true})

    {:ok, view, _html} = open_grading(conn, teacher, exam)
    view |> element("#withdraw-return-btn") |> render_click()
    html = view |> element("#open-return-modal-btn") |> render_click()

    # show_content was off when it was returned, so the correction box is
    # disabled again rather than silently re-enabled.
    assert html =~ "cursor-not-allowed"
  end

  # The return action must not disturb the export control it sits next to. The
  # PDF service is absent in test, so the export button renders disabled — which
  # is exactly the state to assert here.
  test "the export control still renders next to the return button", %{conn: conn} do
    %{teacher: teacher, exam: exam} = graded_exam("assigned")
    {:ok, _view, html} = open_grading(conn, teacher, exam)

    assert html =~ "Exportieren"
    assert html =~ "Prüfung zurückgeben"
    refute Tasky.PDF.Gotenberg.enabled?()
    assert html =~ "PDF-Dienst nicht verfügbar"
  end

  test "the export modal uses the same option list as the return modal", %{conn: conn} do
    %{teacher: teacher, exam: exam} = graded_exam("assigned")
    {:ok, view, _html} = open_grading(conn, teacher, exam)

    return_html = view |> element("#open-return-modal-btn") |> render_click()

    for option <- TaskyWeb.ExamComponents.submission_view_options(exam) do
      assert return_html =~ option.label
      assert return_html =~ ~s(phx-value-option="#{option.key}")
    end
  end

  test "a free-document exam is not offered the sample-solution option" do
    exam = %Tasky.Exams.Exam{answer_mode: "free_document"}

    keys = Enum.map(TaskyWeb.ExamComponents.submission_view_options(exam), & &1.key)

    refute :show_sample_solution in keys
    assert :show_correction in keys
  end
end
