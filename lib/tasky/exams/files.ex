defmodule Tasky.Exams.Files do
  @moduledoc """
  Files around an exam: the teacher's attachments, the upload fields
  learners hand files in through, and the answer files themselves. Writes to
  a learner's files pass the same write gate as their answers
  (`Tasky.Exams.Access`).
  """

  import Ecto.Query, warn: false
  import Tasky.Exams.Access

  alias Tasky.Exams.Exam
  alias Tasky.Exams.ExamAttachment
  alias Tasky.Exams.ExamSubmission
  alias Tasky.Exams.ExamSubmissionFile
  alias Tasky.Exams.ExamUploadField
  alias Tasky.Policy
  alias Tasky.Positioned
  alias Tasky.Repo

  # --- Attachments (Anhänge) ---

  @doc "Lists an exam's attachments in display order."
  def list_exam_attachments(%Exam{} = exam) do
    Positioned.list(ExamAttachment, :exam_id, exam.id)
  end

  @doc "Gets an attachment of the given exam, or nil."
  def get_exam_attachment(%Exam{} = exam, id) do
    Repo.get_child(ExamAttachment, id, exam_id: exam.id)
  end

  @doc "Gets an attachment by its stored (UUID) filename, or nil."
  def get_exam_attachment_by_stored_filename(exam_id, stored_filename) do
    Repo.get_by(ExamAttachment, exam_id: exam_id, stored_filename: stored_filename)
  end

  @doc """
  Creates an attachment record for a file already stored on disk (see
  `Tasky.Uploads.save_exam_attachment/3`).
  """
  def create_exam_attachment(scope, %Exam{} = exam, attrs) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      position = Positioned.next_position(ExamAttachment, :exam_id, exam.id)

      %ExamAttachment{exam_id: exam.id}
      |> ExamAttachment.changeset(Map.put(attrs, :position, position))
      |> Repo.insert()
    end
  end

  @doc "Deletes an attachment record and its file on disk."
  def delete_exam_attachment(scope, %ExamAttachment{} = attachment) do
    with :ok <- authorize_exam_id(scope, attachment.exam_id),
         {:ok, deleted} <- Repo.delete(attachment) do
      Tasky.Uploads.delete_exam_attachment_file(deleted.exam_id, deleted.stored_filename)
      {:ok, deleted}
    end
  end

  # --- Upload fields (Datei-Abgaben) ---

  @doc "Lists an exam's upload fields in display order."
  def list_upload_fields(%Exam{} = exam), do: list_upload_fields_by_exam_id(exam.id)

  defp list_upload_fields_by_exam_id(exam_id) do
    Positioned.list(ExamUploadField, :exam_id, exam_id)
  end

  @doc "Gets an upload field of the given exam, or nil."
  def get_upload_field(%Exam{} = exam, id) do
    Repo.get_child(ExamUploadField, id, exam_id: exam.id)
  end

  @doc "Creates an upload field, appended at the end."
  def create_upload_field(scope, %Exam{} = exam, attrs) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      position = Positioned.next_position(ExamUploadField, :exam_id, exam.id)

      %ExamUploadField{exam_id: exam.id}
      |> ExamUploadField.changeset(Map.put(attrs, "position", position))
      |> Repo.insert()
    end
  end

  @doc "Updates an upload field."
  def update_upload_field(scope, %ExamUploadField{} = field, attrs) do
    with :ok <- authorize_exam_id(scope, field.exam_id) do
      field
      |> ExamUploadField.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes an upload field including all student files uploaded into it
  (records via FK cascade, bytes on disk explicitly).
  """
  def delete_upload_field(scope, %ExamUploadField{} = field) do
    files =
      Repo.all(
        from sf in ExamSubmissionFile,
          where: sf.upload_field_id == ^field.id,
          join: s in assoc(sf, :exam_submission),
          select: {s.exam_id, sf.exam_submission_id, sf.stored_filename}
      )

    with :ok <- authorize_exam_id(scope, field.exam_id),
         {:ok, deleted} <- Repo.delete(field) do
      Enum.each(files, fn {exam_id, submission_id, stored} ->
        Tasky.Uploads.delete_submission_file_from_disk(exam_id, submission_id, stored)
      end)

      {:ok, deleted}
    end
  end

  @doc "True when the exam has attachments or upload fields (student tab visibility)."
  def exam_has_files?(%Exam{} = exam) do
    Repo.exists?(from a in ExamAttachment, where: a.exam_id == ^exam.id) or
      Repo.exists?(from f in ExamUploadField, where: f.exam_id == ^exam.id)
  end

  # --- Student answer files ---

  @doc """
  Lists all answer files uploaded for an exam (upload field preloaded),
  for the teacher's correction overview.
  """
  def list_exam_submission_files(%Exam{} = exam) do
    Repo.all(
      from sf in ExamSubmissionFile,
        join: s in assoc(sf, :exam_submission),
        where: s.exam_id == ^exam.id,
        join: f in assoc(sf, :upload_field),
        order_by: [asc: f.position, asc: f.id],
        preload: [upload_field: f]
    )
  end

  @doc "Lists a submission's uploaded files."
  def list_submission_files(%ExamSubmission{} = submission) do
    Repo.all(from sf in ExamSubmissionFile, where: sf.exam_submission_id == ^submission.id)
  end

  @doc "Gets a submission's file for one upload field, or nil."
  def get_submission_file(%ExamSubmission{} = submission, field_id) do
    Repo.get_by(ExamSubmissionFile,
      exam_submission_id: submission.id,
      upload_field_id: field_id
    )
  end

  @doc "Gets a file of the given submission by its id, or nil."
  def get_submission_file_by_id(%ExamSubmission{} = submission, file_id) do
    Repo.get_child(ExamSubmissionFile, file_id, exam_submission_id: submission.id)
  end

  @doc """
  Stores/replaces the answer file of one upload field for a submission whose
  bytes are already on disk. A previously uploaded file for the same field is
  replaced and its bytes removed.
  """
  def put_submission_file(%ExamSubmission{} = submission, %ExamUploadField{} = field, attrs) do
    result =
      Repo.transaction(fn ->
        {exam, locked} = lock_submission_for_write!(submission)
        ensure_submission_writable!(exam, locked)

        old = get_submission_file(submission, field.id)

        changeset =
          case old do
            nil ->
              %ExamSubmissionFile{exam_submission_id: submission.id, upload_field_id: field.id}
              |> ExamSubmissionFile.changeset(attrs)

            existing ->
              ExamSubmissionFile.changeset(existing, attrs)
          end

        case Repo.insert_or_update(changeset) do
          {:ok, file} -> {file, old}
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    # Bytes are removed only once the record change has committed, so a rolled
    # back transaction can't leave the DB pointing at a file that is gone.
    with {:ok, {file, old}} <- result do
      if old, do: delete_submission_file_bytes(submission, old.stored_filename)
      {:ok, file}
    end
  end

  @doc "Deletes a submission's answer file (record + bytes)."
  def delete_submission_file(%ExamSubmission{} = submission, %ExamSubmissionFile{} = file) do
    result =
      Repo.transaction(fn ->
        {exam, locked} = lock_submission_for_write!(submission)
        ensure_submission_writable!(exam, locked)

        case Repo.delete(file) do
          {:ok, deleted} -> deleted
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    with {:ok, deleted} <- result do
      delete_submission_file_bytes(submission, deleted.stored_filename)
      {:ok, deleted}
    end
  end

  defp delete_submission_file_bytes(submission, stored_filename) do
    Tasky.Uploads.delete_submission_file_from_disk(
      submission.exam_id,
      submission.id,
      stored_filename
    )
  end

  @doc """
  Required upload fields of the submission's exam that have no file yet.
  Used to gate the exam submit.
  """
  def missing_required_uploads(%ExamSubmission{} = submission) do
    uploaded_ids =
      Repo.all(
        from sf in ExamSubmissionFile,
          where: sf.exam_submission_id == ^submission.id,
          select: sf.upload_field_id
      )

    submission.exam_id
    |> list_upload_fields_by_exam_id()
    |> Enum.filter(&(&1.required and &1.id not in uploaded_ids))
  end
end
