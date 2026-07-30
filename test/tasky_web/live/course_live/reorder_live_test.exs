defmodule TaskyWeb.CourseLive.ReorderTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.TasksFixtures

  alias Tasky.Tasks

  defp course_with_tasks(%{conn: conn}) do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    course = course_fixture(scope: scope)

    [a, b, c] =
      for i <- 1..3 do
        task_fixture(scope, %{name: "Einheit #{i}", position: i - 1, course_id: course.id})
      end

    %{conn: log_in_user(conn, teacher), teacher: teacher, course: course, a: a, b: b, c: c}
  end

  # The persisted order, by task name.
  defp order(course) do
    course.id |> Tasks.list_tasks_by_course() |> Enum.map(& &1.name)
  end

  # The order the page actually renders, read off the `<li id="task-N">` ids.
  defp rendered_ids(html) do
    ~r/id="task-(\d+)"/
    |> Regex.scan(html)
    |> Enum.map(fn [_, id] -> String.to_integer(id) end)
  end

  describe "reordering" do
    setup :course_with_tasks

    test "move_down swaps a unit with its successor", %{conn: conn, course: course, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/reorder")

      lv |> element(~s{button[phx-click="move_down"][phx-value-id="#{a.id}"]}) |> render_click()

      assert order(course) == ["Einheit 2", "Einheit 1", "Einheit 3"]
    end

    test "move_up swaps a unit with its predecessor", %{conn: conn, course: course, c: c} do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/reorder")

      lv |> element(~s{button[phx-click="move_up"][phx-value-id="#{c.id}"]}) |> render_click()

      assert order(course) == ["Einheit 1", "Einheit 3", "Einheit 2"]
    end

    test "the arrows are disabled at the list boundaries", %{conn: conn, course: course} = ctx do
      {:ok, _lv, html} = live(conn, ~p"/courses/#{course}/reorder")

      assert html =~ ~s{phx-click="move_up" phx-value-id="#{ctx.a.id}" disabled}
      assert html =~ ~s{phx-click="move_down" phx-value-id="#{ctx.c.id}" disabled}
      refute html =~ ~s{phx-click="move_up" phx-value-id="#{ctx.b.id}" disabled}
      refute html =~ ~s{phx-click="move_down" phx-value-id="#{ctx.b.id}" disabled}
    end

    test "a move past the boundary is a no-op", %{conn: conn, course: course, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/reorder")

      # Bypasses the disabled attribute the way a tampered client would.
      render_hook_move_up(lv, a.id)

      assert order(course) == ["Einheit 1", "Einheit 2", "Einheit 3"]
    end

    test "dropping before a target inserts the unit above it",
         %{conn: conn, course: course} = ctx do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/reorder")

      render_hook(lv, "move", %{
        "id" => to_string(ctx.c.id),
        "target_id" => to_string(ctx.a.id),
        "place" => "before"
      })

      assert order(course) == ["Einheit 3", "Einheit 1", "Einheit 2"]
    end

    test "dropping after a target inserts the unit below it",
         %{conn: conn, course: course} = ctx do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/reorder")

      render_hook(lv, "move", %{
        "id" => to_string(ctx.a.id),
        "target_id" => to_string(ctx.c.id),
        "place" => "after"
      })

      assert order(course) == ["Einheit 2", "Einheit 3", "Einheit 1"]
    end

    test "the rendered list reflects the new order", %{conn: conn, course: course} = ctx do
      {:ok, lv, html} = live(conn, ~p"/courses/#{course}/reorder")

      assert rendered_ids(html) == [ctx.a.id, ctx.b.id, ctx.c.id]

      html =
        lv
        |> element(~s{button[phx-click="move_up"][phx-value-id="#{ctx.c.id}"]})
        |> render_click()

      assert rendered_ids(html) == [ctx.a.id, ctx.c.id, ctx.b.id]
    end
  end

  describe "status chips" do
    setup :course_with_tasks

    test "match the German labels and colours used on the course page", %{
      conn: conn,
      course: course,
      teacher: teacher,
      a: a
    } do
      scope = user_scope_fixture(teacher)
      {:ok, _} = Tasks.update_task(scope, a, %{status: "archived"})

      {:ok, _lv, reorder_html} = live(conn, ~p"/courses/#{course}/reorder")
      {:ok, _lv, show_html} = live(conn, ~p"/courses/#{course}")

      for html <- [reorder_html, show_html] do
        assert html =~ "bg-amber-100 text-amber-700"
        assert html =~ "Entwurf"
        assert html =~ "Archiviert"
        refute html =~ "Draft"
        refute html =~ "Published"
        refute html =~ "Archived"
      end
    end
  end

  describe "malformed params" do
    setup :course_with_tasks

    test "garbage ids leave the LiveView alive and the order untouched", %{
      conn: conn,
      course: course,
      a: a
    } do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/reorder")

      for params <- [
            %{"id" => "abc", "target_id" => to_string(a.id), "place" => "before"},
            %{"id" => to_string(a.id), "target_id" => nil, "place" => "before"},
            %{"id" => to_string(a.id), "target_id" => to_string(a.id), "place" => "after"},
            %{"id" => "999999", "target_id" => to_string(a.id), "place" => "after"}
          ] do
        render_hook(lv, "move", params)
      end

      render_hook_move_up(lv, "not-a-number")

      assert render(lv) =~ "Lerneinheiten sortieren"
      assert order(course) == ["Einheit 1", "Einheit 2", "Einheit 3"]
    end

    test "an unknown place is ignored without crashing", %{conn: conn, course: course} = ctx do
      {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/reorder")

      render_hook(lv, "move", %{
        "id" => to_string(ctx.c.id),
        "target_id" => to_string(ctx.a.id),
        "place" => "sideways"
      })

      render_hook(lv, "move", %{"nonsense" => true})

      assert render(lv) =~ "Lerneinheiten sortieren"
      assert order(course) == ["Einheit 1", "Einheit 2", "Einheit 3"]
    end
  end

  describe "authorization" do
    setup :course_with_tasks

    test "another teacher cannot open the page", %{conn: conn, course: course} do
      other = user_fixture(%{role: "teacher"})

      assert_raise Ecto.NoResultsError, fn ->
        live(log_in_user(conn, other), ~p"/courses/#{course}/reorder")
      end
    end

    test "a student is redirected away", %{conn: conn, course: course} do
      student = user_fixture()

      assert {:error, {:redirect, _}} =
               live(log_in_user(conn, student), ~p"/courses/#{course}/reorder")
    end
  end

  describe "entry point on the course page" do
    setup :course_with_tasks

    test "the Sortieren link is shown for a course with several units", %{
      conn: conn,
      course: course
    } do
      {:ok, _lv, html} = live(conn, ~p"/courses/#{course}")

      assert html =~ ~p"/courses/#{course}/reorder"
      assert html =~ "Sortieren"
    end

    test "the link is hidden for a course with a single unit", %{conn: conn, teacher: teacher} do
      scope = user_scope_fixture(teacher)
      course = course_fixture(scope: scope)
      task_fixture(scope, %{name: "Nur eine", position: 0, course_id: course.id})

      {:ok, _lv, html} = live(conn, ~p"/courses/#{course}")

      refute html =~ ~p"/courses/#{course}/reorder"
    end
  end

  defp render_hook_move_up(lv, id) do
    render_hook(lv, "move_up", %{"id" => id})
  end
end
