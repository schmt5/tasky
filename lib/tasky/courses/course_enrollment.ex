defmodule Tasky.Courses.CourseEnrollment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "course_enrollments" do
    belongs_to :course, Tasky.Courses.Course
    belongs_to :student, Tasky.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(enrollment, attrs) do
    enrollment
    |> cast(attrs, [:course_id, :student_id])
    |> validate_required([:course_id, :student_id])
    |> unique_constraint([:course_id, :student_id])
  end
end
