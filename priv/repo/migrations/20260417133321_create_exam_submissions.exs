defmodule Tasky.Repo.Migrations.CreateExamSubmissions do
  use Ecto.Migration

  def change do
    create table(:exam_submissions) do
      add :firstname, :string, null: false
      add :lastname, :string, null: false
      add :exam_token, :string, null: false
      add :exam_id, references(:exams, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:exam_submissions, [:exam_id])
    create unique_index(:exam_submissions, [:exam_token])
  end
end
