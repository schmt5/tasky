defmodule Tasky.Exams.ExamSubmissionFile do
  @moduledoc """
  A student's uploaded answer file for one upload field of one submission.
  At most one file per (submission, field) — re-uploading replaces it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "exam_submission_files" do
    field :stored_filename, :string
    field :original_name, :string
    field :content_type, :string
    field :size, :integer

    belongs_to :exam_submission, Tasky.Exams.ExamSubmission
    belongs_to :upload_field, Tasky.Exams.ExamUploadField

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(file, attrs) do
    file
    |> cast(attrs, [:stored_filename, :original_name, :content_type, :size])
    |> validate_required([:stored_filename, :original_name, :content_type, :size])
    |> validate_length(:original_name, max: 255)
    |> unique_constraint([:exam_submission_id, :upload_field_id])
  end
end
