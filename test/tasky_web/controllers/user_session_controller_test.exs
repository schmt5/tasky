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

  describe "POST /users/log-in rate limits" do
    # A client IP of its own per test: the buckets are global, and the shared
    # 127.0.0.1 budget must stay untouched for every other test.
    defp from_ip(conn),
      do: put_req_header(conn, "fly-client-ip", "10.#{System.unique_integer([:positive])}")

    defp attempt(conn, email, password) do
      post(conn, ~p"/users/log-in", %{"user" => %{"email" => email, "password" => password}})
    end

    test "stops guessing one account after ten attempts, even with the right password", %{
      conn: conn,
      user: user
    } do
      for _ <- 1..10 do
        conn |> from_ip() |> attempt(user.email, "wrong")
      end

      conn = conn |> from_ip() |> attempt(String.upcase(user.email), "hello world!")

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Zu viele Anmeldeversuche"
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "stops one IP after sixty attempts across accounts", %{conn: conn, user: user} do
      ip = "10.#{System.unique_integer([:positive])}"

      # Spent directly rather than through sixty requests: those take long
      # enough to straddle the one-minute window and reset the count midway.
      for _ <- 1..60 do
        TaskyWeb.Plugs.RateLimit.check(:login_ip, ip, 60, 60_000)
      end

      conn = conn |> put_req_header("fly-client-ip", ip) |> attempt(user.email, "hello world!")

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Zu viele Anmeldeversuche"
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
