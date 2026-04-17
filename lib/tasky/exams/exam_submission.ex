defmodule Tasky.Exams.ExamSubmission do
  use Ecto.Schema
  import Ecto.Changeset

  schema "exam_submissions" do
    field :firstname, :string
    field :lastname, :string
    field :exam_token, :string

    belongs_to :exam, Tasky.Exams.Exam

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(exam_submission, attrs) do
    exam_submission
    |> cast(attrs, [:firstname, :lastname])
    |> validate_required([:firstname, :lastname])
    |> validate_length(:firstname, min: 1, max: 100)
    |> validate_length(:lastname, min: 1, max: 100)
    |> put_exam_token()
    |> unique_constraint(:exam_token)
  end

  defp put_exam_token(changeset) do
    if get_change(changeset, :exam_token) do
      changeset
    else
      put_change(changeset, :exam_token, generate_exam_token())
    end
  end

  defp generate_exam_token do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
