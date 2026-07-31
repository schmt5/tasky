defmodule Tasky.Tasks do
  @moduledoc """
  The Tasks context.
  """

  import Ecto.Query, warn: false
  alias Tasky.Repo

  alias Tasky.Accounts.Scope
  alias Tasky.Accounts.User
  alias Tasky.Correction.AnswerKey
  alias Tasky.Policy
  alias Tasky.Tasks.Task
  alias Tasky.Tasks.TaskAttachment
  alias Tasky.Tasks.TaskSubmission
  alias Tasky.Tasks.TaskSubmissionFile
  alias Tasky.Tasks.TaskUploadField

  # Submission statuses in which the student may still edit answers,
  # upload files and mark the unit as complete.
  @editable_statuses ~w(draft open in_progress not_started review_denied)

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
  def list_tasks(%Scope{user: %{role: "admin"}}) do
    Repo.all(Task)
  end

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
    task = Repo.get!(Task, id)

    if Policy.can_manage?(scope, task.user_id) do
      task
    else
      raise Ecto.NoResultsError, queryable: Task
    end
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
  Copies a learning unit into another course, including its Tiptap content
  (with its content images), teacher attachments and student upload fields.
  Submissions and the files students uploaded are deliberately left behind —
  a duplicate starts without any student data.

  ## Examples

      iex> duplicate_task_into_course(scope, task, course.id)
      {:ok, %Task{}}

  """
  def duplicate_task_into_course(%Scope{} = scope, %Task{} = source, course_id) do
    with :ok <- Policy.authorize(scope, source.user_id),
         {:ok, task} <-
           create_task(scope, %{
             name: source.name,
             position: source.position,
             status: source.status,
             locked: source.locked,
             course_id: course_id
           }),
         {:ok, task} <- copy_task_content(task, source),
         :ok <- copy_task_attachments(task, source),
         :ok <- copy_task_upload_fields(task, source) do
      {:ok, task}
    end
  end

  defp copy_task_content(task, %Task{content: nil}), do: {:ok, task}

  defp copy_task_content(task, %Task{content: content} = source) do
    task
    |> Task.content_changeset(copy_content_images(content, source.id, task.id))
    |> Repo.update()
  end

  # Content images live under their own task's upload prefix, so the copy has
  # to take its own bytes along and point at them — sharing the source's files
  # would blank the duplicate out as soon as the original unit is deleted.
  defp copy_content_images(content, from_task_id, to_task_id) do
    ctx = {
      "/uploads/tasks/#{from_task_id}/",
      "/uploads/tasks/#{to_task_id}/",
      from_task_id,
      to_task_id
    }

    rewrite_image_refs(content, ctx)
  end

  defp rewrite_image_refs(value, ctx) when is_map(value),
    do: Map.new(value, fn {k, v} -> {k, rewrite_image_refs(v, ctx)} end)

  defp rewrite_image_refs(value, ctx) when is_list(value),
    do: Enum.map(value, &rewrite_image_refs(&1, ctx))

  defp rewrite_image_refs(value, {prefix, new_prefix, from_task_id, to_task_id})
       when is_binary(value) do
    # Only direct children of the task prefix are content images; anything
    # deeper (an attachment path, say) is not ours to rewrite. A file that no
    # longer exists keeps its old URL rather than failing the duplication.
    with true <- String.starts_with?(value, prefix),
         filename = String.replace_prefix(value, prefix, ""),
         false <- String.contains?(filename, "/"),
         :ok <- Tasky.Uploads.copy_task_image(from_task_id, to_task_id, filename) do
      new_prefix <> filename
    else
      _ -> value
    end
  end

  defp rewrite_image_refs(value, _ctx), do: value

  defp copy_task_attachments(task, source) do
    source
    |> list_task_attachments()
    |> Enum.reduce_while(:ok, fn attachment, _acc ->
      case Tasky.Uploads.copy_task_attachment_file(
             source.id,
             task.id,
             attachment.stored_filename
           ) do
        {:ok, stored_filename} ->
          case create_task_attachment(task, %{
                 stored_filename: stored_filename,
                 original_name: attachment.original_name,
                 content_type: attachment.content_type,
                 size: attachment.size
               }) do
            {:ok, _attachment} -> {:cont, :ok}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end

        # Bytes that already vanished from storage leave a dangling record
        # behind; that is not a reason to fail the whole duplication.
        {:error, _reason} ->
          {:cont, :ok}
      end
    end)
  end

  defp copy_task_upload_fields(task, source) do
    source
    |> list_task_upload_fields()
    |> Enum.reduce_while(:ok, fn field, _acc ->
      case create_task_upload_field(task, %{
             "label" => field.label,
             "instruction" => field.instruction,
             "allowed_types" => field.allowed_types,
             "required" => field.required
           }) do
        {:ok, _field} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
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
    with :ok <- Policy.authorize(scope, task.user_id),
         {:ok, task = %Task{}} <-
           task
           |> Task.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_task(scope, {:updated, task})
      {:ok, task}
    end
  end

  @doc """
  Toggles the locked status of a task.
  Only the owner (teacher) can toggle locked status.

  ## Examples

      iex> toggle_locked(scope, task)
      {:ok, %Task{}}

  """
  def toggle_locked(%Scope{} = scope, %Task{} = task) do
    with :ok <- Policy.authorize(scope, task.user_id),
         {:ok, task = %Task{}} <-
           task
           |> Ecto.Changeset.change(%{locked: !task.locked})
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
    with :ok <- Policy.authorize(scope, task.user_id),
         {:ok, task = %Task{}} <- Repo.delete(task) do
      # The DB cascade removes the rows; the stored bytes (content images,
      # attachments, submission files) must go too or they leak forever.
      Tasky.Uploads.delete_task_files(task.id)
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
    unless Policy.can_manage?(scope, task.user_id) do
      raise Ecto.NoResultsError, queryable: Task
    end

    Task.changeset(task, attrs, scope)
  end

  @doc """
  Reorders a course's tasks to match `ordered_ids`.

  `ordered_ids` must list *every* task of the course exactly once — a partial
  list is rejected, because the dense positions written here would otherwise
  collide with the positions of the tasks left out. Positions are always
  rewritten as `0..n-1`, which also heals the `nil` and duplicate values the
  schema still permits.

  ## Examples

      iex> reorder_tasks(scope, course.id, [3, 1, 2])
      {:ok, :reordered}

  """
  def reorder_tasks(%Scope{} = scope, course_id, ordered_ids) when is_list(ordered_ids) do
    tasks = Repo.all(from t in Task, where: t.course_id == ^course_id)

    cond do
      # Length *and* set equality together also rule out duplicate ids, which
      # set equality alone would happily accept.
      length(ordered_ids) != length(tasks) ->
        {:error, :invalid_order}

      MapSet.new(ordered_ids) != MapSet.new(tasks, & &1.id) ->
        {:error, :invalid_order}

      not Enum.all?(tasks, &Policy.can_manage?(scope, &1.user_id)) ->
        {:error, :unauthorized}

      true ->
        tasks_by_id = Map.new(tasks, &{&1.id, &1})

        Repo.transaction(fn ->
          ordered_ids
          |> Enum.with_index()
          |> Enum.each(fn {id, position} ->
            tasks_by_id
            |> Map.fetch!(id)
            |> Ecto.Changeset.change(%{position: position})
            |> Repo.update!()
          end)

          :reordered
        end)
    end
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
    # Get all published tasks for the course, including draft ones so students see "Bald verfügbar"
    tasks =
      Task
      |> where([t], t.course_id == ^course_id and t.status == "published")
      |> order_by([t], asc: t.position)
      |> Repo.all()

    # Ensure a submission row exists for every non-locked task
    Enum.each(tasks, fn task ->
      unless task.locked do
        get_or_create_submission(scope, task.id)
      end
    end)

    task_ids = Enum.map(tasks, & &1.id)

    # Fetch existing submissions for non-draft tasks
    submissions_by_task =
      TaskSubmission
      |> where([s], s.student_id == ^user.id and s.task_id in ^task_ids)
      |> preload(:task)
      |> Repo.all()
      |> Map.new(&{&1.task_id, &1})

    # Return in task position order; locked tasks without a submission get a virtual placeholder
    tasks
    |> Enum.map(fn task ->
      case Map.get(submissions_by_task, task.id) do
        nil when task.locked ->
          # Return a virtual submission struct so the UI can render "Bald verfügbar"
          %TaskSubmission{
            task_id: task.id,
            task: task,
            status: "not_started",
            student_id: user.id
          }

        nil ->
          nil

        submission ->
          submission
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
    # Gate checks and the write run in one transaction against a row locked FOR
    # UPDATE, so the completion can't slip past concurrently-changed state
    # (TOCTOU on the upload check). The `:task` preload stays unlocked — no
    # guard below reads a `tasks` column.
    result =
      Repo.transaction(fn ->
        submission = Repo.lock_one!(TaskSubmission, submission_id) |> Repo.preload(:task)

        cond do
          submission.student_id != user.id ->
            Repo.rollback(:unauthorized)

          submission.status not in @editable_statuses ->
            Repo.rollback(:not_editable)

          missing_required_uploads(submission) != [] ->
            Repo.rollback(:missing_uploads)

          true ->
            case submission |> TaskSubmission.complete_changeset() |> Repo.update() do
              {:ok, updated} -> %{updated | task: submission.task}
              {:error, changeset} -> Repo.rollback(changeset)
            end
        end
      end)

    with {:ok, updated} <- result do
      broadcast_submission_updated(updated, updated.task.course_id)
      {:ok, updated}
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
      submission = Repo.get!(TaskSubmission, submission_id) |> Repo.preload(:task)

      case submission
           |> TaskSubmission.grade_changeset(attrs, user.id)
           |> Repo.update() do
        {:ok, updated_submission} = result ->
          Phoenix.PubSub.broadcast(
            Tasky.PubSub,
            "student:#{submission.student_id}:submissions",
            {:submission_updated, updated_submission}
          )

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

  @doc """
  Returns a map of %{student_id => %{status, has_content}} for all
  given students on a single task. Used by the task progress LiveView.
  """
  def get_progress_map_for_task(task_id, student_ids) do
    submissions =
      Repo.all(
        from s in TaskSubmission,
          where: s.student_id in ^student_ids and s.task_id == ^task_id,
          select: %{
            student_id: s.student_id,
            status: s.status,
            has_content: not is_nil(s.content)
          }
      )

    Enum.reduce(submissions, %{}, fn submission, acc ->
      Map.put(acc, submission.student_id, %{
        status: submission.status,
        has_content: submission.has_content
      })
    end)
  end

  @doc """
  Gets a task preloaded with its associated course. Used by progress views
  that need the course_id without raw Repo access in LiveViews.
  """
  def get_task_with_course!(%Scope{} = scope, task_id) do
    task = get_task!(scope, task_id)
    Repo.preload(task, :course)
  end

  @doc """
  Returns the submission record for a given student and task, or nil if none exists.
  Avoids raw Repo.get_by calls in LiveViews.
  """
  def get_submission_for_student(task_id, student_id) do
    Repo.get_by(TaskSubmission, task_id: task_id, student_id: student_id)
  end

  @doc """
  Gets a single submission of the given task, or nil. Authorization rides on
  the task: callers fetch it via `get_task!/2` first.
  """
  def get_submission(%Task{} = task, id) do
    Repo.get_by(TaskSubmission, id: id, task_id: task.id)
  end

  @doc """
  Gets a task by id for a student, or `nil` when the task does not exist or
  the student is not enrolled in the task's course. This is the single entry
  point for student-facing task access — enrollment is checked here, not in
  the callers.
  """
  def get_task_for_student(%Scope{user: user} = _scope, task_id)
      when user.role == "student" do
    with %Task{} = task <- Repo.get(Task, task_id),
         true <- Tasky.Courses.enrolled?(task.course_id, user.id) do
      task
    else
      _ -> nil
    end
  end

  @doc "True while the student may still edit answers / upload files / complete."
  def editable_submission?(%TaskSubmission{status: status}),
    do: status in @editable_statuses

  ## Learning-unit content (Tiptap)

  @doc """
  Saves the learning unit's Tiptap content doc from the authoring editor.
  Assigns stable `answerId`s to all answer-bearing nodes (see
  `Tasky.Correction.AnswerKey`). Only the owning teacher may save.
  """
  def save_task_content(%Scope{} = scope, %Task{} = task, doc) when is_map(doc) do
    with :ok <- Policy.authorize(scope, task.user_id),
         {:ok, task = %Task{}} <-
           task
           |> Task.content_changeset(AnswerKey.ensure_ids(doc))
           |> Repo.update() do
      broadcast_task(scope, {:updated, task})
      {:ok, task}
    end
  end

  @doc """
  Saves the student's answer doc for their own submission. Rejected once the
  submission is completed or approved; allowed again after a teacher sends it
  back (`review_denied`).
  """
  def save_student_answers(%Scope{user: user} = _scope, %TaskSubmission{} = submission, doc)
      when user.role == "student" and is_map(doc) do
    cond do
      submission.student_id != user.id ->
        {:error, :unauthorized}

      submission.status not in @editable_statuses ->
        {:error, :not_editable}

      true ->
        submission
        |> TaskSubmission.answers_changeset(doc)
        |> Repo.update()
    end
  end

  @doc """
  Sets a teacher's review verdict on a completed submission and saves the
  feedback in one go. `verdict` is `"review_approved"` or `"review_denied"`;
  a denied submission becomes editable for the student again.
  """
  def review_submission(%Scope{user: user} = scope, submission_id, verdict, attrs \\ %{})
      when verdict in ["review_approved", "review_denied"] do
    if Scope.admin_or_teacher?(scope) do
      submission = Repo.get!(TaskSubmission, submission_id) |> Repo.preload(:task)

      case submission
           |> TaskSubmission.grade_changeset(attrs, user.id)
           |> Ecto.Changeset.put_change(:status, verdict)
           |> Repo.update() do
        {:ok, updated_submission} = result ->
          broadcast_submission_updated(updated_submission, submission.task.course_id)
          result

        error ->
          error
      end
    else
      {:error, :unauthorized}
    end
  end

  ## Attachments (teacher-provided files)

  @doc "Lists a task's attachments in display order."
  def list_task_attachments(%Task{} = task) do
    Repo.all(
      from a in TaskAttachment,
        where: a.task_id == ^task.id,
        order_by: [asc: a.position, asc: a.id]
    )
  end

  @doc "Gets an attachment of the given task, or nil."
  def get_task_attachment(%Task{} = task, id) do
    Repo.get_by(TaskAttachment, id: id, task_id: task.id)
  end

  @doc "Gets an attachment by its stored (UUID) filename, or nil."
  def get_task_attachment_by_stored_filename(task_id, stored_filename) do
    Repo.get_by(TaskAttachment, task_id: task_id, stored_filename: stored_filename)
  end

  @doc """
  Creates an attachment record for a file already stored on disk (see
  `Tasky.Uploads.save_task_attachment/3`).
  """
  def create_task_attachment(%Task{} = task, attrs) do
    position =
      Repo.one(
        from a in TaskAttachment,
          where: a.task_id == ^task.id,
          select: coalesce(max(a.position), -1)
      ) + 1

    %TaskAttachment{task_id: task.id}
    |> TaskAttachment.changeset(Map.put(attrs, :position, position))
    |> Repo.insert()
  end

  @doc "Deletes an attachment record and its file on disk."
  def delete_task_attachment(%TaskAttachment{} = attachment) do
    with {:ok, deleted} <- Repo.delete(attachment) do
      Tasky.Uploads.delete_task_attachment_file(deleted.task_id, deleted.stored_filename)
      {:ok, deleted}
    end
  end

  ## Upload fields (student file-answer slots)

  @doc "Lists a task's upload fields in display order."
  def list_task_upload_fields(%Task{} = task), do: list_upload_fields_by_task_id(task.id)

  defp list_upload_fields_by_task_id(task_id) do
    Repo.all(
      from f in TaskUploadField,
        where: f.task_id == ^task_id,
        order_by: [asc: f.position, asc: f.id]
    )
  end

  @doc "Gets an upload field of the given task, or nil."
  def get_task_upload_field(%Task{} = task, id) do
    Repo.get_by(TaskUploadField, id: id, task_id: task.id)
  end

  @doc "Creates an upload field, appended at the end."
  def create_task_upload_field(%Task{} = task, attrs) do
    position =
      Repo.one(
        from f in TaskUploadField,
          where: f.task_id == ^task.id,
          select: coalesce(max(f.position), -1)
      ) + 1

    %TaskUploadField{task_id: task.id}
    |> TaskUploadField.changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  @doc "Updates an upload field."
  def update_task_upload_field(%TaskUploadField{} = field, attrs) do
    field
    |> TaskUploadField.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an upload field including all student files uploaded into it
  (records via FK cascade, bytes on disk explicitly).
  """
  def delete_task_upload_field(%TaskUploadField{} = field) do
    files =
      Repo.all(
        from sf in TaskSubmissionFile,
          where: sf.upload_field_id == ^field.id,
          join: s in assoc(sf, :task_submission),
          select: {s.task_id, sf.task_submission_id, sf.stored_filename}
      )

    with {:ok, deleted} <- Repo.delete(field) do
      Enum.each(files, fn {task_id, submission_id, stored} ->
        Tasky.Uploads.delete_task_submission_file_from_disk(task_id, submission_id, stored)
      end)

      {:ok, deleted}
    end
  end

  @doc "True when the task has attachments or upload fields (student files section visibility)."
  def task_has_files?(%Task{} = task) do
    Repo.exists?(from a in TaskAttachment, where: a.task_id == ^task.id) or
      Repo.exists?(from f in TaskUploadField, where: f.task_id == ^task.id)
  end

  ## Student answer files

  @doc "Lists a submission's uploaded files."
  def list_submission_files(%TaskSubmission{} = submission) do
    Repo.all(from sf in TaskSubmissionFile, where: sf.task_submission_id == ^submission.id)
  end

  @doc "Gets a submission's file for one upload field, or nil."
  def get_submission_file(%TaskSubmission{} = submission, field_id) do
    Repo.get_by(TaskSubmissionFile,
      task_submission_id: submission.id,
      upload_field_id: field_id
    )
  end

  @doc "Gets a file of the given submission by its id, or nil."
  def get_submission_file_by_id(%TaskSubmission{} = submission, file_id) do
    Repo.get_by(TaskSubmissionFile, id: file_id, task_submission_id: submission.id)
  end

  @doc """
  Stores/replaces the answer file of one upload field for a submission whose
  bytes are already on disk. A previously uploaded file for the same field is
  replaced and its bytes removed.
  """
  def put_submission_file(%TaskSubmission{} = submission, %TaskUploadField{} = field, attrs) do
    result =
      Repo.transaction(fn ->
        lock_for_file_change!(submission)
        old = get_submission_file(submission, field.id)

        changeset =
          case old do
            nil ->
              %TaskSubmissionFile{task_submission_id: submission.id, upload_field_id: field.id}
              |> TaskSubmissionFile.changeset(attrs)

            existing ->
              TaskSubmissionFile.changeset(existing, attrs)
          end

        case Repo.insert_or_update(changeset) do
          {:ok, file} -> {file, old}
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    # Bytes are removed only once the record change has committed, so a rolled
    # back transaction can't leave the DB pointing at a file that is gone.
    with {:ok, {file, old}} <- result do
      if old, do: delete_submission_file_bytes(submission, old.stored_filename)
      {:ok, file}
    end
  end

  @doc "Deletes a submission's answer file (record + bytes)."
  def delete_submission_file(%TaskSubmission{} = submission, %TaskSubmissionFile{} = file) do
    result =
      Repo.transaction(fn ->
        lock_for_file_change!(submission)

        case Repo.delete(file) do
          {:ok, deleted} -> deleted
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    with {:ok, deleted} <- result do
      delete_submission_file_bytes(submission, deleted.stored_filename)
      {:ok, deleted}
    end
  end

  # `complete_task/2` locks the submission row and then counts this submission's
  # files to gate completion. Locking the same row before every file change makes
  # the two mutually exclusive; without it a required file could be replaced or
  # deleted between that count and the completion write, since a row lock on the
  # submission does not pin rows in task_submission_files.
  defp lock_for_file_change!(%TaskSubmission{} = submission) do
    Repo.lock_one!(TaskSubmission, submission.id)
  end

  defp delete_submission_file_bytes(submission, stored_filename) do
    Tasky.Uploads.delete_task_submission_file_from_disk(
      submission.task_id,
      submission.id,
      stored_filename
    )
  end

  @doc """
  Required upload fields of the submission's task that have no file yet.
  Used to gate the "mark as complete" action.
  """
  def missing_required_uploads(%TaskSubmission{} = submission) do
    uploaded_ids =
      Repo.all(
        from sf in TaskSubmissionFile,
          where: sf.task_submission_id == ^submission.id,
          select: sf.upload_field_id
      )

    submission.task_id
    |> list_upload_fields_by_task_id()
    |> Enum.filter(&(&1.required and &1.id not in uploaded_ids))
  end

  # Broadcasts a submission change to the student's own view and the
  # teacher-facing course progress views.
  defp broadcast_submission_updated(%TaskSubmission{} = submission, course_id) do
    Phoenix.PubSub.broadcast(
      Tasky.PubSub,
      "student:#{submission.student_id}:submissions",
      {:submission_updated, submission}
    )

    Phoenix.PubSub.broadcast(
      Tasky.PubSub,
      "course:#{course_id}:progress",
      {:submission_updated, submission}
    )
  end
end
