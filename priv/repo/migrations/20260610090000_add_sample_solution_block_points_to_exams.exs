defmodule Tasky.Repo.Migrations.AddSampleSolutionBlockPointsToExams do
  use Ecto.Migration

  def change do
    alter table(:exams) do
      add :sample_solution_block_points, :map, default: %{}, null: false
    end
  end
end
