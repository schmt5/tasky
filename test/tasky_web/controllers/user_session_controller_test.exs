defmodule TaskyWeb.UserSessionControllerTest do
  use TaskyWeb.ConnCase

  import Tasky.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "POST /users/log-in" do
    test "logs the user in with valid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "hello world!"}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with invalid password", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "wrong"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Ungültige E-Mail oder Passwort."
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "redirects to login page with invalid email", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => "unknown@example.com", "password" => "hello world!"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Ungültige E-Mail oder Passwort."
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end
end
