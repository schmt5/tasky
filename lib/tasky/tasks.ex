defmodule Tasky.Tasks do
  @moduledoc """
  The Tasks context.
  """

  import Ecto.Query, warn: false
  alias Tasky.Repo

  alias Tasky.Tasks.Task
  alias Tasky.Tasks.TaskSubmission
  alias Tasky.Accounts.Scope
  alias Tasky.Accounts.User

  @doc """
  Subscribes to scoped notifications about any task changes.

  The broadcasted messages match the pattern:

    * {:created, %Task{}}
    * {:updated, %Task{}}
    * {:deleted, %Task{}}

  """
  def subscribe_tasks(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Tasky.PubSub, "user:#{key}:tasks")
  end

  defp broadcast_task(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Tasky.PubSub, "user:#{key}:tasks", message)
  end

  @doc """
  Returns the list of tasks.

  ## Examples

      iex> list_tasks(scope)
      [%Task{}, ...]

  """
  def list_tasks(%Scope{} = scope) do
    Repo.all_by(Task, user_id: scope.user.id)
  end

  @doc """
  Returns the list of tasks for a specific course.

  ## Examples

      iex> list_tasks_by_course(course_id)
      [%Task{}, ...]

  """
  def list_tasks_by_course(course_id) do
    Task
    |> where([t], t.course_id == ^course_id)
    |> order_by([t], asc: t.position)
    |> Repo.all()
  end

  @doc """
  Gets a single task.

  Raises `Ecto.NoResultsError` if the Task does not exist.

  ## Examples

      iex> get_task!(scope, 123)
      %Task{}

      iex> get_task!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_task!(%Scope{} = scope, id) do
    Repo.get_by!(Task, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a task.

  ## Examples

      iex> create_task(scope, %{field: value})
      {:ok, %Task{}}

      iex> create_task(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_task(%Scope{} = scope, attrs) do
    with {:ok, task = %Task{}} <-
           %Task{}
           |> Task.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_task(scope, {:created, task})
      {:ok, task}
    end
  end

  @doc """
  Updates a task.

  ## Examples

      iex> update_task(scope, task, %{field: new_value})
      {:ok, %Task{}}

      iex> update_task(scope, task, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_task(%Scope{} = scope, %Task{} = task, attrs) do
    true = task.user_id == scope.user.id

    with {:ok, task = %Task{}} <-
           task
           |> Task.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_task(scope, {:updated, task})
      {:ok, task}
    end
  end

  @doc """
  Deletes a task.

  ## Examples

      iex> delete_task(scope, task)
      {:ok, %Task{}}

      iex> delete_task(scope, task)
      {:error, %Ecto.Changeset{}}

  """
  def delete_task(%Scope{} = scope, %Task{} = task) do
    true = task.user_id == scope.user.id

    with {:ok, task = %Task{}} <-
           Repo.delete(task) do
      broadcast_task(scope, {:deleted, task})
      {:ok, task}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking task changes.

  ## Examples

      iex> change_task(scope, task)
      %Ecto.Changeset{data: %Task{}}

  """
  def change_task(%Scope{} = scope, %Task{} = task, attrs \\ %{}) do
    true = task.user_id == scope.user.id

    Task.changeset(task, attrs, scope)
  end

  ## Task Submissions

  @doc """
  Gets or creates a task submission for a student.
  Automatically creates a submission with "not_started" status if one doesn't exist.

  ## Examples

      iex> get_or_create_submission(scope, task_id)
      {:ok, %TaskSubmission{}}

  """
  def get_or_create_submission(%Scope{user: user} = _scope, task_id)
      when user.role == "student" do
    case Repo.get_by(TaskSubmission, task_id: task_id, student_id: user.id) do
      nil ->
        %TaskSubmission{}
        |> TaskSubmission.create_changeset(%{task_id: task_id, student_id: user.id})
        |> Repo.insert()

      submission ->
        {:ok, submission}
    end
  end

  @doc """
  Lists all submissions for a specific student.
  Students can only view their own submissions.

  ## Examples

      iex> list_my_submissions(scope)
      [%TaskSubmission{}, ...]

  """
  def list_my_submissions(%Scope{user: user} = _scope) when user.role == "student" do
    TaskSubmission
    |> where([s], s.student_id == ^user.id)
    |> join(:inner, [s], t in assoc(s, :task))
    |> preload([:task])
    |> order_by([s, t], asc: t.position)
    |> Repo.all()
  end

  @doc """
  Lists all submissions for a specific course for a student.
  Students can only view their own submissions.
  Automatically creates submissions for published tasks that don't have one yet.

  ## Examples

      iex> list_course_submissions(scope, course_id)
      [%TaskSubmission{}, ...]

  """
  def list_course_submissions(%Scope{user: user} = scope, course_id)
      when user.role == "student" do
    # Get all published tasks for the course
    tasks =
      Task
      |> where([t], t.course_id == ^course_id and t.status == "published")
      |> order_by([t], asc: t.position)
      |> Repo.all()

    # For each task, get or create a submission
    Enum.map(tasks, fn task ->
      case get_or_create_submission(scope, task.id) do
        {:ok, submission} ->
          # Preload the task association
          Repo.preload(submission, :task)

        {:error, _} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Lists all submissions for a specific task.
  Only teachers and admins can view all submissions.

  ## Examples

      iex> list_task_submissions(scope, task_id)
      [%TaskSubmission{}, ...]

  """
  def list_task_submissions(%Scope{} = scope, task_id) do
    if Scope.admin_or_teacher?(scope) do
      TaskSubmission
      |> where([s], s.task_id == ^task_id)
      |> preload([:student, :graded_by])
      |> order_by([s], asc: s.status, desc: s.updated_at)
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Updates the status of a task submission.
  Students can only update their own submissions.

  ## Examples

      iex> update_submission_status(scope, submission_id, "in_progress")
      {:ok, %TaskSubmission{}}

  """
  def update_submission_status(%Scope{user: user} = _scope, submission_id, status)
      when user.role == "student" do
    submission = Repo.get!(TaskSubmission, submission_id) |> Repo.preload(:task)

    if submission.student_id == user.id do
      case submission
           |> TaskSubmission.status_changeset(%{status: status})
           |> Repo.update() do
        {:ok, updated_submission} = result ->
          # Broadcast to student's own subscription
          Phoenix.PubSub.broadcast(
            Tasky.PubSub,
            "student:#{user.id}:submissions",
            {:submission_updated, updated_submission}
          )

          # Broadcast to course progress view for teachers
          Phoenix.PubSub.broadcast(
            Tasky.PubSub,
            "course:#{submission.task.course_id}:progress",
            {:submission_updated, updated_submission}
          )

          result

        error ->
          error
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Marks a task as completed by the student.

  ## Examples

      iex> complete_task(scope, submission_id)
      {:ok, %TaskSubmission{}}

  """
  def complete_task(%Scope{user: user} = _scope, submission_id) when user.role == "student" do
    submission = Repo.get!(TaskSubmission, submission_id) |> Repo.preload(:task)

    if submission.student_id == user.id do
      case submission
           |> TaskSubmission.complete_changeset()
           |> Repo.update() do
        {:ok, updated_submission} = result ->
          # Broadcast to student's own subscription
          Phoenix.PubSub.broadcast(
            Tasky.PubSub,
            "student:#{user.id}:submissions",
            {:submission_updated, updated_submission}
          )

          # Broadcast to course progress view for teachers
          Phoenix.PubSub.broadcast(
            Tasky.PubSub,
            "course:#{submission.task.course_id}:progress",
            {:submission_updated, updated_submission}
          )

          result

        error ->
          error
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Grades a task submission.
  Only teachers and admins can grade submissions.

  ## Examples

      iex> grade_submission(scope, submission_id, %{points: 85, feedback: "Great work!"})
      {:ok, %TaskSubmission{}}

  """
  def grade_submission(%Scope{user: user} = scope, submission_id, attrs) do
    if Scope.admin_or_teacher?(scope) do
      submission = Repo.get!(TaskSubmission, submission_id)

      submission
      |> TaskSubmission.grade_changeset(attrs, user.id)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Gets a single task submission.

  ## Examples

      iex> get_submission!(scope, submission_id)
      %TaskSubmission{}

  """
  def get_submission!(%Scope{user: user} = scope, submission_id) do
    submission =
      TaskSubmission
      |> preload([:task, :student, :graded_by])
      |> Repo.get!(submission_id)

    cond do
      # Students can only view their own submissions
      user.role == "student" and submission.student_id == user.id ->
        submission

      # Teachers and admins can view any submission
      Scope.admin_or_teacher?(scope) ->
        submission

      true ->
        raise Ecto.NoResultsError, queryable: TaskSubmission
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking submission changes.

  ## Examples

      iex> change_submission(submission)
      %Ecto.Changeset{data: %TaskSubmission{}}

  """
  def change_submission(%TaskSubmission{} = submission, attrs \\ %{}) do
    TaskSubmission.status_changeset(submission, attrs)
  end

  @doc """
  Lists all students who can be assigned tasks.
  Only teachers and admins can view this list.

  ## Examples

      iex> list_available_students(scope)
      [%User{}, ...]

  """
  def list_available_students(%Scope{} = scope) do
    if Scope.admin_or_teacher?(scope) do
      User
      |> where([u], u.role == "student")
      |> order_by([u], asc: u.email)
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Lists students who are not yet assigned to a task.
  Only teachers and admins can view this list.

  ## Examples

      iex> list_unassigned_students(scope, task_id)
      [%User{}, ...]

  """
  def list_unassigned_students(%Scope{} = scope, task_id) do
    if Scope.admin_or_teacher?(scope) do
      already_assigned_ids =
        TaskSubmission
        |> where([s], s.task_id == ^task_id)
        |> select([s], s.student_id)
        |> Repo.all()

      User
      |> where([u], u.role == "student")
      |> where([u], u.id not in ^already_assigned_ids)
      |> order_by([u], asc: u.email)
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Assigns a task to one or more students by creating submissions.
  Only teachers and admins can assign tasks.

  ## Examples

      iex> assign_task_to_students(scope, task_id, [1, 2, 3])
      {:ok, 3}

  """
  def assign_task_to_students(%Scope{} = scope, task_id, student_ids)
      when is_list(student_ids) do
    if Scope.admin_or_teacher?(scope) do
      # Verify the task belongs to the teacher
      task = get_task!(scope, task_id)

      # Create submissions for each student
      now = DateTime.utc_now(:second)

      submissions =
        Enum.map(student_ids, fn student_id ->
          %{
            task_id: task.id,
            student_id: student_id,
            status: "not_started",
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} =
        Repo.insert_all(
          TaskSubmission,
          submissions,
          on_conflict: :nothing,
          conflict_target: [:task_id, :student_id]
        )

      {:ok, count}
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Assigns a task to all students.
  Only teachers and admins can assign tasks.

  ## Examples

      iex> assign_task_to_all_students(scope, task_id)
      {:ok, 5}

  """
  def assign_task_to_all_students(%Scope{} = scope, task_id) do
    if Scope.admin_or_teacher?(scope) do
      students = list_available_students(scope)
      student_ids = Enum.map(students, & &1.id)
      assign_task_to_students(scope, task_id, student_ids)
    else
      {:error, :unauthorized}
    end
  end
end
