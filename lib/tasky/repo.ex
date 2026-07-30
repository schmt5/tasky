defmodule Tasky.Repo do
  use Ecto.Repo,
    otp_app: :tasky,
    adapter: Ecto.Adapters.Postgres

  # Selective import: `use Ecto.Repo` already defines preload/3, which would
  # conflict with the `Ecto.Query` macro of the same arity.
  import Ecto.Query, only: [from: 2]

  @doc """
  Fetches one row by primary key and holds a row lock on it until the
  surrounding transaction commits.

  This is the Postgres replacement for SQLite's
  `Repo.transaction(fn -> ... end, mode: :immediate)`: `BEGIN IMMEDIATE` took a
  database-wide write lock, so a read-check-then-write could not interleave.
  Postgres has no equivalent, so every row a guard reads must be locked here —
  a plain `Repo.get!/2` inside a transaction sees the latest committed snapshot
  and a concurrent writer may still commit between the check and the write.

    * `:update` (default) — `FOR UPDATE`, for rows this transaction will write.
    * `:share` — `FOR SHARE`, for rows read only as a guard. It still blocks a
      concurrent `UPDATE` of the row, but does not conflict with the
      `FOR KEY SHARE` that foreign-key inserts take on the parent row, so
      locking an exam for a guard does not block submission inserts.

  When locking more than one row, follow the ordering rule in `ARCHITECTURE.md`
  (parent before child, ascending id within a table) or concurrent callers can
  deadlock. Only meaningful inside `Repo.transaction/1`.
  """
  def lock_one!(schema, id, mode \\ :update)

  def lock_one!(schema, id, :update),
    do: one!(from r in schema, where: r.id == ^id, lock: "FOR UPDATE")

  def lock_one!(schema, id, :share),
    do: one!(from r in schema, where: r.id == ^id, lock: "FOR SHARE")
end
