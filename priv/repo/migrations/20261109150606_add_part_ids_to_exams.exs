defmodule Tasky.Repo.Migrations.AddPartIdsToExams do
  @moduledoc """
  The ids of an exam's parts, as a column next to the document.

  The exam list shows whether a finished exam still needs correcting. That is
  "some submission's `corrected_parts` does not contain every part id", and the
  part ids live inside `content` — a document the list deliberately never
  loads. With the ids in their own column the list answers it in one grouped
  query: `NOT e.part_ids <@ s.corrected_parts` (containment, not a count, so a
  part deleted after it was corrected does not skew the answer).

  Written only by `Tasky.Exams.Exam.put_part_ids/1`, on every content write.

  Backfilled here from each exam's `content` with
  `Tasky.ExamDoc.split_content_into_parts/2` — the very split the correction
  keys `corrected_parts` by, including the positional `"q-N"` fallback of old
  documents and the single `"document"` part of a free-document exam. ExamDoc
  is pure (no Repo, no schema), so calling it from a migration is safe.
  """

  use Ecto.Migration

  def up do
    alter table(:exams) do
      add :part_ids, {:array, :string}, null: false, default: []
    end

    flush()

    %{rows: rows} = repo().query!("SELECT id, content, answer_mode FROM exams")

    for [id, content, mode] <- rows do
      ids =
        (content || %{})
        |> Tasky.ExamDoc.split_content_into_parts(mode)
        |> Enum.map(& &1.id)

      repo().query!("UPDATE exams SET part_ids = $1 WHERE id = $2", [ids, id])
    end
  end

  def down do
    alter table(:exams) do
      remove :part_ids
    end
  end
end
