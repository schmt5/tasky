defmodule Tasky.Policy do
  @moduledoc """
  The single place the "who may manage what" rule lives.

  Decided rule (docs/ROBUSTNESS_PLAN.md): **admins see and manage
  everything**; teachers manage what they own. Context mutators call
  `authorize/2` with the owning user's id; read accessors use `can_manage?/2`.

  The special scope `:system` is reserved for trusted, supervised background
  jobs inside `lib/tasky` (e.g. `Tasky.AI.BulkCorrectionRunner`) that act
  without a user — never pass it from the web layer.
  """

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
end
