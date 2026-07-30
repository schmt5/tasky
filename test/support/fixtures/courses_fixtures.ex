defmodule Tasky.CoursesFixtures do
  @moduledoc """
  Test helpers for creating courses and enrollments via `Tasky.Courses`.
  """

  import Tasky.AccountsFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Courses

  @doc """
  Generate a course. Pass `scope:` to set the owning teacher; a fresh teacher
  is created when omitted.
  """
  def course_fixture(opts \\ []) do
    scope =
      Keyword.get_lazy(opts, :scope, fn ->
        user_scope_fixture(user_fixture(%{role: "teacher"}))
      end)

    attrs = opts |> Keyword.get(:attrs, %{}) |> Enum.into(%{name: "Testkurs"})

    {:ok, course} = Courses.create_course(scope, attrs)
    course
  end

  @doc "Enrolls the given student (User or Scope) into the course."
  def enroll_fixture(course, %Scope{user: user}), do: enroll_fixture(course, user)

  def enroll_fixture(course, %Tasky.Accounts.User{} = student) do
    {:ok, enrollment} = Courses.enroll_student(course.id, student.id)
    enrollment
  end
end
