defmodule TaskyWeb.ExamShowLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  defp show(conn, opts) do
    teacher = user_fixture(%{role: "teacher"})
    exam = exam_fixture([scope: user_scope_fixture(teacher)] ++ opts)
    {:ok, _view, html} = conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}")
    html
  end

  describe "status description for an open session" do
    test "assigned mode points at the dashboard, not the enrolment link", %{conn: conn} do
      html = show(conn, status: "open", participation_mode: "assigned")

      assert html =~ "Die Durchführung ist offen."
      assert html =~ "zugewiesenen Lernenden sehen die Prüfung auf ihrem Dashboard"
      refute html =~ "Einschreibelink einschreiben"
    end

    test "anonymous mode points at the enrolment link", %{conn: conn} do
      html = show(conn, status: "open", participation_mode: "anonymous")

      assert html =~ "Die Durchführung ist offen."
      assert html =~ "Einschreibelink einschreiben"
      refute html =~ "auf ihrem Dashboard"
    end
  end
end
