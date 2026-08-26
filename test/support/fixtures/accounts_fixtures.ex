defmodule Tasky.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Tasky.Accounts` context.
  """

  import Ecto.Query

  alias Tasky.Accounts
  alias Tasky.Accounts.Scope
  alias Tasky.Organizations.Organization

  import Tasky.OrganizationsFixtures, only: [default_class: 0, default_organization: 0]

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      firstname: "Test",
      lastname: "User",
      password: "hello world!"
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user({:class, default_class()})

    user
  end

  @doc """
  Creates a user through the real invitation path.

  There is no open registration any more: the link decides the role, so a
  student is registered through a class and a teacher through an organization.
  Both default into the shared test organization (`default_organization/0`), which
  is what lets a test pair a teacher with a student and have them actually see
  each other — otherwise every such test would fail on the fail-closed rule
  rather than on what it means to assert.

  Options:

    * `:role` — `"student"` (default), `"teacher"` or `"admin"`
    * `:class_id` — for students; `nil` produces a class-less student
    * `:organization_id` — for teachers; `nil` produces a teacher without one

  The two `nil` cases can no longer happen through the app; they exist for rows
  that predate organizations, and the fail-closed behaviour around them is worth
  testing.
  """
  def user_fixture(attrs \\ %{}) do
    {role, attrs} = Map.pop(attrs, :role, "student")
    {class_id, attrs} = Map.pop(attrs, :class_id, :default)
    {organization_id, attrs} = Map.pop(attrs, :organization_id, :default)

    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user(invitation(role, class_id, organization_id))

    user
    |> apply_role(role)
    |> apply_membership(role, class_id, organization_id)
  end

  defp invitation("student", class_id, _organization_id),
    do: {:class, resolve_class(class_id)}

  defp invitation(_role, _class_id, organization_id),
    do: {:organization, resolve_organization(organization_id)}

  defp resolve_class(:default), do: default_class()
  defp resolve_class(nil), do: default_class()
  defp resolve_class(id), do: Tasky.Repo.get!(Tasky.Classes.Class, id)

  defp resolve_organization(:default), do: default_organization()
  defp resolve_organization(nil), do: default_organization()
  defp resolve_organization(id), do: Tasky.Repo.get!(Organization, id)

  # The invitation only ever produces "student" or "teacher"; an admin is
  # promoted afterwards, mirroring reality — the app has no UI that creates one.
  defp apply_role(user, role) do
    {:ok, user} = Accounts.update_user_role(user, %{role: role})
    user
  end

  # Straight to the Repo on purpose: an explicit `nil` asks for a user the
  # invitation path can no longer create, and admins hold no organization
  # because they see every one of them.
  defp apply_membership(user, "student", nil, _organization_id),
    do: user |> Ecto.Changeset.change(class_id: nil) |> Tasky.Repo.update!()

  defp apply_membership(user, "student", _class_id, _organization_id), do: user

  defp apply_membership(user, "admin", _class_id, _organization_id),
    do: user |> Ecto.Changeset.change(organization_id: nil) |> Tasky.Repo.update!()

  defp apply_membership(user, _role, _class_id, nil),
    do: user |> Ecto.Changeset.change(organization_id: nil) |> Tasky.Repo.update!()

  defp apply_membership(user, _role, _class_id, _organization_id), do: user

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Tasky.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Tasky.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
