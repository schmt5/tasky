defmodule Tasky.Exams.Access do
  @moduledoc """
  The two guards every exam write goes through, shared by `Tasky.Exams` and
  its submodules: who may touch a row hanging off an exam (`authorize_exam_id/2`,
  `authorize_submission/2`), and whether a learner may still write to their
  submission (`lock_submission_for_write!/1` + `ensure_submission_writable!/2`).
  Imported, not called through the facade, because they are internal.
  """

  import Ecto.Query, warn: false

  alias Tasky.Exams.Exam
  alias Tasky.Exams.ExamSubmission
  alias Tasky.Policy
  alias Tasky.Repo

  # Locks the rows every student-facing write to a submission needs: the exam
  # FOR SHARE (its status is only read, as a guard) and the submission FOR
  # UPDATE. Same order and modes as `submit_exam_submission/1` above, so none of
  # these writes can deadlock against a submit.
  #
  # For file changes the submission lock does double duty: the submit gate
  # counts this submission's files, and a row lock on the submission does *not*
  # pin rows in exam_submission_files — so without taking the same lock here, a
  # required file could be replaced or deleted between that count and the submit
  # write.
  def lock_submission_for_write!(%ExamSubmission{} = submission) do
    exam = Repo.lock_one!(Exam, submission.exam_id, :share)
    {exam, Repo.lock_one!(ExamSubmission, submission.id)}
  end

  # Rolls the surrounding transaction back unless the student may still write to
  # this submission: only while the exam runs and nothing is handed in. The one
  # gate behind the answer doc *and* the answer files.
  #
  # It is checked here, against the freshly locked rows, rather than in the
  # LiveView, because a LiveView holds the submission it loaded at mount: a
  # stale socket, a late autosave or a replayed event would otherwise still
  # mutate a handed-in submission.
  def ensure_submission_writable!(%Exam{} = exam, %ExamSubmission{} = submission) do
    cond do
      submission.submitted -> Repo.rollback(:already_submitted)
      exam.status != "running" -> Repo.rollback(:exam_not_running)
      true -> :ok
    end
  end

  # Writes to anything hanging off an exam go through the exam owner (or an
  # admin / the :system scope of a trusted background job). One indexed lookup
  # resolves the owning teacher from the child's exam_id; an exam that is gone
  # is not an authorization pass.
  def authorize_exam_id(scope, exam_id) do
    case Repo.one(from e in Exam, where: e.id == ^exam_id, select: e.teacher_id) do
      nil -> {:error, :unauthorized}
      teacher_id -> Policy.authorize(scope, teacher_id)
    end
  end

  def authorize_submission(scope, %ExamSubmission{} = submission),
    do: authorize_exam_id(scope, submission.exam_id)
end
