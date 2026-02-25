defmodule Tasky.Repo.Migrations.CreateCourses do
  use Ecto.Migration

  def change do
    create table(:courses) do
      add :name, :string, null: false
      add :description, :text
      add :teacher_id, references(:users, type: :id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:courses, [:teacher_id])
  end
end
