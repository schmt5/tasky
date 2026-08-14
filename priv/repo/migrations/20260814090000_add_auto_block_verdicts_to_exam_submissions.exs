defmodule Tasky.Repo.Migrations.AddAutoBlockVerdictsToExamSubmissions do
  use Ecto.Migration

  # Records what the auto-corrector itself last wrote into `block_verdicts`,
  # keyed by the block's `answerId`. Without it a re-run cannot tell its own
  # previous verdict from one the teacher entered by hand, so it overwrote
  # both.
  def change do
    alter table(:exam_submissions) do
      add :auto_block_verdicts, :map, null: false, default: %{}
    end
  end
end
