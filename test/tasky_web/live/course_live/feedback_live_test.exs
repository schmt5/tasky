defmodule TaskyWeb.CourseLive.FeedbackLiveTest do
  @moduledoc """
  Der Briefkasten aus Sicht der Lehrperson: lesen, abhaken, löschen — und in
  keinem Fall erfahren, von wem eine Nachricht stammt.
  """
  use TaskyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.FeedbackFixtures

  alias Tasky.Feedback.Message
  alias Tasky.Repo

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    teacher_scope = user_scope_fixture(teacher)
    course = course_fixture(scope: teacher_scope, attrs: %{feedback_box_enabled: true})

    student = user_fixture(%{role: "student"})
    enroll_fixture(course, student)

    %{conn: log_in_user(conn, teacher), course: course, student: student, teacher: teacher}
  end

  test "shows the message text and its date, but no name", %{
    conn: conn,
    course: course,
    student: student
  } do
    feedback_message_fixture(course, student, %{body: "Das Tempo ist zu hoch."})

    {:ok, _lv, html} = live(conn, ~p"/courses/#{course}/feedback")

    assert html =~ "Das Tempo ist zu hoch."
    assert html =~ Calendar.strftime(DateTime.utc_now(), "%d.%m.%Y")
    refute html =~ student.email
    assert html =~ "Neu"
  end

  test "shows an empty state without messages", %{conn: conn, course: course} do
    {:ok, _lv, html} = live(conn, ~p"/courses/#{course}/feedback")

    assert html =~ "Noch keine Rückmeldungen"
  end

  test "points out that a closed mailbox is closed", %{conn: conn, teacher: teacher} do
    closed = course_fixture(scope: user_scope_fixture(teacher))

    {:ok, _lv, html} = live(conn, ~p"/courses/#{closed}/feedback")

    assert html =~ "Der Briefkasten ist geschlossen."
  end

  test "marking as read toggles both ways", %{conn: conn, course: course, student: student} do
    message = feedback_message_fixture(course, student)

    {:ok, lv, _html} = live(conn, ~p"/courses/#{course}/feedback")

    html = lv |> element("button[phx-click=toggle_read]") |> render_click()
    assert html =~ "Als ungelesen"
    assert Repo.get!(Message, message.id).read_at

    html = lv |> element("button[phx-click=toggle_read]") |> render_click()
    assert html =~ "Als gelesen"
    refute Repo.get!(Message, message.id).read_at
  end

  test "deleting removes the message from the list", %{
    conn: conn,
    course: course,
    student: student
  } do
    message = feedback_message_fixture(course, student, %{body: "Weg damit"})

    {:ok, lv, html} = live(conn, ~p"/courses/#{course}/feedback")
    assert html =~ "Weg damit"

    html = lv |> element("button[phx-click=delete]") |> render_click()

    refute html =~ "Weg damit"
    assert html =~ "Noch keine Rückmeldungen"
    refute Repo.get(Message, message.id)
  end

  test "a foreign teacher gets a 404", %{conn: conn, course: course} do
    conn = log_in_user(conn, user_fixture(%{role: "teacher"}))

    assert_error_sent 404, fn -> live(conn, ~p"/courses/#{course}/feedback") end
  end
end
