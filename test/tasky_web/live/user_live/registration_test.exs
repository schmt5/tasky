defmodule TaskyWeb.UserLive.RegistrationTest do
  use TaskyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures

  alias Tasky.Classes

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Register"
      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces"})

      assert result =~ "Register"
      assert result =~ "must have the @ sign and no spaces"
    end
  end

  describe "register user" do
    test "creates account but does not log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~
               ~r/An email was sent to .*, please access it to confirm your account/
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Log in"
    end
  end

  describe "registration with class parameter" do
    test "displays class name when valid slug is provided", %{conn: conn} do
      {:ok, class} = Classes.create_class(%{name: "Test Class 5a"})

      {:ok, _lv, html} = live(conn, ~p"/users/register?class=#{class.slug}")

      assert html =~ "Test Class 5a"
      assert html =~ "Klasse"
    end

    test "shows error when invalid class slug is provided", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register?class=invalid-slug")

      assert html =~ "Die angegebene Klasse wurde nicht gefunden"
    end

    test "registers user with class when slug is provided", %{conn: conn} do
      {:ok, class} = Classes.create_class(%{name: "Test Class 5a"})
      {:ok, lv, _html} = live(conn, ~p"/users/register?class=#{class.slug}")

      email = unique_user_email()

      form =
        form(lv, "#registration_form",
          user: %{
            "email" => email,
            "firstname" => "Test",
            "lastname" => "Student"
          }
        )

      {:ok, _lv, _html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      # Verify user was created with class_id
      user = Tasky.Accounts.get_user_by_email(email)
      assert user.class_id == class.id
    end

    test "registers user without class when no slug is provided", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      form =
        form(lv, "#registration_form",
          user: %{
            "email" => email,
            "firstname" => "Test",
            "lastname" => "Student"
          }
        )

      {:ok, _lv, _html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      # Verify user was created without class_id
      user = Tasky.Accounts.get_user_by_email(email)
      assert is_nil(user.class_id)
    end
  end
end
