defmodule Tasky.Repo.Migrations.CreateTaskSolutionFiles do
  use Ecto.Migration

  def change do
    # Formgleich zu task_attachments — der Unterschied liegt nicht in den
    # Daten, sondern im Zugriff: Lösungsdateien werden nur ausgeliefert, wenn
    # die Lösung für die/den Lernende/n freigegeben ist.
    create table(:task_solution_files) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :stored_filename, :string, null: false
      add :original_name, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:task_solution_files, [:task_id])
    create unique_index(:task_solution_files, [:stored_filename])
  end
end
