defmodule Tasky.Repo.Migrations.AddTiptapContentToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :content, :map
    end

    alter table(:task_submissions) do
      add :content, :map
    end

    create table(:task_attachments) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :stored_filename, :string, null: false
      add :original_name, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:task_attachments, [:task_id])
    create unique_index(:task_attachments, [:stored_filename])

    create table(:task_upload_fields) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :label, :string, null: false
      add :instruction, :string
      add :allowed_types, {:array, :string}, null: false, default: []
      add :required, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:task_upload_fields, [:task_id])

    create table(:task_submission_files) do
      add :task_submission_id, references(:task_submissions, on_delete: :delete_all), null: false

      add :upload_field_id, references(:task_upload_fields, on_delete: :delete_all), null: false

      add :stored_filename, :string, null: false
      add :original_name, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:task_submission_files, [:task_submission_id])
    create unique_index(:task_submission_files, [:task_submission_id, :upload_field_id])
  end
end
