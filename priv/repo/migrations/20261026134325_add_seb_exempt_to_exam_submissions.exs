defmodule Tasky.Repo.Migrations.AddSebExemptToExamSubmissions do
  use Ecto.Migration

  @moduledoc """
  Lets the teacher release a single participant from the Safe Exam Browser
  requirement of an exam that otherwise demands it — a broken laptop, a
  disadvantage compensation, an SEB that will not start on exam day.

  Stored on the submission, not the exam: it is a decision about one person.
  `TaskyWeb.SebGuard.mode/2` reports such a submission as `:off`, the mode
  every guard already treats as "SEB is not in play".
  """

  def change do
    alter table(:exam_submissions) do
      add :seb_exempt, :boolean, null: false, default: false
    end
  end
end
