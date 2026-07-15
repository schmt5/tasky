defmodule Tasky.Repo.Migrations.CreateExamFiles do
  use Ecto.Migration

  def change do
    create table(:exam_attachments) do
      add :exam_id, references(:exams, on_delete: :delete_all), null: false
      add :stored_filename, :string, null: false
      add :original_name, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:exam_attachments, [:exam_id])
    create unique_index(:exam_attachments, [:stored_filename])

    create table(:exam_upload_fields) do
      add :exam_id, references(:exams, on_delete: :delete_all), null: false
      add :label, :string, null: false
      add :instruction, :string
      add :allowed_types, {:array, :string}, null: false, default: []
      add :required, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:exam_upload_fields, [:exam_id])

    create table(:exam_submission_files) do
      add :exam_submission_id, references(:exam_submissions, on_delete: :delete_all),
        null: false

      add :upload_field_id, references(:exam_upload_fields, on_delete: :delete_all),
        null: false

      add :stored_filename, :string, null: false
      add :original_name, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:exam_submission_files, [:exam_submission_id])
    create unique_index(:exam_submission_files, [:exam_submission_id, :upload_field_id])
  end
end
