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
      # The points for a 6 live on the configuration page only.
      refute html =~ "Punkte für eine 6"
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
      assert html =~ "Punkte für eine 6"
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

  describe "saving the configuration" do
    defp configured_exam(sample_points) do
      %{scope: scope, exam: exam} = ctx = finished_exam()
      {:ok, exam, 0} = Exams.set_mark_step(scope, exam, "0.25")

      exam =
        exam
        |> Ecto.Changeset.change(sample_solution_points: %{"p1" => sample_points})
        |> Tasky.Repo.update!()

      %{ctx | exam: exam}
    end

    defp open_config(conn, teacher, exam) do
      conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading/config")
    end

    test "the total stays visible while the points for a 6 are edited", %{conn: conn} do
      %{teacher: teacher, exam: exam} = configured_exam(10)
      {:ok, view, _html} = open_config(conn, teacher, exam)

      assert has_element?(view, "#grading-max-points-total", "10")
      refute has_element?(view, "#grading-points-for-six-warning")

      render_change(view, "set_points_for_six", %{"points_for_six" => "8"})

      assert has_element?(view, "#grading-max-points-total", "10")
      assert has_element?(view, "#grading-points-for-six-input[value='8']")
    end

    test "more points for a 6 than the total warns", %{conn: conn} do
      %{teacher: teacher, exam: exam} = configured_exam(10)
      {:ok, view, _html} = open_config(conn, teacher, exam)

      render_change(view, "set_points_for_six", %{"points_for_six" => "12"})

      assert has_element?(view, "#grading-points-for-six-warning")
    end

    test "the grading table shows the total and where the 6 starts", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = configured_exam(10)
      {:ok, exam} = Exams.update_grading_max_points(scope, exam, 8)

      {:ok, view, _html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading")

      assert has_element?(view, "#sort-points-hint", "6 ab 8")
    end

    test "points for a 6 are a draft until Speichern", %{conn: conn} do
      %{teacher: teacher, exam: exam} = configured_exam(10)
      {:ok, view, _html} = open_config(conn, teacher, exam)

      assert has_element?(view, "#save-grading-config-btn[disabled]")

      render_change(view, "set_points_for_six", %{"points_for_six" => "12"})

      assert Tasky.Repo.reload!(exam).grading_max_points == nil
      refute has_element?(view, "#save-grading-config-btn[disabled]")
      assert has_element?(view, "#grading-config-unsaved")

      view |> element("#save-grading-config-btn") |> render_click()

      assert Tasky.Repo.reload!(exam).grading_max_points == 12.0
      assert has_element?(view, "#save-grading-config-btn[disabled]")
      refute has_element?(view, "#grading-config-unsaved")
    end

    test "the plus button only changes the draft", %{conn: conn} do
      %{teacher: teacher, exam: exam} = configured_exam(10)
      {:ok, view, _html} = open_config(conn, teacher, exam)

      render_click(view, "adjust_points_for_six", %{"direction" => "up"})

      assert Tasky.Repo.reload!(exam).grading_max_points == nil
      assert has_element?(view, ~s|#grading-points-for-six-input[value="10.25"]|)
    end

    test "reset goes back to the sample solution and saves as no override", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = configured_exam(10)
      {:ok, exam} = Exams.update_grading_max_points(scope, exam, 8)
      {:ok, view, _html} = open_config(conn, teacher, exam)

      view |> element("#reset-points-for-six-btn") |> render_click()

      assert has_element?(view, ~s|#grading-points-for-six-input[value="10"]|)
      refute has_element?(view, "#reset-points-for-six-btn")

      view |> element("#save-grading-config-btn") |> render_click()

      assert Tasky.Repo.reload!(exam).grading_max_points == nil
    end

    test "no reset when the value already follows the sample solution", %{conn: conn} do
      %{teacher: teacher, exam: exam} = configured_exam(10)
      {:ok, view, _html} = open_config(conn, teacher, exam)

      refute has_element?(view, "#reset-points-for-six-btn")
      assert has_element?(view, "#grading-points-for-six-source")
    end

    test "an invalid value blocks saving", %{conn: conn} do
      %{teacher: teacher, exam: exam} = configured_exam(10)
      {:ok, view, _html} = open_config(conn, teacher, exam)

      render_change(view, "set_points_for_six", %{"points_for_six" => "0"})

      assert has_element?(view, "#grading-points-for-six-error")
      assert has_element?(view, "#save-grading-config-btn[disabled]")
    end

    test "step and max points are saved together", %{conn: conn} do
      %{teacher: teacher, exam: exam} = configured_exam(10)
      {:ok, view, _html} = open_config(conn, teacher, exam)

      view |> element(~s|input[name="mark_step"][value="0.1"]|) |> render_click()
      render_change(view, "set_points_for_six", %{"points_for_six" => "9.5"})
      view |> element("#save-grading-config-btn") |> render_click()

      exam = Tasky.Repo.reload!(exam)
      assert exam.mark_step == "0.1"
      assert exam.grading_max_points == 9.5
    end

    test "saving the step keeps max points changed elsewhere since mount", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = configured_exam(10)
      {:ok, view, _html} = open_config(conn, teacher, exam)

      # Another tab sets the max points after this page loaded.
      {:ok, _exam} = Exams.update_grading_max_points(scope, exam, 8)

      view |> element(~s|input[name="mark_step"][value="0.1"]|) |> render_click()
      view |> element("#save-grading-config-btn") |> render_click()

      exam = Tasky.Repo.reload!(exam)
      assert exam.mark_step == "0.1"
      assert exam.grading_max_points == 8.0
    end

    test "Benotung starten writes the max points as well", %{conn: conn} do
      %{teacher: teacher, exam: exam} = finished_exam()
      {:ok, view, _html} = open_config(conn, teacher, exam)

      render_change(view, "set_points_for_six", %{"points_for_six" => "20"})
      assert Tasky.Repo.reload!(exam).grading_max_points == nil

      assert {:error, {:live_redirect, _}} =
               view |> element("#start-grading-btn") |> render_click()

      exam = Tasky.Repo.reload!(exam)
      assert exam.mark_step == "0.25"
      assert exam.grading_max_points == 20.0
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
