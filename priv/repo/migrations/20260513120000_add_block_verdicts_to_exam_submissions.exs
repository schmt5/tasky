defmodule Tasky.Repo.Migrations.AddBlockVerdictsToExamSubmissions do
  use Ecto.Migration

  def change do
    alter table(:exam_submissions) do
      add :block_verdicts, :map, default: %{}, null: false
    end
  end
end
