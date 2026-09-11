defmodule Tasky.Repo.Migrations.AddPaperLayoutToExams do
  @moduledoc """
  How big each answer field is on the printed paper version, as
  `%{answer_id => lines}`.

  Its own column rather than a change to `content`: the paper version grows the
  answer boxes by putting empty paragraphs inside them, and `content` is the
  document the learners actually sit — writing the print geometry there would
  put blank paragraphs into the digital exam.

  Only the line count is stored, not the paper document. That way the layout
  survives later edits to the exam: a newly placed answer field starts from the
  point-derived default (`Tasky.ExamPaper.lines_for_points/1`) and an entry
  whose field was deleted is simply ignored.

  `nil` means "every box on its default size", so there is nothing to backfill.
  Written only by `Tasky.Exams.update_paper_layout/3` and carried to a copy by
  the duplication path — the column is deliberately absent from
  `Exam.changeset/2`, so neither goes through cast.
  """

  use Ecto.Migration

  def change do
    alter table(:exams) do
      add :paper_layout, :map
    end
  end
end
