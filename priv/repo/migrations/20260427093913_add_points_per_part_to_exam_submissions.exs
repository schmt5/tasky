defmodule Tasky.Repo.Migrations.AddPointsPerPartToExamSubmissions do
  use Ecto.Migration

  def change do
    alter table(:exam_submissions) do
      add :points_per_part, :map, default: %{}, null: false
    end
  end
end
