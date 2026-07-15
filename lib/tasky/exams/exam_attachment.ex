defmodule Tasky.Exams.ExamAttachment do
  @moduledoc """
  A file the teacher attaches to an exam so students can download it during
  the exam (reading texts, listening comprehension audio, worksheets, …).

  The actual bytes live under the uploads dir (see `Tasky.Uploads`); this
  record only holds the metadata. `stored_filename` is a server-generated
  UUID + extension, never the client-supplied name.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "exam_attachments" do
    field :stored_filename, :string
    field :original_name, :string
    field :content_type, :string
    field :size, :integer
    field :position, :integer, default: 0

    belongs_to :exam, Tasky.Exams.Exam

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:stored_filename, :original_name, :content_type, :size, :position])
    |> validate_required([:stored_filename, :original_name, :content_type, :size])
    |> validate_length(:original_name, max: 255)
    |> unique_constraint(:stored_filename)
  end
end
