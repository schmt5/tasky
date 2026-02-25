defmodule Tasky.Repo.Migrations.AddCourseIdToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :course_id, references(:courses, type: :id, on_delete: :delete_all)
    end

    create index(:tasks, [:course_id])
  end
end
