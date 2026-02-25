defmodule Tasky.Courses.Course do
  use Ecto.Schema
  import Ecto.Changeset

  schema "courses" do
    field :name, :string
    field :description, :string

    belongs_to :teacher, Tasky.Accounts.User, foreign_key: :teacher_id
    has_many :tasks, Tasky.Tasks.Task

    many_to_many :students, Tasky.Accounts.User,
      join_through: "course_enrollments",
      join_keys: [course_id: :id, student_id: :id]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(course, attrs) do
    course
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, min: 3, max: 255)
    |> validate_length(:description, max: 1000)
  end

  @doc false
  def create_changeset(course, attrs, scope) do
    course
    |> changeset(attrs)
    |> put_change(:teacher_id, scope.user.id)
  end
end
