defmodule Tasky.Repo.Migrations.AddAiCorrectionConfigToExams do
  use Ecto.Migration

  def change do
    alter table(:exams) do
      add :ai_correction_config, :map, default: %{}
    end
  end
end
