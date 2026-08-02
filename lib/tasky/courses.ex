defmodule Tasky.Courses do
  @moduledoc """
  The Courses context.
  """

  import Ecto.Query, warn: false
  alias Tasky.Repo
  alias Tasky.Tasks.Task

  alias Tasky.Accounts.Scope
  alias Tasky.Courses.Course
  alias Tasky.Courses.CourseEnrollment

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
    tasks_query = from t in Task, order_by: [asc: t.position]
    course = Repo.get!(Course, id) |> Repo.preload([:teacher, tasks: tasks_query])

    if Tasky.Policy.can_manage?(scope, course.teacher_id) do
      course
    else
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
  Duplicates a course under the given (caller-provided, localized) name,
  including every learning unit with its content, attachments and upload
  fields (see `Tasky.Tasks.duplicate_task_into_course/3`). Enrollments,
  submissions and student files are not copied — the copy starts empty and
  belongs to the duplicating user.

  The records are written in one transaction; the copied file bytes are the
  one side effect a rollback cannot undo, so a failure can leave orphaned
  files in storage but never half-linked records.
  """
  def duplicate_course(scope, %Course{} = source, name) do
    with :ok <- Tasky.Policy.authorize(scope, source.teacher_id) do
      tasks_query = from t in Task, order_by: [asc: t.position]
      source = Repo.preload(source, tasks: tasks_query)

      attrs = %{
        "name" => String.slice(name, 0, 255),
        "description" => source.description
      }

      Repo.transaction(fn -> insert_duplicate(scope, source, attrs) end)
    end
  end

  defp insert_duplicate(scope, source, attrs) do
    with {:ok, course} <- create_course(scope, attrs),
         :ok <- duplicate_tasks(scope, source.tasks, course.id) do
      course
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp duplicate_tasks(scope, tasks, course_id) do
    Enum.reduce_while(tasks, :ok, fn task, _acc ->
      case Tasky.Tasks.duplicate_task_into_course(scope, task, course_id) do
        {:ok, _task} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
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

  # Share link functions

  @doc """
  Returns the course with a `share_slug`, generating one on first use.

  The slug backs the public Markdown export (`/share/course/:share_slug`),
  which is readable by anyone holding the link — hence 128 bits of entropy,
  the same budget as an exam submission token. Idempotent: a course that
  already has a slug keeps it, so the link a teacher handed to an AI tool
  stays valid.
  """
  def ensure_share_slug(scope, %Course{} = course, attempts \\ 3) do
    with :ok <- Tasky.Policy.authorize(scope, course.teacher_id) do
      if is_binary(course.share_slug) and course.share_slug != "" do
        {:ok, course}
      else
        put_fresh_share_slug(course, attempts)
      end
    end
  end

  defp put_fresh_share_slug(%Course{} = course, attempts) when attempts > 0 do
    result =
      course
      |> Ecto.Changeset.change(share_slug: generate_share_slug())
      |> Ecto.Changeset.unique_constraint(:share_slug)
      |> Repo.update()

    case result do
      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :share_slug) do
          put_fresh_share_slug(course, attempts - 1)
        else
          error
        end

      other ->
        other
    end
  end

  defp put_fresh_share_slug(%Course{}, _attempts), do: {:error, :share_slug_collision}

  defp generate_share_slug do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  @doc """
  Gets a course by its share slug, or `nil` if the slug is unknown.

  Deliberately unscoped — the slug itself is the credential, exactly like
  `Tasky.Exams.get_exam_submission_by_token/1`.
  """
  def get_course_by_share_slug(slug) when is_binary(slug) and slug != "" do
    Repo.get_by(Course, share_slug: slug) |> Repo.preload([:teacher])
  end

  def get_course_by_share_slug(_slug), do: nil

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
  Returns the list of students not enrolled in a course, filtered by class.
  """
  def list_unenrolled_students(course_id, class_id) when is_integer(class_id) do
    Repo.all(
      from u in Tasky.Accounts.User,
        where:
          u.role == "student" and
            u.class_id == ^class_id and
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

  @doc """
  Returns a progress map for all students and tasks in a course.

  The result is a map of `{student_id, task_id} => status` for efficient
  lookup in the progress grid, avoiding raw Repo access in LiveViews.
  """
  def get_progress_map_for_course(course_id, student_ids, task_ids) do
    Repo.all(
      from s in Tasky.Tasks.TaskSubmission,
        join: t in assoc(s, :task),
        where:
          s.student_id in ^student_ids and s.task_id in ^task_ids and t.course_id == ^course_id,
        select: %{student_id: s.student_id, task_id: s.task_id, status: s.status}
    )
    |> Enum.reduce(%{}, fn submission, acc ->
      Map.put(acc, {submission.student_id, submission.task_id}, submission.status)
    end)
  end
end
