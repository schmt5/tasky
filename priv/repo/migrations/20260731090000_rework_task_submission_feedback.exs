defmodule Tasky.Repo.Migrations.ReworkTaskSubmissionFeedback do
  use Ecto.Migration

  def up do
    # Lerneinheiten werden nicht bewertet, sondern kommentiert: die Grading-
    # Spalten heissen jetzt nach dem, was sie tatsächlich tragen, und `points`
    # fällt weg (docs/COURSES_TIPTAP_PLAN.md: bleibt bewusst unbenutzt).
    rename table(:task_submissions), :graded_at, to: :feedback_at
    rename table(:task_submissions), :graded_by_id, to: :feedback_by_id

    alter table(:task_submissions) do
      remove :points
      # varchar(255) hat längeres Feedback mit einem Postgrex-Fehler abgewiesen.
      modify :feedback, :text
    end

    # `draft`, `open` und `not_started` waren Synonyme für "noch nicht begonnen".
    execute "UPDATE task_submissions SET status = 'not_started' WHERE status IN ('draft', 'open')"
  end

  def down do
    execute "UPDATE task_submissions SET status = 'not_started' WHERE status = 'in_revision'"

    alter table(:task_submissions) do
      modify :feedback, :string
      add :points, :integer
    end

    rename table(:task_submissions), :feedback_by_id, to: :graded_by_id
    rename table(:task_submissions), :feedback_at, to: :graded_at
  end
end
