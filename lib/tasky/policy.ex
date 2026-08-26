defmodule Tasky.Policy do
  @moduledoc """
  The single place the "who may reach what" rules live. There are two, and they
  are orthogonal:

  **Ownership** — for courses, learning units and exams. Decided rule
  (docs/ROBUSTNESS_PLAN.md): **admins see and manage everything**; teachers
  manage what they own. Context mutators call `authorize/2` with the owning
  user's id; read accessors use `can_manage?/2`. Colleagues in the same
  organization do *not* see each other's courses or exams.

  **Organization** — for classes and students. Teachers of one organization
  share its classes and all students in them. `organization_scope/1` resolves
  how far a scope may see; `scope_by_organization/3` narrows a query to it.
  Fail-closed: a teacher without an organization sees nothing, because the
  organization columns shipped without a backfill and NULL is the normal state
  right after deploy.

  Note the asymmetry that keeps this cheap: **for anything that has an owner,
  the organization comes from that owner, not from the caller's scope** — a
  course carries `teacher_id`, and the teacher carries the organization. Only
  classes (which have no owner) and the admin-side organization CRUD need a
  scope threaded in. Resist re-introducing scope parameters elsewhere.

  The special scope `:system` is reserved for trusted, supervised background
  jobs inside `lib/tasky` (e.g. `Tasky.AI.BulkCorrectionRunner`) that act
  without a user — never pass it from the web layer.
  """

  import Ecto.Query, warn: false

  alias Tasky.Accounts.Scope

  @doc "True when the scope may view/edit/delete a resource owned by `owner_id`."
  def can_manage?(:system, _owner_id), do: true
  def can_manage?(%Scope{user: %{role: "admin"}}, _owner_id), do: true
  def can_manage?(%Scope{user: %{id: id}}, owner_id), do: id == owner_id
  def can_manage?(_scope, _owner_id), do: false

  @doc "`:ok` when `can_manage?/2`, otherwise `{:error, :unauthorized}`."
  def authorize(scope, owner_id) do
    if can_manage?(scope, owner_id), do: :ok, else: {:error, :unauthorized}
  end

  @doc """
  `:ok` for admins only.

  For the handful of operations that have no owner to compare against — one
  user administering another — where `authorize/2` has nothing to work with.
  """
  def authorize_admin(:system), do: :ok
  def authorize_admin(%Scope{user: %{role: "admin"}}), do: :ok
  def authorize_admin(_scope), do: {:error, :unauthorized}

  @doc """
  How far this scope may see across organizations.

  Three-valued rather than a boolean on purpose: a boolean cannot express
  "admins bypass the filter", so every call site would have to re-branch on
  `Scope.admin?/1` and duplicate the fail-closed rule.
  """
  def organization_scope(:system), do: :all
  def organization_scope(%Scope{user: %{role: "admin"}}), do: :all
  def organization_scope(%Scope{user: %{organization_id: nil}}), do: :none
  def organization_scope(%Scope{user: %{organization_id: id}}), do: {:org, id}
  def organization_scope(_scope), do: :none

  @doc "True when the scope may reach a record belonging to `org_id`."
  def same_organization?(scope, org_id) do
    case organization_scope(scope) do
      :all -> true
      {:org, id} -> not is_nil(org_id) and id == org_id
      :none -> false
    end
  end

  @doc """
  `:ok` when `same_organization?/2`, otherwise `{:error, :unauthorized}`.
  """
  def authorize_organization(scope, org_id) do
    if same_organization?(scope, org_id), do: :ok, else: {:error, :unauthorized}
  end

  @doc """
  Narrows `query` to the scope's organization.

  `where: false` for a scope without one is what makes this a single
  implementation: it yields `[]` from every `Repo.all`, `Ecto.NoResultsError`
  from every `Repo.one!` and `0` from every count aggregate, so no caller needs
  its own nil-organization branch.
  """
  def scope_by_organization(query, scope, field \\ :organization_id) do
    case organization_scope(scope) do
      :all -> query
      {:org, id} -> from(q in query, where: field(q, ^field) == ^id)
      :none -> from(q in query, where: false)
    end
  end
end
