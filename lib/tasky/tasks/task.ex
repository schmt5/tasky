defmodule Tasky.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :name, :string
    field :link, :string
    field :position, :integer
    field :status, :string
    field :user_id, :id

    belongs_to :course, Tasky.Courses.Course
    has_many :submissions, Tasky.Tasks.TaskSubmission

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task, attrs, user_scope) do
    task
    |> cast(attrs, [:name, :link, :position, :status, :course_id])
    |> validate_required([:name, :link, :position, :status])
    |> put_change(:user_id, user_scope.user.id)
  end
end
