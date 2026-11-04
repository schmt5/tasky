defmodule TaskyWeb.UserLive.RegistrationLiveTest do
  @moduledoc """
  Die Registrierung über einen Klassenlink: das Einladungstoken öffnet sie, und
  pro IP gibt es nur ein begrenztes Kontingent an Versuchen — auch über den
  Websocket, an dem kein Plug mehr mitzählt.
  """
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.ClassesFixtures

  alias TaskyWeb.Plugs.RateLimit

  # A client IP of its own: the rate-limit buckets are global, and the shared
  # 127.0.0.1 budget must stay untouched for every other test.
  defp unique_ip, do: "10.#{System.unique_integer([:positive])}"

  test "caps registration attempts per IP over the open websocket", %{conn: conn} do
    class = class_fixture()
    ip = unique_ip()

    {:ok, view, _html} =
      conn
      |> put_req_header("fly-client-ip", ip)
      |> live(~p"/users/register?class=#{class.invite_token}")

    # Too short a password: every attempt is refused by validation, so none
    # creates an account, but each one spends the budget.
    invalid = %{"user" => %{"email" => "neu@example.com", "password" => "kurz"}}

    html = view |> form("#registration_form", invalid) |> render_submit()
    refute html =~ "Zu viele Registrierungen"

    # The rest of the budget is spent directly, not by 59 more submits: the
    # windows are fixed, and a run that took long enough to cross a window
    # boundary split its attempts over two windows and never hit the cap.
    for _ <- 2..60, do: :ok = RateLimit.check(:registration, ip, 60, 10 * 60_000)

    # Only counts if the submit above spent the same budget.
    assert view |> form("#registration_form", invalid) |> render_submit() =~
             "Zu viele Registrierungen"
  end
end
