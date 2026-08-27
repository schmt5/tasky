defmodule TaskyWeb.PageControllerTest do
  use TaskyWeb.ConnCase

  import Tasky.AccountsFixtures

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "LearningLine"
  end

  test "GET / as student links to courses and exams", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture(%{role: "student"})) |> get(~p"/")
    html = html_response(conn, 200)

    assert html =~ "Alle Kurse ansehen"
    assert html =~ ~p"/student/courses"
    assert html =~ "Alle Prüfungen ansehen"
    assert html =~ ~p"/student/exams"
  end

  test "GET / as teacher does not expose the admin routes", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture(%{role: "teacher"})) |> get(~p"/")
    html = html_response(conn, 200)

    assert html =~ "Klassen verwalten"
    refute html =~ ~p"/admin/organizations"
    refute html =~ ~p"/admin/users"
  end

  test "GET / as admin links to the administration routes", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture(%{role: "admin"})) |> get(~p"/")
    html = html_response(conn, 200)

    assert html =~ "Organisationen verwalten"
    assert html =~ ~p"/admin/organizations"
    assert html =~ "Benutzer verwalten"
    assert html =~ ~p"/admin/users"
  end
end
