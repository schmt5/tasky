defmodule Tasky.Repo.Migrations.AddContentToExamSubmissions do
  use Ecto.Migration

  def change do
    alter table(:exam_submissions) do
      add :content, :map, default: %{}
    end
  end
end
