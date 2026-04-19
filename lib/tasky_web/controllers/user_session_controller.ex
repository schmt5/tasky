defmodule TaskyWeb.UserSessionController do
  use TaskyWeb, :controller

  alias Tasky.Accounts
  alias TaskyWeb.UserAuth

  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> UserAuth.log_in_user(user, user_params)
    else
      conn
      |> put_flash(:error, "Ungültige E-Mail oder Passwort.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
  end
end
