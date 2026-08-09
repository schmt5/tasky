defmodule TaskyWeb.Student.FeedbackLiveTest do
  @moduledoc """
  Das Briefkasten-Formular der Lernenden: abschicken und fertig — der Text darf
  danach nicht mehr auf der Seite stehen.
  """
  use TaskyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures

  alias Tasky.Feedback.Message
  alias Tasky.Repo

  setup %{conn: conn} do
    teacher_scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
    course = course_fixture(scope: teacher_scope, attrs: %{feedback_box_enabled: true})

    student = user_fixture(%{role: "student"})
    enroll_fixture(course, student)

    %{conn: log_in_user(conn, student), course: course, student: student}
  end

  test "sending stores the message and confirms without echoing the text", %{
    conn: conn,
    course: course,
    student: student
  } do
    {:ok, lv, _html} = live(conn, ~p"/student/courses/#{course}/feedback")

    html =
      lv
      |> form("#feedback-form", message: %{body: "Kapitel 3 war zu schnell."})
      |> render_submit()

    assert html =~ "Danke für deine Rückmeldung"
    refute html =~ "Kapitel 3 war zu schnell."

    message = Repo.one!(Message)
    assert message.body == "Kapitel 3 war zu schnell."
    assert message.course_id == course.id
    assert message.student_id == student.id
  end

  test "an empty message shows the field error and stores nothing", %{
    conn: conn,
    course: course
  } do
    {:ok, lv, _html} = live(conn, ~p"/student/courses/#{course}/feedback")

    html = lv |> form("#feedback-form", message: %{body: "   "}) |> render_submit()

    assert html =~ "Bitte schreibe zuerst etwas."
    refute Repo.one(Message)
  end

  test "writing another message starts from an empty form", %{conn: conn, course: course} do
    {:ok, lv, _html} = live(conn, ~p"/student/courses/#{course}/feedback")

    lv |> form("#feedback-form", message: %{body: "Erste"}) |> render_submit()
    html = lv |> element("button[phx-click=write_another]") |> render_click()

    assert html =~ "feedback-form"
    refute html =~ "Erste"
  end

  test "a closed mailbox redirects back to the course", %{conn: conn, student: student} do
    closed = course_fixture(attrs: %{name: "Geschlossen"})
    enroll_fixture(closed, student)

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/student/courses/#{closed}/feedback")

    assert to == "/student/courses/#{closed.id}"
  end

  test "a student who is not enrolled is sent away", %{conn: conn} do
    foreign = course_fixture(attrs: %{feedback_box_enabled: true})

    assert {:error, {:live_redirect, %{to: "/student/courses"}}} =
             live(conn, ~p"/student/courses/#{foreign}/feedback")
  end
end
