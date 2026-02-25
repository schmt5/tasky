defmodule Tasky.Courses do
  @moduledoc """
  The Courses context.
  """

  import Ecto.Query, warn: false
  alias Tasky.Repo

  alias Tasky.Courses.Course
  alias Tasky.Courses.CourseEnrollment
  alias Tasky.Accounts.Scope

  @doc """
  Returns the list of courses for a given scope.
  Teachers see only their own courses, admins see all courses.
  """
  def list_courses(%Scope{user: user}) do
    case user.role do
      "admin" ->
        Repo.all(from c in Course, order_by: [desc: c.inserted_at], preload: [:teacher, :tasks])

      "teacher" ->
        Repo.all(
          from c in Course,
            where: c.teacher_id == ^user.id,
            order_by: [desc: c.inserted_at],
            preload: [:teacher, :tasks]
        )

      _ ->
        []
    end
  end

  @doc """
  Returns the list of courses a student is enrolled in.
  """
  def list_enrolled_courses(%Scope{user: %{role: "student", id: student_id}}) do
    Repo.all(
      from c in Course,
        join: e in CourseEnrollment,
        on: c.id == e.course_id,
        where: e.student_id == ^student_id,
        order_by: [desc: c.inserted_at],
        preload: [:teacher, :tasks]
    )
  end

  def list_enrolled_courses(_), do: []

  @doc """
  Gets a single course.

  Raises `Ecto.NoResultsError` if the Course does not exist.
  """
  def get_course!(scope, id) do
    course = Repo.get!(Course, id) |> Repo.preload([:teacher, :tasks])

    case scope.user.role do
      "admin" ->
        course

      "teacher" ->
        if course.teacher_id == scope.user.id do
          course
        else
          raise Ecto.NoResultsError, queryable: Course
        end

      _ ->
        raise Ecto.NoResultsError, queryable: Course
    end
  end

  @doc """
  Gets a course by id for a student if they are enrolled.
  """
  def get_course_for_student!(student_id, course_id) do
    course =
      Repo.one(
        from c in Course,
          join: e in CourseEnrollment,
          on: c.id == e.course_id,
          where: c.id == ^course_id and e.student_id == ^student_id,
          preload: [:teacher, tasks: [:submissions]]
      )

    case course do
      nil -> raise Ecto.NoResultsError, queryable: Course
      course -> course
    end
  end

  @doc """
  Creates a course.
  """
  def create_course(scope, attrs \\ %{}) do
    %Course{}
    |> Course.create_changeset(attrs, scope)
    |> Repo.insert()
  end

  @doc """
  Updates a course.
  """
  def update_course(%Course{} = course, attrs) do
    course
    |> Course.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a course.
  """
  def delete_course(%Course{} = course) do
    Repo.delete(course)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking course changes.
  """
  def change_course(%Course{} = course, attrs \\ %{}) do
    Course.changeset(course, attrs)
  end

  # Enrollment functions

  @doc """
  Enrolls a student in a course.
  """
  def enroll_student(course_id, student_id) do
    %CourseEnrollment{}
    |> CourseEnrollment.changeset(%{course_id: course_id, student_id: student_id})
    |> Repo.insert()
  end

  @doc """
  Unenrolls a student from a course.
  """
  def unenroll_student(course_id, student_id) do
    enrollment =
      Repo.one(
        from e in CourseEnrollment,
          where: e.course_id == ^course_id and e.student_id == ^student_id
      )

    case enrollment do
      nil -> {:error, :not_found}
      enrollment -> Repo.delete(enrollment)
    end
  end

  @doc """
  Returns the list of students enrolled in a course.
  """
  def list_enrolled_students(course_id) do
    Repo.all(
      from u in Tasky.Accounts.User,
        join: e in CourseEnrollment,
        on: u.id == e.student_id,
        where: e.course_id == ^course_id and u.role == "student",
        order_by: u.email
    )
  end

  @doc """
  Returns the list of students not enrolled in a course.
  """
  def list_unenrolled_students(course_id) do
    Repo.all(
      from u in Tasky.Accounts.User,
        where:
          u.role == "student" and
            u.id not in subquery(
              from e in CourseEnrollment,
                where: e.course_id == ^course_id,
                select: e.student_id
            ),
        order_by: u.email
    )
  end

  @doc """
  Checks if a student is enrolled in a course.
  """
  def enrolled?(course_id, student_id) do
    Repo.exists?(
      from e in CourseEnrollment,
        where: e.course_id == ^course_id and e.student_id == ^student_id
    )
  end
end
