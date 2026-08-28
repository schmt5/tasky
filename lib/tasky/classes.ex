defmodule Tasky.Classes do
  @moduledoc """
  The Classes context.

  A class belongs to one organization, and the teachers of that organization all
  share it. Classes have no owner of their own, which makes this the one context
  that needs a `%Scope{}` threaded in — everywhere else the organization is
  derived from the owner of the resource (see `Tasky.Policy`).

  Every read is fail-closed: a teacher without an organization sees nothing, and
  reaching a foreign class raises `Ecto.NoResultsError` so the web layer answers
  404 rather than 403 (same convention as `Tasky.Courses.get_course!/2`).
  """

  import Ecto.Query, warn: false
  alias Tasky.Repo

  alias Tasky.Accounts.Scope
  alias Tasky.Classes.Class
  alias Tasky.Policy

  @doc """
  Returns the classes of the scope's organization.

  Admins see all classes; a teacher without an organization sees none.

  ## Examples

      iex> list_classes(scope)
      [%Class{}, ...]

  """
  def list_classes(scope) do
    Class
    |> Policy.scope_by_organization(scope)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  @doc """
  Gets a single class from the scope's organization.

  Raises `Ecto.NoResultsError` if the class does not exist or belongs to another
  organization — a foreign class must be indistinguishable from a missing one.

  ## Examples

      iex> get_class!(scope, 123)
      %Class{}

      iex> get_class!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_class!(scope, id) do
    Class
    |> Policy.scope_by_organization(scope)
    |> where([c], c.id == ^id)
    |> Repo.one!()
  end

  @doc """
  True when the scope may reach the class with this id.

  The cheap counterpart to `get_class!/2` for validating a *target* class before
  assigning something to it — `Tasky.Accounts.update_student/3` uses it so a
  teacher cannot move a student into another organization's class by posting a
  foreign `class_id`.

  Accepts the raw string a form sends. Anything unparsable is `false`.
  """
  def visible?(scope, id) when is_integer(id) do
    Class
    |> Policy.scope_by_organization(scope)
    |> where([c], c.id == ^id)
    |> Repo.exists?()
  end

  def visible?(scope, id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> visible?(scope, parsed)
      _ -> false
    end
  end

  def visible?(_scope, _id), do: false

  @doc """
  Gets a class by slug.

  Returns `nil` if no class exists with the given slug.

  Deliberately unscoped: this runs pre-authentication for the registration link
  `/users/register?class=<slug>`, where the slug itself is the credential —
  exactly like `Tasky.Courses.get_course_by_share_slug/1`.

  ## Examples

      iex> get_class_by_slug("klasse-5a")
      %Class{}

      iex> get_class_by_slug("unknown")
      nil

  """
  def get_class_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Class, slug: slug)
  end

  @doc """
  Creates a class in the scope's organization.

  Returns `{:error, :no_organization}` for a teacher who has none — there would
  be no organization to file the class under, and an unfiled class is invisible
  to everyone. Admins pick the organization explicitly and go through
  `Class.admin_changeset/2`.

  ## Examples

      iex> create_class(scope, %{name: "MPA"})
      {:ok, %Class{}}

      iex> create_class(scope, %{name: ""})
      {:error, %Ecto.Changeset{}}

  """
  def create_class(scope, attrs \\ %{}) do
    case Policy.organization_scope(scope) do
      :all ->
        %Class{}
        |> Class.admin_changeset(attrs)
        |> Repo.insert()

      {:org, organization_id} ->
        %Class{organization_id: organization_id}
        |> Class.changeset(attrs)
        |> Repo.insert()

      :none ->
        {:error, :no_organization}
    end
  end

  @doc """
  Updates a class of the scope's organization.

  A teacher may rename a class but never move it to another organization; an
  admin may do both.

  ## Examples

      iex> update_class(scope, class, %{name: "MPA 2"})
      {:ok, %Class{}}

      iex> update_class(scope, foreign_class, %{name: "MPA 2"})
      {:error, :unauthorized}

  """
  def update_class(scope, %Class{} = class, attrs) do
    with :ok <- Policy.authorize_organization(scope, class.organization_id) do
      class
      |> class_changeset(scope, attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes a class of the scope's organization.

  Its students keep their accounts but lose `class_id` (FK nilify) and with it
  their organization, so they fall out of every teacher's view — which is why a
  foreign class must be unreachable here.

  ## Examples

      iex> delete_class(scope, class)
      {:ok, %Class{}}

      iex> delete_class(scope, foreign_class)
      {:error, :unauthorized}

  """
  def delete_class(scope, %Class{} = class) do
    with :ok <- Policy.authorize_organization(scope, class.organization_id) do
      Repo.delete(class)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking class changes.

  ## Examples

      iex> change_class(class)
      %Ecto.Changeset{data: %Class{}}

  """
  def change_class(%Class{} = class, attrs \\ %{}) do
    Class.changeset(class, attrs)
  end

  @doc """
  Returns a map of `%{class_id => student_count}` for the scope's classes in a
  single query.

  Scoped like `list_classes/1` so the counts always match the listed classes.

  ## Examples

      iex> count_students_per_class(scope)
      %{1 => 5, 2 => 3}

  """
  def count_students_per_class(scope) do
    Class
    |> Policy.scope_by_organization(scope)
    |> join(:inner, [c], u in Tasky.Accounts.User, on: u.class_id == c.id)
    |> group_by([c], c.id)
    |> select([c, u], {c.id, count(u.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp class_changeset(%Class{} = class, scope, attrs) do
    if Scope.admin?(scope),
      do: Class.admin_changeset(class, attrs),
      else: Class.changeset(class, attrs)
  end
end
