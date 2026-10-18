defmodule TaskyWeb.ExamArchiveLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    %{conn: log_in_user(conn, teacher), scope: scope}
  end

  test "lists only archived exams", %{conn: conn, scope: scope} do
    active = exam_fixture(scope: scope, status: "finished")
    archived = exam_fixture(scope: scope, status: "finished", archived: true)

    {:ok, view, _html} = live(conn, ~p"/exams/archive")

    assert has_element?(view, "#archived-exams #exams-#{archived.id}")
    refute has_element?(view, "#exams-#{active.id}")
  end

  test "restoring brings the exam back with its old status", %{conn: conn, scope: scope} do
    exam = exam_fixture(scope: scope, status: "running", archived: true)

    {:ok, view, _html} = live(conn, ~p"/exams/archive")
    view |> element("#unarchive-#{exam.id}") |> render_click()

    assert has_element?(view, "#archive-empty")

    restored = Exams.get_exam!(scope, exam.id)
    refute Exams.archived?(restored)
    assert restored.status == "running"
  end

  test "shows an empty state without archived exams", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/exams/archive")

    assert has_element?(view, "#archive-empty")
  end

  test "does not show another teacher's archived exams", %{conn: conn} do
    other = user_scope_fixture(user_fixture(%{role: "teacher"}))
    exam = exam_fixture(scope: other, status: "finished", archived: true)

    {:ok, view, _html} = live(conn, ~p"/exams/archive")

    refute has_element?(view, "#exams-#{exam.id}")
  end
end
