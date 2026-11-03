defmodule TaskyWeb.UserLive.RegistrationLiveTest do
  @moduledoc """
  Die Registrierung über einen Klassenlink: das Einladungstoken öffnet sie, und
  pro IP gibt es nur ein begrenztes Kontingent an Versuchen — auch über den
  Websocket, an dem kein Plug mehr mitzählt.
  """
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.ClassesFixtures

  # A client IP of its own: the rate-limit buckets are global, and the shared
  # 127.0.0.1 budget must stay untouched for every other test.
  defp from_ip(conn),
    do: put_req_header(conn, "fly-client-ip", "10.#{System.unique_integer([:positive])}")

  test "caps registration attempts per IP over the open websocket", %{conn: conn} do
    class = class_fixture()

    {:ok, view, _html} =
      conn |> from_ip() |> live(~p"/users/register?class=#{class.invite_token}")

    # Too short a password: every attempt is refused by validation, so none
    # creates an account, but each one spends the budget.
    invalid = %{"user" => %{"email" => "neu@example.com", "password" => "kurz"}}

    for _ <- 1..60 do
      html = view |> form("#registration_form", invalid) |> render_submit()
      refute html =~ "Zu viele Registrierungen"
    end

    assert view |> form("#registration_form", invalid) |> render_submit() =~
             "Zu viele Registrierungen"
  end
end
