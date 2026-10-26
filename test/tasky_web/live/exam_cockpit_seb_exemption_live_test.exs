defmodule TaskyWeb.ExamCockpitSebExemptionLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp setup_exam(seb_enabled?) do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    exam = exam_fixture(scope: scope, status: "running", participation_mode: "anonymous")

    {:ok, exam} =
      exam |> Ecto.Changeset.change(%{seb_enabled: seb_enabled?}) |> Tasky.Repo.update()

    %{teacher: teacher, exam: exam, submission: exam_submission_fixture(exam)}
  end

  defp open_cockpit(conn, teacher, exam) do
    conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/cockpit")
  end

  test "releases a participant from SEB and puts them back", %{conn: conn} do
    %{teacher: teacher, exam: exam, submission: submission} = setup_exam(true)
    {:ok, view, _html} = open_cockpit(conn, teacher, exam)
    refute has_element?(view, "#seb-exempt-badge-#{submission.id}")

    view |> element("#toggle-seb-exempt-#{submission.id}") |> render_click()

    assert Exams.get_submission(exam, submission.id).seb_exempt
    assert has_element?(view, "#seb-exempt-badge-#{submission.id}")
    assert has_element?(view, "#toggle-seb-exempt-#{submission.id}", "SEB wieder verlangen")

    view |> element("#toggle-seb-exempt-#{submission.id}") |> render_click()

    refute Exams.get_submission(exam, submission.id).seb_exempt
    refute has_element?(view, "#seb-exempt-badge-#{submission.id}")
  end

  test "offers nothing for an exam that does not require SEB", %{conn: conn} do
    %{teacher: teacher, exam: exam, submission: submission} = setup_exam(false)
    {:ok, view, _html} = open_cockpit(conn, teacher, exam)

    refute has_element?(view, "#toggle-seb-exempt-#{submission.id}")
  end
end
