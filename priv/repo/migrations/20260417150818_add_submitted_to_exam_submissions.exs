defmodule Tasky.Repo.Migrations.AddSubmittedToExamSubmissions do
  use Ecto.Migration

  def change do
    alter table(:exam_submissions) do
      add :submitted, :boolean, default: false, null: false
    end
  end
end
