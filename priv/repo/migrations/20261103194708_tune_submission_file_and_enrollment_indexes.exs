defmodule Tasky.Repo.Migrations.TuneSubmissionFileAndEnrollmentIndexes do
  use Ecto.Migration

  # Runs on boot while the previous release still serves requests — learners
  # may be uploading during an exam — so every index is built and dropped
  # CONCURRENTLY, which takes no lock that blocks writes. That rules out the
  # surrounding transaction and the migration lock.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # `upload_field_id` is the target of an ON DELETE CASCADE from the upload
    # fields, and Exams/Tasks.delete_upload_field filter on it. Without an index
    # of its own (it is only the second column of the unique pair below) every
    # field deletion scanned the whole file table.
    create_if_not_exists index(:exam_submission_files, [:upload_field_id], concurrently: true)
    create_if_not_exists index(:task_submission_files, [:upload_field_id], concurrently: true)

    # Each of these is the leading column of a unique composite index on the
    # same table, which serves the same lookups. They only cost writes.
    drop_if_exists index(:exam_submission_files, [:exam_submission_id], concurrently: true)
    drop_if_exists index(:task_submission_files, [:task_submission_id], concurrently: true)
    drop_if_exists index(:course_enrollments, [:course_id], concurrently: true)
    drop_if_exists index(:task_submissions, [:task_id], concurrently: true)
  end
end
