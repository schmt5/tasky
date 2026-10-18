defmodule TaskyWeb.ExamIndexLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    %{conn: log_in_user(conn, teacher), scope: scope}
  end

  describe "status filter" do
    test "shows only exams with the chosen status", %{conn: conn, scope: scope} do
      draft = exam_fixture(scope: scope)
      finished = exam_fixture(scope: scope, status: "finished")

      {:ok, view, _html} = live(conn, ~p"/exams?status=finished")

      assert has_element?(view, "#status-filter-finished[aria-pressed=true]")
      assert has_element?(view, "#exams-#{finished.id}")
      refute has_element?(view, "#exams-#{draft.id}")
    end

    test "switches the filter through the URL", %{conn: conn, scope: scope} do
      draft = exam_fixture(scope: scope)
      finished = exam_fixture(scope: scope, status: "finished")

      {:ok, view, _html} = live(conn, ~p"/exams")
      view |> element("#status-filter-draft") |> render_click()

      assert_patch(view, ~p"/exams?status=draft")
      assert has_element?(view, "#exams-#{draft.id}")
      refute has_element?(view, "#exams-#{finished.id}")
    end

    test "falls back to all for an unknown status", %{conn: conn, scope: scope} do
      draft = exam_fixture(scope: scope)

      {:ok, view, _html} = live(conn, ~p"/exams?status=bogus")

      assert has_element?(view, "#status-filter-all[aria-pressed=true]")
      assert has_element?(view, "#exams-#{draft.id}")
    end

    test "shows an empty state when no exam matches", %{conn: conn, scope: scope} do
      exam_fixture(scope: scope)

      {:ok, view, _html} = live(conn, ~p"/exams?status=running")

      assert has_element?(view, "#exams-empty")
    end
  end
end
