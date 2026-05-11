defmodule Tasky.Repo.Migrations.AddAutoCorrectedPartsToExamSubmissions do
  use Ecto.Migration

  def change do
    alter table(:exam_submissions) do
      add :auto_corrected_parts, {:array, :string}, default: []
    end
  end
end
