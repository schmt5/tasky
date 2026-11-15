defmodule TaskyWeb.CourseLive.StudentsLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ClassesFixtures
  import Tasky.CoursesFixtures

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    %{conn: log_in_user(conn, teacher), scope: user_scope_fixture(teacher)}
  end

  defp open_enroll_modal(conn, course) do
    {:ok, view, _html} = live(conn, ~p"/courses/#{course}/students")
    view |> element("#open-enroll-modal") |> render_click()
    view
  end

  describe "Lernende einschreiben" do
    test "lists candidates by name, not just by e-mail", %{conn: conn, scope: scope} do
      course = course_fixture(scope: scope)
      anna = user_fixture(%{role: "student", firstname: "Anna", lastname: "Müller"})

      view = open_enroll_modal(conn, course)

      assert has_element?(view, "#enroll-candidate-#{anna.id}", "Anna Müller")
    end

    test "the name search narrows the list, ignoring case", %{conn: conn, scope: scope} do
      course = course_fixture(scope: scope)
      anna = user_fixture(%{role: "student", firstname: "Anna", lastname: "Müller"})
      ben = user_fixture(%{role: "student", firstname: "Ben", lastname: "Meier"})

      view = open_enroll_modal(conn, course)
      view |> form("#enroll-filter", %{"search" => "aNNa"}) |> render_change()

      assert has_element?(view, "#enroll-candidate-#{anna.id}")
      refute has_element?(view, "#enroll-candidate-#{ben.id}")

      view |> form("#enroll-filter", %{"search" => "nobody"}) |> render_change()
      assert has_element?(view, "#enroll-empty", "Keine passenden Lernenden gefunden.")
    end

    test "search and class filter combine; enrolling the class needs no search", %{
      conn: conn,
      scope: scope
    } do
      course = course_fixture(scope: scope)
      class = class_fixture()
      anna = user_fixture(%{role: "student", class_id: class.id, firstname: "Anna"})
      ben = user_fixture(%{role: "student", class_id: class.id, firstname: "Ben"})
      outsider = user_fixture(%{role: "student", firstname: "Anna"})

      view = open_enroll_modal(conn, course)

      view |> form("#enroll-filter", %{"class_id" => to_string(class.id)}) |> render_change()
      assert has_element?(view, "button[phx-click=enroll_all_from_class]")

      view
      |> form("#enroll-filter", %{"class_id" => to_string(class.id), "search" => "anna"})
      |> render_change()

      assert has_element?(view, "#enroll-candidate-#{anna.id}")
      refute has_element?(view, "#enroll-candidate-#{ben.id}")
      refute has_element?(view, "#enroll-candidate-#{outsider.id}")
      refute has_element?(view, "button[phx-click=enroll_all_from_class]")
    end
  end

  describe "Lernende ausschreiben" do
    setup %{scope: scope} do
      course = course_fixture(scope: scope)
      student = user_fixture(%{role: "student", class_id: class_fixture().id})

      Tasky.Repo.insert!(%Tasky.Courses.CourseEnrollment{
        course_id: course.id,
        student_id: student.id
      })

      %{course: course, student: student}
    end

    test "unenrolls only after the confirmation", %{
      conn: conn,
      course: course,
      student: student
    } do
      {:ok, view, _html} = live(conn, ~p"/courses/#{course}/students")

      view |> element("#unenroll-student-#{student.id}") |> render_click()
      assert has_element?(view, "#confirm-dialog-message", student.email)
      assert Tasky.Courses.enrolled?(course.id, student.id)

      view |> element("#confirm-dialog-confirm") |> render_click()

      refute has_element?(view, "#confirm-dialog")
      refute Tasky.Courses.enrolled?(course.id, student.id)
      refute has_element?(view, "#unenroll-student-#{student.id}")
    end

    # The dialog shows an email address: a crafted id of someone outside the
    # course must not open it.
    test "does not ask about a student outside the course", %{conn: conn, course: course} do
      outsider = user_fixture(%{role: "student"})

      {:ok, view, _html} = live(conn, ~p"/courses/#{course}/students")

      render_click(view, "ask_confirm", %{
        "action" => "unenroll_student",
        "student_id" => to_string(outsider.id)
      })

      refute has_element?(view, "#confirm-dialog")
      refute render(view) =~ outsider.email
    end
  end
end
