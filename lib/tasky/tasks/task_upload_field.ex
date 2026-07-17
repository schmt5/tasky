defmodule Tasky.Tasks.TaskUploadField do
  @moduledoc """
  A file-answer slot the teacher defines on a learning unit (task): students
  upload exactly one file per field (edited Word document, PDF, …).
  `allowed_types` holds type keys from the registry in `Tasky.Uploads`
  (e.g. "docx", "pdf").
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "task_upload_fields" do
    field :label, :string
    field :instruction, :string
    field :allowed_types, {:array, :string}, default: []
    field :required, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :task, Tasky.Tasks.Task
    has_many :submission_files, Tasky.Tasks.TaskSubmissionFile, foreign_key: :upload_field_id

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
    changeset = validate_subset(changeset, :allowed_types, Tasky.Uploads.answer_type_keys())

    # validate_length only runs on changes, so an untouched empty default
    # would slip through — check the resulting field value instead.
    case get_field(changeset, :allowed_types) do
      [_ | _] -> changeset
      _ -> add_error(changeset, :allowed_types, "mindestens einen Dateityp wählen")
    end
  end
end
