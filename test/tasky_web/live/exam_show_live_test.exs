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

  describe "archiving" do
    setup %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      %{conn: log_in_user(conn, teacher), scope: user_scope_fixture(teacher)}
    end

    test "archives a draft and restores it", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope)

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}")
      refute has_element?(view, "#archived-notice")

      view |> element("#archive-exam") |> render_click()
      assert has_element?(view, "#archived-notice")
      assert Tasky.Exams.archived?(Tasky.Exams.get_exam!(scope, exam.id))

      view |> element("#archived-notice-unarchive") |> render_click()
      refute has_element?(view, "#archived-notice")
      refute Tasky.Exams.archived?(Tasky.Exams.get_exam!(scope, exam.id))
    end

    test "asks before archiving a running session", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope, status: "running")

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}")

      assert has_element?(view, "#archive-exam[data-confirm]")
    end

    test "archives a finished exam without asking", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope, status: "finished")

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}")

      refute has_element?(view, "#archive-exam[data-confirm]")
    end
  end
end
