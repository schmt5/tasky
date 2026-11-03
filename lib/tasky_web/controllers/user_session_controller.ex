defmodule TaskyWeb.UserSessionController do
  use TaskyWeb, :controller

  alias Tasky.Accounts
  alias TaskyWeb.Plugs.RateLimit
  alias TaskyWeb.UserAuth

  # Online password guessing. Per IP generous enough for a class logging in
  # together behind one school NAT; per account tight, because nobody types
  # their own password ten times in a quarter of an hour.
  @ip_limit 60
  @ip_window_ms 60_000
  @account_limit 10
  @account_window_ms 15 * 60_000

  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params})
      when is_binary(email) and is_binary(password) do
    if within_limits?(conn, email) do
      if user = Accounts.get_user_by_email_and_password(email, password) do
        conn
        |> UserAuth.log_in_user(user, user_params)
      else
        conn
        |> put_flash(:error, "Ungültige E-Mail oder Passwort.")
        |> redirect(to: ~p"/users/log-in")
      end
    else
      conn
      |> put_flash(:error, "Zu viele Anmeldeversuche. Bitte warte einige Minuten.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
  end

  # Both budgets are spent on every attempt, so a flood from one IP cannot
  # hide behind many accounts, nor a distributed one behind many IPs.
  defp within_limits?(conn, email) do
    account = email |> String.trim() |> String.downcase()

    ip_result = RateLimit.check(:login_ip, RateLimit.client_ip(conn), @ip_limit, @ip_window_ms)

    account_result =
      RateLimit.check(:login_account, account, @account_limit, @account_window_ms)

    ip_result == :ok and account_result == :ok
  end
end
