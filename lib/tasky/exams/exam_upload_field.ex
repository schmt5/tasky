defmodule Tasky.Exams.ExamUploadField do
  @moduledoc """
  A file-answer slot the teacher defines on an exam: students upload exactly
  one file per field (essay PDF, voice recording, …). `allowed_types` holds
  type keys from the registry in `Tasky.Uploads` (e.g. "pdf", "audio").
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "exam_upload_fields" do
    field :label, :string
    field :instruction, :string
    field :allowed_types, {:array, :string}, default: []
    field :required, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :exam, Tasky.Exams.Exam
    has_many :submission_files, Tasky.Exams.ExamSubmissionFile, foreign_key: :upload_field_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(field, attrs) do
    field
    |> cast(attrs, [:label, :instruction, :allowed_types, :required, :position])
    |> validate_required([:label])
    |> validate_length(:label, max: 255)
    |> validate_length(:instruction, max: 1000)
    |> validate_allowed_types()
  end

  defp validate_allowed_types(changeset) do
    changeset
    |> validate_length(:allowed_types, min: 1, message: "mindestens einen Dateityp wählen")
    |> validate_subset(:allowed_types, Tasky.Uploads.answer_type_keys())
  end
end
