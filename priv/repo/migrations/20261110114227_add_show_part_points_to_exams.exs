defmodule Tasky.Repo.Migrations.AddShowPartPointsToExams do
  @moduledoc """
  Whether the learners see what each question is worth («4 Punkte» under the
  question heading), online and on the paper version.

  Defaults to true: the paper version always printed the points, so existing
  exams keep doing that and now show them online too. Only the question's
  total is ever shown, never its split over the answer fields.

  Written only by `Tasky.Exams.set_show_part_points/3` and the duplication
  path.
  """

  use Ecto.Migration

  def change do
    alter table(:exams) do
      add :show_part_points, :boolean, null: false, default: true
    end
  end
end
