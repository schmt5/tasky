defmodule TaskyWeb.Admin.UserEditLiveDeleteTest do
  @moduledoc """
  Deleting a teacher from the admin's user edit page: who sees the action,
  what the confirmation dialog shows, and that only the typed e-mail address
  lets the delete through.
  """
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Accounts.User

  setup %{conn: conn} do
    admin = user_fixture(%{role: "admin"})
    teacher = user_fixture(%{role: "teacher"})

    %{conn: log_in_user(conn, admin), admin: admin, teacher: teacher}
  end

  defp open_dialog(conn, user) do
    {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/edit")
    view |> element("#delete-teacher-button") |> render_click()
    view
  end

  describe "visibility" do
    test "shows the delete section for a teacher", %{conn: conn, teacher: teacher} do
      {:ok, view, _html} = live(conn, ~p"/admin/users/#{teacher.id}/edit")

      assert has_element?(view, "#delete-teacher-section")
    end

    test "hides it for learners, admins and the admin's own account", %{
      conn: conn,
      admin: admin
    } do
      for user <- [user_fixture(%{role: "student"}), user_fixture(%{role: "admin"}), admin] do
        {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/edit")

        refute has_element?(view, "#delete-teacher-section")
      end
    end
  end

  describe "dialog" do
    test "shows what goes, the exams and the courses handed over", %{
      conn: conn,
      teacher: teacher
    } do
      scope = Scope.for_user(teacher)
      course_fixture(scope: scope)
      published = catalog_course_fixture(scope: scope)
      exam_submission_fixture(exam_fixture(scope: scope, status: "running"))

      view = open_dialog(conn, teacher)

      assert has_element?(view, "#delete-teacher-modal")
      assert has_element?(view, "#delete-summary-courses")
      assert has_element?(view, "#delete-summary-exams")
      assert has_element?(view, "#transferred-course-#{published.id}")
      assert has_element?(view, "#confirm-delete-teacher[disabled]")
    end

    test "has no exam warning when there are no exams", %{conn: conn, teacher: teacher} do
      view = open_dialog(conn, teacher)

      refute has_element?(view, "#delete-summary-exams")
      refute has_element?(view, "#delete-summary-transferred")
    end

    test "closes on cancel", %{conn: conn, teacher: teacher} do
      view = open_dialog(conn, teacher)

      render_click(view, "close_delete_modal")

      refute has_element?(view, "#delete-teacher-modal")
    end
  end

  describe "confirmation" do
    test "enables the button once the e-mail address matches", %{conn: conn, teacher: teacher} do
      view = open_dialog(conn, teacher)
      form = "#delete-teacher-form-#{teacher.id}"

      view |> form(form, delete_teacher: %{email: "falsch@example.com"}) |> render_change()
      assert has_element?(view, "#confirm-delete-teacher[disabled]")

      view |> form(form, delete_teacher: %{email: teacher.email}) |> render_change()
      refute has_element?(view, "#confirm-delete-teacher[disabled]")
    end

    test "a wrong address deletes nothing", %{conn: conn, teacher: teacher} do
      view = open_dialog(conn, teacher)

      view
      |> form("#delete-teacher-form-#{teacher.id}",
        delete_teacher: %{email: "falsch@example.com"}
      )
      |> render_submit()

      assert Tasky.Repo.get(User, teacher.id)
      assert has_element?(view, "#delete-teacher-modal")
    end

    test "the right address deletes the teacher and returns to the user list", %{
      conn: conn,
      teacher: teacher
    } do
      view = open_dialog(conn, teacher)

      view
      |> form("#delete-teacher-form-#{teacher.id}", delete_teacher: %{email: teacher.email})
      |> render_submit()

      assert_redirect(view, ~p"/admin/users")
      refute Tasky.Repo.get(User, teacher.id)
    end
  end
end
