defmodule Tasky.Repo.Migrations.AddExamGradingGuards do
  use Ecto.Migration

  @moduledoc """
  Second line of defence behind `Exams.update_grading_max_points/3` and
  `Exams.set_submission_mark/2`. A max of 0 or less divides into every mark of
  the exam — zero removes them all, negative clamps the whole class to 1.0 —
  so the database must refuse it even if a future write path forgets to.
  """

  def change do
    create constraint(:exams, :exams_grading_max_points_positive,
             check: "grading_max_points IS NULL OR grading_max_points > 0"
           )

    create constraint(:exam_submissions, :exam_submissions_mark_range,
             check: "mark IS NULL OR (mark >= 1 AND mark <= 6)"
           )
  end
end
