defmodule TaskyWeb.AssignmentLiveTest do
  use TaskyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Tasky.AssignmentsFixtures

  @create_attrs %{name: "some name", status: "some status", link: "some link"}
  @update_attrs %{
    name: "some updated name",
    status: "some updated status",
    link: "some updated link"
  }
  @invalid_attrs %{name: nil, status: nil, link: nil}
  defp create_assignment(_) do
    assignment = assignment_fixture()

    %{assignment: assignment}
  end

  describe "Index" do
    setup [:create_assignment]

    test "lists all assignments", %{conn: conn, assignment: assignment} do
      {:ok, _index_live, html} = live(conn, ~p"/assignments")

      assert html =~ "Listing Assignments"
      assert html =~ assignment.name
    end

    test "saves new assignment", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/assignments")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Assignment")
               |> render_click()
               |> follow_redirect(conn, ~p"/assignments/new")

      assert render(form_live) =~ "New Assignment"

      assert form_live
             |> form("#assignment-form", assignment: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#assignment-form", assignment: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/assignments")

      html = render(index_live)
      assert html =~ "Assignment created successfully"
      assert html =~ "some name"
    end

    test "updates assignment in listing", %{conn: conn, assignment: assignment} do
      {:ok, index_live, _html} = live(conn, ~p"/assignments")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#assignments-#{assignment.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/assignments/#{assignment}/edit")

      assert render(form_live) =~ "Edit Assignment"

      assert form_live
             |> form("#assignment-form", assignment: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#assignment-form", assignment: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/assignments")

      html = render(index_live)
      assert html =~ "Assignment updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes assignment in listing", %{conn: conn, assignment: assignment} do
      {:ok, index_live, _html} = live(conn, ~p"/assignments")

      assert index_live |> element("#assignments-#{assignment.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#assignments-#{assignment.id}")
    end
  end

  describe "Show" do
    setup [:create_assignment]

    test "displays assignment", %{conn: conn, assignment: assignment} do
      {:ok, _show_live, html} = live(conn, ~p"/assignments/#{assignment}")

      assert html =~ "Show Assignment"
      assert html =~ assignment.name
    end

    test "updates assignment and returns to show", %{conn: conn, assignment: assignment} do
      {:ok, show_live, _html} = live(conn, ~p"/assignments/#{assignment}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/assignments/#{assignment}/edit?return_to=show")

      assert render(form_live) =~ "Edit Assignment"

      assert form_live
             |> form("#assignment-form", assignment: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#assignment-form", assignment: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/assignments/#{assignment}")

      html = render(show_live)
      assert html =~ "Assignment updated successfully"
      assert html =~ "some updated name"
    end
  end
end
