defmodule TaskyWeb.ExamGradingConfigLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp finished_exam do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    exam = exam_fixture(scope: scope, status: "running")
    {:ok, submission} = Exams.create_exam_submission(exam, valid_enrollment_attrs())
    {:ok, submission} = Exams.submit_exam_submission(submission)
    {:ok, exam} = Exams.update_exam_status(scope, exam, "finished")

    %{teacher: teacher, scope: scope, exam: exam, submission: submission}
  end

  describe "the gate into the grading table" do
    test "an exam without a mark step is sent to the configuration first", %{conn: conn} do
      %{teacher: teacher, exam: exam} = finished_exam()

      assert {:error, {:live_redirect, %{to: to}}} =
               conn
               |> log_in_user(teacher)
               |> live(~p"/exams/#{exam}/correction/grading")

      assert to == "/exams/#{exam.id}/correction/grading/config"
    end

    test "the gate also catches a bookmarked link on the dead render", %{conn: conn} do
      # `live/2` alone does not prove this: a pasted URL renders statically
      # first, and the redirect has to happen there too.
      %{teacher: teacher, exam: exam} = finished_exam()

      conn =
        conn
        |> log_in_user(teacher)
        |> get(~p"/exams/#{exam}/correction/grading")

      assert redirected_to(conn) == "/exams/#{exam.id}/correction/grading/config"
    end

    test "a configured exam opens the table directly", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = finished_exam()
      {:ok, exam, 0} = Exams.set_mark_step(scope, exam, "0.25")

      {:ok, _view, html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading")

      assert html =~ "Konfigurieren"
      assert html =~ "grading-config-btn"
      # The max points live on the configuration page only.
      refute html =~ "Maximalpunkte für Benotung"
      refute html =~ "er-Schritte"
    end
  end

  describe "the configuration page" do
    test "it is the way into the grading before a step is chosen", %{conn: conn} do
      %{teacher: teacher, exam: exam} = finished_exam()

      {:ok, _view, html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading/config")

      assert html =~ "Notenschritte"
      assert html =~ "Viertelnoten"
      assert html =~ "Zehntelnoten"
      assert html =~ "Benotung starten"
      assert html =~ "Maximalpunkte für Benotung"
      refute html =~ "save-grading-config-btn"
    end

    test "it is the configuration once a step is chosen", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = finished_exam()
      {:ok, exam, 0} = Exams.set_mark_step(scope, exam, "0.1")

      {:ok, _view, html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading/config")

      assert html =~ "Konfiguration"
      assert html =~ "save-grading-config-btn"
      refute html =~ "Benotung starten"
    end

    test "choosing tenths starts the grading on the 0.1 grid", %{conn: conn} do
      %{teacher: teacher, exam: exam} = finished_exam()

      {:ok, view, _html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading/config")

      view |> element(~s|input[name="mark_step"][value="0.1"]|) |> render_click()

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("#start-grading-btn") |> render_click()

      assert to == "/exams/#{exam.id}/correction/grading"
      assert Tasky.Repo.reload!(exam).mark_step == "0.1"
    end

    test "an unknown step from a tampered client is ignored", %{conn: conn} do
      %{teacher: teacher, exam: exam} = finished_exam()

      {:ok, view, _html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading/config")

      render_click(view, "select_step", %{"step" => "0.2"})
      render_click(view, "save", %{})

      # The pre-selection survives; nothing off-grid reaches the column.
      assert Tasky.Repo.reload!(exam).mark_step == "0.25"
    end
  end

  describe "the grading table follows the exam's step" do
    test "the stepper, its copy and the input are on the 0.1 grid", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = finished_exam()
      {:ok, exam, 0} = Exams.set_mark_step(scope, exam, "0.1")

      {:ok, _view, html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading")

      assert html =~ "Note um 0.1 senken"
      assert html =~ "Note um 0.1 erhöhen"
      assert html =~ ~s|step="0.1"|
      refute html =~ "Note um 0.25 senken"
    end

    test "the plus button moves a mark by a tenth", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam, submission: submission} = finished_exam()
      {:ok, exam, 0} = Exams.set_mark_step(scope, exam, "0.1")
      {:ok, submission} = Exams.set_submission_mark(scope, submission, 4.7)

      {:ok, view, _html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading")

      render_click(view, "adjust_mark", %{
        "submission-id" => to_string(submission.id),
        "direction" => "up"
      })

      assert Tasky.Repo.reload!(submission).mark == 4.8
    end

    test "a typed mark is snapped to the exam's grid", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam, submission: submission} = finished_exam()
      {:ok, exam, 0} = Exams.set_mark_step(scope, exam, "0.25")

      {:ok, view, _html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading")

      render_click(view, "set_mark", %{
        "submission_id" => to_string(submission.id),
        "mark" => "4.7"
      })

      assert Tasky.Repo.reload!(submission).mark == 4.75
    end
  end
end
