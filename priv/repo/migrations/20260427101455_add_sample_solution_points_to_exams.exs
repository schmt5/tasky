defmodule Tasky.Repo.Migrations.AddSampleSolutionPointsToExams do
  use Ecto.Migration

  def change do
    alter table(:exams) do
      add :sample_solution_points, :map, default: %{}, null: false
    end
  end
end
