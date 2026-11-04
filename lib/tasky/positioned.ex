defmodule Tasky.Positioned do
  @moduledoc """
  The ordered child lists of exams and learning units — attachments, solution
  files, upload fields. They are listed by `position` with the id breaking
  ties, and a new entry goes one past the highest position in use. Five lists
  in `Tasky.Exams` and `Tasky.Tasks` repeated these two queries verbatim.

  Two concurrent appends can draw the same position. The id tie-break keeps
  the order stable all the same, so no lock is taken for it.
  """

  import Ecto.Query, warn: false

  alias Tasky.Repo

  @doc "The rows of `schema` whose `owner_field` is `owner_id`, in display order."
  def list(schema, owner_field, owner_id) do
    Repo.all(
      from r in schema,
        where: field(r, ^owner_field) == ^owner_id,
        order_by: [asc: r.position, asc: r.id]
    )
  end

  @doc "The position a new row of this owner should take: one past the highest in use."
  def next_position(schema, owner_field, owner_id) do
    Repo.one(
      from r in schema,
        where: field(r, ^owner_field) == ^owner_id,
        select: coalesce(max(r.position), -1)
    ) + 1
  end
end
