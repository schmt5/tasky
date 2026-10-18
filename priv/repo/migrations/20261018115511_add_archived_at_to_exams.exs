defmodule Tasky.Repo.Migrations.AddArchivedAtToExams do
  use Ecto.Migration

  # Archiving moves out of the status lifecycle into its own column. As a
  # status it could only follow "finished" and was terminal; as a timestamp any
  # exam can be archived and restored, and restoring puts it back exactly where
  # it was, because `status` is never touched.
  #
  # Exams archived the old way could only have been "finished" before, so that
  # is the status they get back. `updated_at` is the best guess at when they
  # were archived: nothing else writes an archived exam.
  def up do
    alter table(:exams) do
      add :archived_at, :utc_datetime
    end

    create index(:exams, [:teacher_id, :archived_at])

    execute "UPDATE exams SET archived_at = updated_at, status = 'finished' WHERE status = 'archived'"
  end

  def down do
    execute "UPDATE exams SET status = 'archived' WHERE archived_at IS NOT NULL AND status = 'finished'"

    drop index(:exams, [:teacher_id, :archived_at])

    alter table(:exams) do
      remove :archived_at
    end
  end
end
