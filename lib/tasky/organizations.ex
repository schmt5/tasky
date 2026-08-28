defmodule Tasky.Organizations do
  @moduledoc """
  The Organizations context — the tenant boundary for classes and students.

  Two rules live here and nowhere else:

    * **Teachers carry the organization themselves** (`users.organization_id`),
      **students derive theirs from their class** (`classes.organization_id` via
      `users.class_id`). Never write `users.organization_id` for a student; a
      check constraint enforces it.

    * Everything is **fail-closed on `nil`**. A teacher without an organization
      and a student without a class never meet, which matters because the
      organization columns ship without a backfill.

  Administration is admin-only (`Tasky.Policy.authorize_admin/1`); the invite
  token path is deliberately unauthenticated, because the token *is* the
  credential.
  """

  import Ecto.Query, warn: false

  alias Tasky.Accounts.User
  alias Tasky.Classes.Class
  alias Tasky.Organizations.Organization
  alias Tasky.Policy
  alias Tasky.Repo

  ## Student membership (derived through the class)

  @doc """
  Query of the students who belong to `org_id` through their class.

  Fail-closed: a `nil` organization matches nobody, so a teacher without an
  organization sees no students at all.
  """
  def students_query(nil), do: from(u in User, where: false)

  def students_query(org_id) when is_integer(org_id) do
    from u in User,
      join: c in Class,
      on: c.id == u.class_id,
      where: u.role == "student" and c.organization_id == ^org_id
  end

  @doc """
  Query of the students this scope may see.

  The scope-aware companion to `students_query/1`: `:all` for an admin (which
  includes class-less students — they belong to no organization, and only an
  admin can put that right), the organization's students for a teacher, and
  nobody for a scope without one.
  """
  def visible_students_query(scope) do
    case Policy.organization_scope(scope) do
      :all -> from(u in User, where: u.role == "student")
      {:org, id} -> students_query(id)
      :none -> from(u in User, where: false)
    end
  end

  @doc """
  True when this student belongs to `org_id` through their class.

  Fail-closed on `nil` on either side.
  """
  def student_member?(_student_id, nil), do: false
  def student_member?(nil, _org_id), do: false

  def student_member?(student_id, org_id) when is_integer(student_id) and is_integer(org_id) do
    org_id
    |> students_query()
    |> where([u], u.id == ^student_id)
    |> Repo.exists?()
  end

  @doc """
  The organization a teacher belongs to, looked up by id.

  Returns `nil` for an unknown user, a non-teacher, or a teacher without an
  organization — all of which fail closed downstream.
  """
  def teacher_organization_id(nil), do: nil

  def teacher_organization_id(teacher_id) when is_integer(teacher_id) do
    Repo.one(from u in User, where: u.id == ^teacher_id, select: u.organization_id)
  end

  ## Invitation

  @doc """
  Gets an organization by its invite token, or `nil` if the token is unknown.

  Deliberately unscoped and unauthenticated — the token itself is the
  credential, exactly like `Tasky.Courses.get_course_by_share_slug/1`. Unlike
  that one it grants *teacher* access to the organization, so it is a random
  token rather than a slug and can be rotated.
  """
  def get_organization_by_invite_token(token) when is_binary(token) and token != "" do
    Repo.get_by(Organization, invite_token: token)
  end

  def get_organization_by_invite_token(_token), do: nil

  @doc """
  Issues a fresh invite token, invalidating the previous link.

  The old link stops working immediately — that is the point: the token is
  high-value and gets pasted into chats.
  """
  def rotate_invite_token(scope, %Organization{} = organization) do
    with :ok <- Policy.authorize_admin(scope) do
      put_fresh_invite_token(organization, 3)
    end
  end

  ## Administration (admins only)

  @doc "Lists all organizations, alphabetically. `[]` for non-admins."
  def list_organizations(scope) do
    case Policy.authorize_admin(scope) do
      :ok -> Repo.all(from o in Organization, order_by: [asc: o.name])
      {:error, :unauthorized} -> []
    end
  end

  @doc """
  Gets a single organization.

  Raises `Ecto.NoResultsError` for non-admins so an unauthorized caller sees a
  404 rather than a 403, matching `Tasky.Courses.get_course!/2`.
  """
  def get_organization!(scope, id) do
    case Policy.authorize_admin(scope) do
      :ok -> Repo.get!(Organization, id)
      {:error, :unauthorized} -> raise Ecto.NoResultsError, queryable: Organization
    end
  end

  @doc "Creates an organization with a fresh invite token."
  def create_organization(scope, attrs) do
    with :ok <- Policy.authorize_admin(scope) do
      %Organization{}
      |> Organization.changeset(attrs)
      |> Ecto.Changeset.put_change(:invite_token, generate_invite_token())
      |> Ecto.Changeset.unique_constraint(:invite_token)
      |> Repo.insert()
    end
  end

  @doc "Renames an organization. The invite token is untouched."
  def update_organization(scope, %Organization{} = organization, attrs) do
    with :ok <- Policy.authorize_admin(scope) do
      organization
      |> Organization.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes an organization.

  Members and classes are *not* deleted — the FKs nilify. Their classes then
  belong to no organization and are invisible to every teacher, which is why the
  UI shows the counts before confirming.
  """
  def delete_organization(scope, %Organization{} = organization) do
    with :ok <- Policy.authorize_admin(scope) do
      Repo.delete(organization)
    end
  end

  @doc "Returns an `%Ecto.Changeset{}` for tracking organization changes."
  def change_organization(%Organization{} = organization, attrs \\ %{}) do
    Organization.changeset(organization, attrs)
  end

  @doc "Map of `%{organization_id => member_count}` in one query."
  def count_members_per_organization(scope) do
    case Policy.authorize_admin(scope) do
      :ok ->
        Repo.all(
          from u in User,
            where: not is_nil(u.organization_id),
            group_by: u.organization_id,
            select: {u.organization_id, count(u.id)}
        )
        |> Map.new()

      {:error, :unauthorized} ->
        %{}
    end
  end

  @doc "Map of `%{organization_id => class_count}` in one query."
  def count_classes_per_organization(scope) do
    case Policy.authorize_admin(scope) do
      :ok ->
        Repo.all(
          from c in Class,
            where: not is_nil(c.organization_id),
            group_by: c.organization_id,
            select: {c.organization_id, count(c.id)}
        )
        |> Map.new()

      {:error, :unauthorized} ->
        %{}
    end
  end

  defp put_fresh_invite_token(%Organization{} = organization, attempts) when attempts > 0 do
    result =
      organization
      |> Ecto.Changeset.change(invite_token: generate_invite_token())
      |> Ecto.Changeset.unique_constraint(:invite_token)
      |> Repo.update()

    case result do
      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :invite_token) do
          put_fresh_invite_token(organization, attempts - 1)
        else
          error
        end

      other ->
        other
    end
  end

  defp put_fresh_invite_token(%Organization{}, _attempts), do: {:error, :invite_token_collision}

  defp generate_invite_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
