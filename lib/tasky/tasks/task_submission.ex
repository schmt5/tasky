defmodule Tasky.Tasks.TaskSubmission do
  @moduledoc """
  Schema for tracking student task completion and grading.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses ~w(not_started in_progress completed)

  schema "task_submissions" do
    field :status, :string, default: "not_started"
    field :completed_at, :utc_datetime
    field :points, :integer
    field :feedback, :string

    field :graded_at, :utc_datetime

    belongs_to :task, Tasky.Tasks.Task
    belongs_to :student, Tasky.Accounts.User
    belongs_to :graded_by, Tasky.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid statuses.
  """
  def valid_statuses, do: @valid_statuses

  @doc """
  Changeset for creating a new submission.
  Only sets the task_id and student_id.
  """
  def create_changeset(submission, attrs) do
    submission
    |> cast(attrs, [:task_id, :student_id])
    |> validate_required([:task_id, :student_id])
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:student_id)
    |> unique_constraint([:task_id, :student_id],
      name: :task_submissions_task_id_student_id_index,
      message: "submission already exists for this student and task"
    )
  end

  @doc """
  Changeset for updating submission status by a student.
  """
  def status_changeset(submission, attrs) do
    submission
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @valid_statuses)
    |> maybe_set_completed_at()
  end

  @doc """
  Changeset for completing a task.
  Sets status to "completed" and sets completed_at timestamp.
  """
  def complete_changeset(submission) do
    submission
    |> change(status: "completed", completed_at: DateTime.utc_now(:second))
  end

  @doc """
  Changeset for grading a submission by a teacher.
  """
  def grade_changeset(submission, attrs, grader_id) do
    submission
    |> cast(attrs, [:points, :feedback])
    |> validate_number(:points, greater_than_or_equal_to: 0)
    |> put_change(:graded_by_id, grader_id)
    |> put_change(:graded_at, DateTime.utc_now(:second))
  end

  # Private Functions

  defp maybe_set_completed_at(changeset) do
    case get_change(changeset, :status) do
      "completed" ->
        put_change(changeset, :completed_at, DateTime.utc_now(:second))

      _ ->
        changeset
    end
  end
end
