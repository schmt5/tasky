defmodule TaskyWeb.StudentsLiveTest do
  @moduledoc """
  The teacher-facing student directory at `/students`: who reaches it, who shows
  up in it, and what the edit page lets a teacher change.
  """
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ClassesFixtures
  import Tasky.OrganizationsFixtures

  setup do
    org = organization_fixture()
    other_org = organization_fixture()

    class = class_fixture(%{organization_id: org.id})
    other_class = class_fixture(%{organization_id: other_org.id})

    %{
      org: org,
      other_org: other_org,
      class: class,
      other_class: other_class,
      teacher: user_fixture(%{role: "teacher", organization_id: org.id}),
      student: user_fixture(%{role: "student", class_id: class.id, firstname: "Mine"}),
      foreign_student:
        user_fixture(%{role: "student", class_id: other_class.id, firstname: "Theirs"})
    }
  end

  describe "index" do
    test "students cannot reach the page", %{conn: conn, student: student} do
      assert {:error, redirect} = live(log_in_user(conn, student), ~p"/students")
      assert {:redirect, %{to: to}} = redirect
      refute to == ~p"/students"
    end

    test "anonymous visitors are redirected to the login", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/students")
      assert to == ~p"/users/log-in"
    end

    test "a teacher sees their own students but not foreign ones", %{
      conn: conn,
      teacher: teacher,
      student: student,
      foreign_student: foreign
    } do
      {:ok, _view, html} = live(log_in_user(conn, teacher), ~p"/students")

      assert html =~ student.email
      refute html =~ foreign.email
    end

    test "colleagues do not appear in the list", %{conn: conn, teacher: teacher, org: org} do
      colleague = user_fixture(%{role: "teacher", organization_id: org.id})
      {:ok, _view, html} = live(log_in_user(conn, teacher), ~p"/students")

      refute html =~ colleague.email
    end

    test "there is no role filter", %{conn: conn, teacher: teacher} do
      {:ok, _view, html} = live(log_in_user(conn, teacher), ~p"/students")

      refute html =~ "Alle Rollen"
      assert html =~ "Alle Klassen"
    end

    test "the class filter narrows the list", %{
      conn: conn,
      teacher: teacher,
      org: org,
      student: student
    } do
      second_class = class_fixture(%{organization_id: org.id})
      elsewhere = user_fixture(%{role: "student", class_id: second_class.id})

      {:ok, view, _html} = live(log_in_user(conn, teacher), ~p"/students")

      html =
        view
        |> element("form[phx-change=filter]")
        |> render_change(%{"class_id" => Integer.to_string(second_class.id)})

      assert html =~ elsewhere.email
      refute html =~ student.email
    end

    test "a teacher without an organization gets the empty state", %{conn: conn} do
      lonely = user_fixture(%{role: "teacher", organization_id: nil})
      {:ok, _view, html} = live(log_in_user(conn, lonely), ~p"/students")

      assert html =~ "Keine Lernenden gefunden"
    end
  end

  describe "edit" do
    test "a foreign student is a 404, not a 403", %{
      conn: conn,
      teacher: teacher,
      foreign_student: foreign
    } do
      assert_raise Ecto.NoResultsError, fn ->
        live(log_in_user(conn, teacher), ~p"/students/#{foreign.id}/edit")
      end
    end

    test "the class select offers only the teacher's own classes", %{
      conn: conn,
      teacher: teacher,
      class: class,
      other_class: other_class,
      student: student
    } do
      {:ok, _view, html} = live(log_in_user(conn, teacher), ~p"/students/#{student.id}/edit")

      assert html =~ class.name
      refute html =~ other_class.name
    end

    test "there is no organization select", %{conn: conn, teacher: teacher, student: student} do
      {:ok, _view, html} = live(log_in_user(conn, teacher), ~p"/students/#{student.id}/edit")

      refute html =~ "user[organization_id]"
    end

    test "a teacher saves a profile change", %{conn: conn, teacher: teacher, student: student} do
      {:ok, view, _html} = live(log_in_user(conn, teacher), ~p"/students/#{student.id}/edit")

      html =
        view
        |> form("#student-edit-form",
          user: %{firstname: "Umbenannt", lastname: student.lastname, email: student.email}
        )
        |> render_submit()

      assert html =~ "aktualisiert"
      assert Tasky.Repo.get!(Tasky.Accounts.User, student.id).firstname == "Umbenannt"
    end

    test "a posted foreign class_id is refused", %{
      conn: conn,
      teacher: teacher,
      student: student,
      other_class: other_class
    } do
      {:ok, view, _html} = live(log_in_user(conn, teacher), ~p"/students/#{student.id}/edit")

      html =
        view
        |> form("#student-edit-form",
          user: %{
            firstname: student.firstname,
            lastname: student.lastname,
            email: student.email
          }
        )
        |> render_submit(%{
          "user" => %{
            "firstname" => student.firstname,
            "lastname" => student.lastname,
            "email" => student.email,
            "class_id" => Integer.to_string(other_class.id)
          }
        })

      assert html =~ "gehört nicht zu deiner Organisation"
      assert Tasky.Repo.get!(Tasky.Accounts.User, student.id).class_id == student.class_id
    end

    test "a teacher resets a student's password", %{
      conn: conn,
      teacher: teacher,
      student: student
    } do
      {:ok, view, _html} = live(log_in_user(conn, teacher), ~p"/students/#{student.id}/edit")

      view |> element("button[phx-click=open_password_modal]") |> render_click()

      html =
        view
        |> form("#password-reset-form-#{student.id}",
          password_reset: %{password: "frisch-gesetzt-123"}
        )
        |> render_submit()

      assert html =~ "zurückgesetzt"
      assert Tasky.Accounts.get_user_by_email_and_password(student.email, "frisch-gesetzt-123")
    end
  end
end
