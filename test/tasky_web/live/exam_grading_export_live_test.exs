defmodule TaskyWeb.ExamGradingExportLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp graded_exam do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    exam = exam_fixture(scope: scope, status: "running")

    {:ok, submission} =
      exam
      |> exam_submission_fixture(%{"firstname" => "Anna", "lastname" => "Muster"})
      |> Exams.submit_exam_submission()

    {:ok, exam} = Exams.update_exam_status(scope, exam, "finished")
    {:ok, exam, 0} = Exams.set_mark_step(scope, exam, "0.25")

    %{teacher: teacher, exam: exam, submission: submission}
  end

  test "exports one PDF per submission as a ZIP download", %{conn: conn} do
    %{teacher: teacher, exam: exam} = graded_exam()
    conn = log_in_user(conn, teacher)

    {:ok, view, _html} = live(conn, ~p"/exams/#{exam}/correction/grading")

    view |> element("#open-export-modal-btn") |> render_click()
    view |> element("#start-export-btn") |> render_click()

    assert_push_event(view, "download-file", %{url: url}, 10_000)

    conn = get(conn, url)
    assert conn.status == 200

    {:ok, entries} = :zip.unzip(conn.resp_body, [:memory])
    assert [{name, "%PDF" <> _}] = entries
    assert List.to_string(name) =~ "Anna-Muster"
  end
end
