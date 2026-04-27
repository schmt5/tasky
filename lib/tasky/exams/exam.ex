defmodule Tasky.Exams.Exam do
  use Ecto.Schema
  import Ecto.Changeset

  schema "exams" do
    field :name, :string
    field :content, :map, default: %{}
    field :sample_solution, :map, default: %{}
    field :sample_solution_points, :map, default: %{}
    field :enrollment_token, :string
    field :status, :string, default: "draft"

    belongs_to :teacher, Tasky.Accounts.User, foreign_key: :teacher_id
    has_many :exam_submissions, Tasky.Exams.ExamSubmission

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(exam, attrs) do
    exam
    |> cast(attrs, [
      :name,
      :content,
      :sample_solution,
      :sample_solution_points,
      :enrollment_token,
      :status
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 3, max: 255)
    |> validate_inclusion(:status, ~w(draft open running finished archived))
    |> unique_constraint(:enrollment_token)
  end

  @doc false
  def create_changeset(exam, attrs, scope) do
    exam
    |> changeset(attrs)
    |> put_change(:teacher_id, scope.user.id)
  end
end
