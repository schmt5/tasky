defmodule Tasky.Repo.Migrations.AddAnswerModeToExams do
  @moduledoc """
  The second kind of exam: a free document instead of question + answer fields.

  `answer_fields` is what every exam was until now — the teacher writes
  questions (h3) and places answer fields, and the learner may only type into
  those fields. `free_document` has no answer fields at all: the learner edits
  the teacher's document itself, which is what an essay needs.

  The column is written **only** by `Exam.new_changeset/2`, i.e. exactly once
  on the create form. It is deliberately not in `Exam.changeset/2`: part ids,
  answer ids, block verdicts and the sample solution all hang off the mode, so
  a later switch would strand data that has no honest migration. The default
  keeps every existing row on the old behaviour without a backfill.
  """

  use Ecto.Migration

  def change do
    alter table(:exams) do
      add :answer_mode, :string, null: false, default: "answer_fields"
    end

    create constraint(:exams, :exams_answer_mode_check,
             check: "answer_mode IN ('answer_fields','free_document')"
           )
  end
end
