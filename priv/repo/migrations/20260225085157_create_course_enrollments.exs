defmodule Tasky.Repo.Migrations.CreateCourseEnrollments do
  use Ecto.Migration

  def change do
    create table(:course_enrollments) do
      add :course_id, references(:courses, type: :id, on_delete: :delete_all), null: false
      add :student_id, references(:users, type: :id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:course_enrollments, [:course_id])
    create index(:course_enrollments, [:student_id])
    create unique_index(:course_enrollments, [:course_id, :student_id])
  end
end
