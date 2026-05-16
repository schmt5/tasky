defmodule Tasky.Repo.Migrations.AddGradingFields do
  use Ecto.Migration

  def change do
    alter table(:exams) do
      add :grading_max_points, :float
    end

    alter table(:exam_submissions) do
      add :mark, :float
    end
  end
end
