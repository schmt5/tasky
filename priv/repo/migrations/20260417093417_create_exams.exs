defmodule Tasky.Repo.Migrations.CreateExams do
  use Ecto.Migration

  def change do
    create table(:exams) do
      add :name, :string, null: false
      add :content, :map, default: %{}
      add :sample_solution, :map, default: %{}
      add :enrollment_token, :string
      add :status, :string, default: "draft", null: false
      add :teacher_id, references(:users, type: :id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:exams, [:teacher_id])
    create unique_index(:exams, [:enrollment_token])
  end
end
