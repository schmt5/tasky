defmodule Tasky.Exams.Exam do
  use Ecto.Schema
  import Ecto.Changeset

  schema "exams" do
    field :name, :string
    field :content, :map, default: %{}
    field :sample_solution, :map, default: %{}
    field :sample_solution_points, :map, default: %{}
    # %{part_id => %{answer_id => points}} — a part uses custom (unequal)
    # point distribution iff its inner map is non-empty; otherwise the part's
    # sample_solution_points value is split equally across its answer blocks.
    field :sample_solution_block_points, :map, default: %{}
    field :enrollment_token, :string
    field :status, :string, default: "draft"
    field :seb_enabled, :boolean, default: false
    field :seb_quit_password, :string
    field :ai_correction_config, :map, default: %{}
    field :grading_max_points, :float

    belongs_to :teacher, Tasky.Accounts.User, foreign_key: :teacher_id
    has_many :exam_submissions, Tasky.Exams.ExamSubmission

    timestamps(type: :utc_datetime)
  end

  @doc false
  # :status and :enrollment_token are deliberately not castable — the exam
  # lifecycle goes through Exams.update_exam_status/3 / open_exam_session/2.
  def changeset(exam, attrs) do
    exam
    |> cast(attrs, [
      :name,
      :content,
      :sample_solution,
      :sample_solution_points,
      :sample_solution_block_points,
      :seb_enabled,
      :seb_quit_password,
      :ai_correction_config,
      :grading_max_points
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 3, max: 255)
  end

  @doc false
  def create_changeset(exam, attrs, scope) do
    exam
    |> changeset(attrs)
    |> put_change(:teacher_id, scope.user.id)
  end
end
