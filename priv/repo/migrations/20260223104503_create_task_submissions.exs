defmodule Tasky.Repo.Migrations.CreateTaskSubmissions do
  use Ecto.Migration

  def change do
    create table(:task_submissions) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :student_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "not_started"
      add :completed_at, :utc_datetime
      add :points, :integer
      add :feedback, :string
      add :graded_at, :utc_datetime
      add :graded_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:task_submissions, [:task_id, :student_id])
    create index(:task_submissions, [:student_id])
    create index(:task_submissions, [:task_id])
    create index(:task_submissions, [:status])
    create index(:task_submissions, [:graded_by_id])
  end
end
