defmodule TaskyWeb.CatalogLive.IndexTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.TasksFixtures

  setup %{conn: conn} do
    author =
      user_fixture(%{role: "teacher", firstname: "Anna", lastname: "Autorin"})
      |> user_scope_fixture()

    viewer = user_fixture(%{role: "teacher"})

    %{conn: log_in_user(conn, viewer), author: author, viewer: viewer}
  end

  test "lists a published course with author, unit count and date", %{
    conn: conn,
    author: author
  } do
    course =
      course_fixture(
        scope: author,
        attrs: %{name: "Geteilter Kurs", description: "Sehr nützlich"}
      )

    for i <- 0..1, do: task_fixture(author, %{name: "E#{i}", position: i, course_id: course.id})
    published = catalog_course_fixture(scope: author, course: course)

    {:ok, lv, html} = live(conn, ~p"/catalog")

    assert html =~ "Geteilter Kurs"
    assert html =~ "Sehr nützlich"
    assert html =~ "Anna Autorin"
    assert html =~ "2 Lerneinheiten"
    assert html =~ "Veröffentlicht am"
    assert has_element?(lv, ~s{a[href="/catalog/#{published.id}"]})
  end

  test "does not list an unpublished course", %{conn: conn, author: author} do
    course_fixture(scope: author, attrs: %{name: "Nur für mich"})

    {:ok, _lv, html} = live(conn, ~p"/catalog")

    refute html =~ "Nur für mich"
    assert html =~ "Der Katalog ist noch leer"
  end

  test "badges the viewer's own published course", %{conn: conn, viewer: viewer} do
    own_scope = user_scope_fixture(viewer)
    catalog_course_fixture(scope: own_scope)

    {:ok, _lv, html} = live(conn, ~p"/catalog")

    assert html =~ "Von dir veröffentlicht"
  end

  test "does not badge a foreign course", %{conn: conn, author: author} do
    catalog_course_fixture(scope: author)

    {:ok, _lv, html} = live(conn, ~p"/catalog")

    refute html =~ "Von dir veröffentlicht"
  end

  test "the empty state points back to the teacher's own courses", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/catalog")

    assert html =~ "Der Katalog ist noch leer"
    assert has_element?(lv, ~s{a[href="/courses"]}, "Zu meinen Kursen")
  end
end
