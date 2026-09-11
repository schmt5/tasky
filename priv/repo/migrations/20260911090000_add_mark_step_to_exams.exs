defmodule Tasky.Repo.Migrations.AddMarkStepToExams do
  @moduledoc """
  Per-exam rounding grid for the *mark* (Note), independent of the points grid.

  Points stay on 0.25 steps everywhere — block verdicts, part totals, the
  equal split of a part's points over its answer blocks and the grading
  max-points override all keep running through `Grading.round_quarter/1`.
  What becomes configurable is only the last step of the pipeline: the Swiss
  1–6 mark derived as `points / max * 5 + 1`. Some teachers grade in 0.1
  steps (4.7, then 4.8), others in the 0.25 steps the app has always used.

  Nullable on purpose, and deliberately *not* backfilled: `NULL` means "this
  teacher has not been asked yet" and is what sends them through the grading
  configuration page once, before the grading table opens. A default would
  answer the question on their behalf and the page would never appear. Every
  read path falls back to 0.25 (`Exams.mark_step/1`), so an exam that is
  printed or handed back before the teacher ever opens the Benotung still
  renders exactly the marks it renders today.

  Only `Exams.set_mark_step/3` writes the column — it also re-rounds the
  submissions' stored manual marks onto the new grid, so the value here and
  the marks in `exam_submissions` can never disagree.
  """
  use Ecto.Migration

  def change do
    alter table(:exams) do
      add :mark_step, :string
    end

    create constraint(:exams, :exams_mark_step_check,
             check: "mark_step IS NULL OR mark_step IN ('0.25','0.1')"
           )
  end
end
