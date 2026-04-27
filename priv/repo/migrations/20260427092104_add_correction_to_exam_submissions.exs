defmodule Tasky.Repo.Migrations.AddCorrectionToExamSubmissions do
  use Ecto.Migration

  def change do
    alter table(:exam_submissions) do
      add :corrected_parts, {:array, :string}, default: [], null: false
      add :corrected_content, :map, default: %{}
    end
  end
end
