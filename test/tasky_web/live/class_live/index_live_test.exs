defmodule TaskyWeb.ClassLive.IndexLiveTest do
  @moduledoc """
  Die Klassenübersicht: der Registrierungslink trägt das Einladungstoken der
  Klasse, und «Neu» erneuert es erst nach Bestätigung.
  """
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ClassesFixtures
  import Tasky.OrganizationsFixtures

  alias Tasky.Classes

  setup %{conn: conn} do
    organization = organization_fixture()
    teacher = user_fixture(%{role: "teacher", organization_id: organization.id})
    class = class_fixture(%{name: "Klasse 5a", organization_id: organization.id})

    %{conn: log_in_user(conn, teacher), class: class}
  end

  test "the registration link carries the invite token, not the slug", %{conn: conn, class: class} do
    {:ok, view, _html} = live(conn, ~p"/classes")

    assert has_element?(
             view,
             ~s(#registration-link-#{class.id}[value$="class=#{class.invite_token}"])
           )
  end

  test "a new link replaces the old one only after confirming", %{conn: conn, class: class} do
    {:ok, view, _html} = live(conn, ~p"/classes")

    view |> element("#rotate-link-#{class.id}") |> render_click()
    assert has_element?(view, "#rotate-link-modal")
    assert Classes.get_class_by_invite_token(class.invite_token)

    view |> element("#rotate-link-confirm") |> render_click()
    refute has_element?(view, "#rotate-link-modal")

    assert Classes.get_class_by_invite_token(class.invite_token) == nil
    refute has_element?(view, ~s(#registration-link-#{class.id}[value$="=#{class.invite_token}"]))
  end
end
