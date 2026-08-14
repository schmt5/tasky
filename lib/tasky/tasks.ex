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
  alias Tasky.Tasks.TaskSolutionFile
  alias Tasky.Tasks.TaskSubmission
  alias Tasky.Tasks.TaskSubmissionFile
  alias Tasky.Tasks.TaskUploadField

  # Submission statuses in which the student may still edit answers,
  # upload files and mark the unit as complete.
  @editable_statuses ~w(not_started in_progress in_revision review_denied)

  # Statuses a teacher may put a verdict on: eingereicht, in Überarbeitung
  # (Verdikt korrigieren) oder schon einmal reviewt.
  @reviewable_statuses ~w(completed in_revision review_approved review_denied)

  # Statuses that count as "done" for the student's course progress. A unit
  # handed in counts even before the teacher has approved it.
  @completed_statuses ~w(completed review_approved)

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
  Lists a course's learning units in display order with everything the public
  Markdown export needs preloaded (see `Tasky.Courses.CourseExport`).
  """
  def list_tasks_for_export(course_id) do
    attachments = from a in TaskAttachment, order_by: [asc: a.position, asc: a.id]
    upload_fields = from f in TaskUploadField, order_by: [asc: f.position, asc: f.id]

    Task
    |> where([t], t.course_id == ^course_id)
    |> order_by([t], asc: t.position, asc: t.id)
    |> Repo.all()
    |> Repo.preload(attachments: attachments, upload_fields: upload_fields)
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

  Writes records only. The file copies are *planned*, not performed, and come
  back as the third element for the caller to run once the surrounding
  transaction has committed (see `Tasky.Courses.duplicate_course/3`) — which
  is what makes this function safe to call inside one.

  ## Options

    * `:source_authorized` — skips the ownership check on the source unit. Set
      only by `Tasky.Courses.import_catalog_course_records/3`, never from the
      web layer; see `authorize_duplicate_source/3`.
    * `:reset_release_state` — writes the copy as an unpublished, unlocked
      draft instead of carrying the source's release state over.

  ## Examples

      iex> duplicate_task_into_course(scope, task, course.id)
      {:ok, %Task{}, [%{src: "tasks/1/a.png", dest: "tasks/2/a.png"}]}

  """
  def duplicate_task_into_course(%Scope{} = scope, %Task{} = source, course_id, opts \\ []) do
    with :ok <- authorize_duplicate_source(scope, source, opts),
         {:ok, task} <- create_task(scope, duplicate_attrs(source, course_id, opts)),
         {:ok, task, image_jobs} <- copy_task_content(task, source),
         {:ok, attachment_jobs} <- copy_task_attachments(scope, task, source),
         {:ok, solution_jobs} <- copy_task_solution_files(scope, task, source),
         :ok <- copy_task_upload_fields(scope, task, source) do
      {:ok, task, image_jobs ++ attachment_jobs ++ solution_jobs}
    end
  end

  # Der Katalog-Import kann die Besitzprüfung hier nicht bestehen — die Quelle
  # gehört per Definition einer anderen Lehrperson. Die Berechtigung ist dort
  # geklärt, wo sie hingehört: `Tasky.Courses.import_catalog_course_records/3`
  # liest die Quelle frisch und prüft `catalog_published_at`. Diese Option
  # setzt ausschliesslich `Tasky.Courses` — nie die Web-Schicht.
  defp authorize_duplicate_source(scope, source, opts) do
    if Keyword.get(opts, :source_authorized, false),
      do: :ok,
      else: Policy.authorize(scope, source.user_id)
  end

  # `reset_release_state`: status, locked und der Freigabe-Modus der
  # Musterlösung sind Freigabe-Zustände für die Klasse der Autorin in ihrem
  # Semester, nicht Teil des Inhalts. Beim Katalog-Import startet jede Einheit
  # darum als unveröffentlichter, offener Entwurf mit ausgeblendeter
  # Musterlösung; die importierende Lehrperson gibt selbst frei. `extended`
  # bleibt: ein freiwilliger Zusatzauftrag ist eine inhaltliche Eigenschaft,
  # keine Freigabe.
  defp duplicate_attrs(source, course_id, opts) do
    base = %{
      name: source.name,
      position: source.position,
      extended: source.extended,
      course_id: course_id
    }

    if Keyword.get(opts, :reset_release_state, false) do
      Map.merge(base, %{status: "draft", locked: false, solution_release_mode: "never"})
    else
      Map.merge(base, %{
        status: source.status,
        locked: source.locked,
        solution_release_mode: source.solution_release_mode
      })
    end
  end

  # Die Musterlösung reist hier mit, weil `Task.changeset/3` die JSON-Spalte
  # bewusst nicht castet. Die Antwortmap läuft ebenfalls durch
  # `plan_content_image_copies/4`: klebt ein Screenshot in einem Antwortfeld,
  # zeigt seine URL sonst auf das Präfix der Quelleinheit und läuft ins Leere,
  # sobald die Quelle gelöscht wird.
  defp copy_task_content(task, %Task{} = source) do
    {content, content_jobs} =
      Tasky.Uploads.plan_content_image_copies(source.content || %{}, :tasks, source.id, task.id)

    {answers, answer_jobs} =
      Tasky.Uploads.plan_content_image_copies(
        source.sample_solution || %{},
        :tasks,
        source.id,
        task.id
      )

    with {:ok, task} <-
           task
           |> Task.content_changeset(content)
           |> Ecto.Changeset.put_change(:sample_solution, answers)
           |> Repo.update() do
      {:ok, task, content_jobs ++ answer_jobs}
    end
  end

  defp copy_task_attachments(scope, task, source) do
    source
    |> list_task_attachments()
    |> Enum.reduce_while({:ok, []}, fn attachment, {:ok, jobs} ->
      with {:ok, stored_filename, job} <-
             Tasky.Uploads.plan_attachment_copy(
               :tasks,
               source.id,
               task.id,
               attachment.stored_filename
             ),
           {:ok, _attachment} <-
             create_task_attachment(scope, task, %{
               stored_filename: stored_filename,
               original_name: attachment.original_name,
               content_type: attachment.content_type,
               size: attachment.size
             }) do
        {:cont, {:ok, [job | jobs]}}
      else
        # A stored filename we cannot build a safe storage key from is the one
        # case worth skipping outright — there is nothing to point a record at.
        {:error, :invalid} ->
          {:cont, {:ok, jobs}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, jobs} -> {:ok, Enum.reverse(jobs)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Lösungsdateien sind Inhalt und reisen auch beim Katalog-Import mit — nur
  # der Zeitpunkt ihrer Freigabe tut das nicht.
  defp copy_task_solution_files(scope, task, source) do
    source
    |> list_task_solution_files()
    |> Enum.reduce_while({:ok, []}, fn file, {:ok, jobs} ->
      with {:ok, stored_filename, job} <-
             Tasky.Uploads.plan_solution_file_copy(source.id, task.id, file.stored_filename),
           {:ok, _file} <-
             create_task_solution_file(scope, task, %{
               stored_filename: stored_filename,
               original_name: file.original_name,
               content_type: file.content_type,
               size: file.size
             }) do
        {:cont, {:ok, [job | jobs]}}
      else
        # Wie bei den Anhängen: aus einem unsicheren Dateinamen lässt sich
        # kein Storage-Key bauen, also gibt es nichts, worauf ein Datensatz
        # zeigen könnte.
        {:error, :invalid} -> {:cont, {:ok, jobs}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, jobs} -> {:ok, Enum.reverse(jobs)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp copy_task_upload_fields(scope, task, source) do
    source
    |> list_task_upload_fields()
    |> Enum.reduce_while(:ok, fn field, _acc ->
      case create_task_upload_field(scope, task, %{
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
  Returns an `%Ecto.Changeset{}` for a learning unit that does not exist yet.

  `change_task/3` cannot be used here: an unsaved `%Task{}` has no `user_id`,
  so the ownership check would reject the very teacher who is creating it.

  ## Examples

      iex> change_new_task(scope, %{"name" => "Kapitel 1"})
      %Ecto.Changeset{data: %Task{}}

  """
  def change_new_task(%Scope{} = scope, attrs \\ %{}) do
    Task.changeset(%Task{}, attrs, scope)
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
  Derives a student's course progress from the submissions of
  `list_course_submissions/2` (their `:task` must be preloaded).

  The percentage counts **mandatory units only** — an "erweiterte Lerneinheit"
  is a voluntary extra, so 100 % stays reachable without doing a single one.
  Completed extensions are reported separately instead.

  A course made up of nothing but extensions has no mandatory work left to do,
  so it reports 100 % with `no_mandatory?: true`; the caller words the label
  differently rather than dividing by zero.

  ## Examples

      iex> course_progress(submissions)
      %{total: 8, completed: 6, percent: 75, ...}

  """
  def course_progress(submissions) do
    {extended, mandatory} = Enum.split_with(submissions, & &1.task.extended)
    done = fn list -> Enum.count(list, &(&1.status in @completed_statuses)) end

    total = length(mandatory)
    completed = done.(mandatory)
    extended_total = length(extended)
    extended_completed = done.(extended)

    %{
      total: total,
      completed: completed,
      percent: if(total == 0, do: 100, else: round(completed / total * 100)),
      graded: Enum.count(submissions, &(&1.status == "review_approved")),
      extended_total: extended_total,
      extended_completed: extended_completed,
      no_mandatory?: total == 0
    }
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
      |> preload([:student, :feedback_by])
      |> order_by([s], asc: s.status, desc: s.updated_at)
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Updates the status of a task submission.

  Students can only update their own submissions, and only to a status they may
  reach by working on the unit — `complete_task/2` and `review_submission/4`
  own all other transitions.

  ## Examples

      iex> update_submission_status(scope, submission_id, "in_progress")
      {:ok, %TaskSubmission{}}

  """
  def update_submission_status(%Scope{user: user} = _scope, submission_id, status)
      when user.role == "student" and status in ["in_progress", "in_revision"] do
    submission = Repo.get!(TaskSubmission, submission_id) |> Repo.preload(:task)

    if submission.student_id == user.id do
      with {:ok, updated} <-
             submission
             |> TaskSubmission.status_changeset(%{status: status})
             |> Repo.update() do
        broadcast_submission_updated(updated, submission.task.course_id)
        {:ok, updated}
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
  Saves a teacher's feedback text on a submission without changing its status.
  Only the teacher owning the learning unit (or an admin) may do so.

  ## Examples

      iex> save_feedback(scope, submission_id, %{feedback: "Great work!"})
      {:ok, %TaskSubmission{}}

  """
  def save_feedback(%Scope{user: user} = scope, submission_id, attrs) do
    submission = Repo.get!(TaskSubmission, submission_id) |> Repo.preload(:task)

    with :ok <- Policy.authorize(scope, submission.task.user_id),
         {:ok, updated} <-
           submission
           |> TaskSubmission.feedback_changeset(attrs, user.id)
           |> Repo.update() do
      broadcast_submission_updated(updated, submission.task.course_id)
      {:ok, updated}
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
      |> preload([:task, :student, :feedback_by])
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
  Returns a map of `%{student_id => entry}` for all given students on a single
  task, where each entry carries the submission id, its status, whether there
  is content, and the two fields `solution_visible_for_entry?/2` needs. Used by
  the task progress LiveView.
  """
  def get_progress_map_for_task(task_id, student_ids) do
    Repo.all(
      from s in TaskSubmission,
        where: s.student_id in ^student_ids and s.task_id == ^task_id,
        select: %{
          student_id: s.student_id,
          submission_id: s.id,
          status: s.status,
          has_content: not is_nil(s.content),
          completed_at: s.completed_at,
          solution_released_at: s.solution_released_at
        }
    )
    |> Map.new(&{&1.student_id, Map.delete(&1, :student_id)})
  end

  @doc """
  `solution_visible?/2` für einen Eintrag aus `get_progress_map_for_task/2`.

  Existiert, damit die Fortschrittsansicht das Prädikat nicht nachbaut — es
  gibt genau eine Wahrheit darüber, wer die Lösung sehen darf.
  """
  def solution_visible_for_entry?(%Task{} = task, %{} = entry) do
    solution_visible?(task, %TaskSubmission{
      solution_released_at: entry.solution_released_at,
      completed_at: entry.completed_at
    })
  end

  def solution_visible_for_entry?(%Task{}, nil), do: false

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
  Gets a task by id for a student, or `nil` when the task does not exist, is
  not published, or the student is not enrolled in the task's course. This is
  the single entry point for student-facing task access — enrollment and
  visibility are checked here, not in the callers.

  The `status` check belongs here and not only in `list_tasks_for_course/1`:
  task ids are sequential, so without it any enrolled student could open a
  draft or archived unit of their course by URL, answer it, and reach its
  solution files.
  """
  def get_task_for_student(%Scope{user: user} = _scope, task_id)
      when user.role == "student" do
    with %Task{status: "published"} = task <- Repo.get(Task, task_id),
         true <- Tasky.Courses.enrolled?(task.course_id, user.id) do
      task
    else
      _ -> nil
    end
  end

  @doc "Maximale Länge des Feedbacktexts (auch fürs `maxlength` im Formular)."
  defdelegate max_feedback_chars(), to: TaskSubmission

  @doc """
  True when the submission carries a teacher's feedback text.

  Die einzige Quelle für den Feedback-Hinweis der Lernenden — an einem
  Zeitstempel allein darf er nicht hängen, sonst zeigt er auf leeren Text.
  """
  def has_feedback?(%TaskSubmission{feedback: feedback}),
    do: is_binary(feedback) and String.trim(feedback) != ""

  def has_feedback?(nil), do: false

  @doc "True while the student may still edit answers / upload files / complete."
  def editable_submission?(%TaskSubmission{status: status}),
    do: status in @editable_statuses

  @doc """
  Status, in den eine Einheit wechselt, wenn der Lernende sie öffnet.

  Eine zurückgegebene Einheit geht nach `in_revision`, damit die Lehrperson im
  Fortschritt sieht, dass die Rückgabe angekommen ist. `nil` heisst: Status
  bleibt, wie er ist.
  """
  def resume_status(%TaskSubmission{status: "not_started"}), do: "in_progress"
  def resume_status(%TaskSubmission{status: "review_denied"}), do: "in_revision"
  def resume_status(%TaskSubmission{}), do: nil

  ## Learning-unit content (Tiptap)

  @doc """
  Saves the learning unit's Tiptap content doc from the authoring editor.
  Assigns stable `answerId`s to all answer-bearing nodes (see
  `Tasky.Correction.AnswerKey`). Only the owning teacher may save.

  Entfernt die Lehrperson im Inhalt ein Antwortfeld, verliert der zugehörige
  Eintrag in `sample_solution` seinen Anker — er wird hier mit gepruned, sonst
  bleibt er für immer als Waise liegen. Weil das ein Read-Modify-Write über
  beide Spalten ist, läuft es gegen die gesperrte Zeile (ein gleichzeitiger
  Speichervorgang im Musterlösungs-Tab würde sich sonst damit überschreiben).
  """
  def save_task_content(%Scope{} = scope, %Task{} = task, doc) when is_map(doc) do
    with :ok <- Policy.authorize(scope, task.user_id) do
      new_content = AnswerKey.ensure_ids(doc)

      result =
        Repo.transaction(fn ->
          locked = Repo.lock_one!(Task, task.id)
          pruned = prune_orphan_answers(new_content, locked.sample_solution || %{})

          locked
          |> Task.content_changeset(new_content)
          |> Ecto.Changeset.put_change(:sample_solution, pruned)
          |> Repo.update()
          |> case do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      with {:ok, updated} <- result do
        broadcast_task(scope, {:updated, updated})
        {:ok, updated}
      end
    end
  end

  ## Musterlösung

  @doc """
  Die Musterlösung als vollständiges, antwortgefülltes Dokument — das, was der
  Musterlösungs-Editor lädt und Lernende nach der Freigabe zu sehen bekommen.
  """
  def sample_solution_doc(%Task{} = task),
    do: AnswerKey.merge(task.content || %{}, task.sample_solution || %{})

  @doc """
  Speichert die Musterlösung aus dem Musterlösungs-Tab.

  `doc` ist das ganze antwortgefüllte Dokument. Wir splitten es und behalten
  nur die Antworten: `content` wird hier bewusst nicht geschrieben. Der Editor
  läuft mit gesperrtem Inhalt, das Skelett kann sich also gar nicht ändern —
  und der Musterlösungs-Tab darf unter keinen Umständen das Dokument
  überschreiben, an dem die Lernenden arbeiten.

  Ersetzen statt Mergen ist hier richtig: es gibt genau einen Editor, der das
  ganze Dokument hält. Ein Merge würde Antworten wieder auferstehen lassen,
  die die Lehrperson gerade gelöscht hat.
  """
  def save_sample_solution(%Scope{} = scope, %Task{} = task, doc) when is_map(doc) do
    with :ok <- Policy.authorize(scope, task.user_id) do
      {_blanked, answers} = AnswerKey.split(doc)

      result =
        Repo.transaction(fn ->
          locked = Repo.lock_one!(Task, task.id)
          pruned = prune_orphan_answers(locked.content || %{}, answers)

          case locked |> Task.sample_solution_changeset(pruned) |> Repo.update() do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      with {:ok, updated} <- result do
        broadcast_task(scope, {:updated, updated})
        {:ok, updated}
      end
    end
  end

  # Antworten ohne Anker im Inhalt fliegen raus — sonst wächst die Map mit
  # jedem gelöschten Antwortfeld weiter.
  defp prune_orphan_answers(content, answers) do
    Map.take(answers, MapSet.to_list(AnswerKey.block_ids(content)))
  end

  @doc "Anzahl Antwortfelder im Inhalt — steuert den Leerzustand des Musterlösungs-Tabs."
  def answer_block_count(%Task{} = task),
    do: task.content |> Kernel.||(%{}) |> AnswerKey.block_ids() |> MapSet.size()

  ## Freigabe von Musterlösung und Korrektur

  @doc "Die gültigen Freigabe-Modi (`never` | `manual` | `on_complete`)."
  defdelegate release_modes(), to: Task

  # Gesetzt wird der Modus über `update_task/3` — er ist ein Feld des
  # Lerneinheit-Formulars wie `name` oder `extended`. Ein zweiter Setter hier
  # wäre ein zweiter Schreibpfad auf dasselbe Feld.

  @doc """
  Darf dieser Lernende Musterlösung und Korrektur dieser Lerneinheit sehen?

  Genau ein Tor für beides, und die einzige Stelle, an der die Frage
  beantwortet wird — LiveViews, Controller und die Fortschrittsansicht rufen
  alle hier an.

  Zwei bewusste Eigenschaften:

    * `never` ist ein harter Riegel und überstimmt auch eine bereits erteilte
      Einzelfreigabe. Damit hat die Lehrperson einen Not-Aus, ohne dass wir
      Freigaben löschen müssen.
    * `on_complete` wird an `completed_at` gelesen, nicht beim Abschliessen
      gestempelt. `completed_at` wird nie wieder geräumt (auch
      `review_submission/4` fasst es nicht an), heisst also dauerhaft "hat
      mindestens einmal eingereicht" — genau die Klebrigkeit, die "Freigabe
      bleibt bestehen" verlangt, ohne einen zweiten Schreibpfad.
  """
  def solution_visible?(%Task{solution_release_mode: "never"}, _submission), do: false
  def solution_visible?(%Task{}, nil), do: false
  def solution_visible?(%Task{}, %TaskSubmission{solution_released_at: %DateTime{}}), do: true

  def solution_visible?(%Task{solution_release_mode: "on_complete"}, %TaskSubmission{
        completed_at: %DateTime{}
      }),
      do: true

  def solution_visible?(%Task{}, %TaskSubmission{}), do: false

  @doc """
  Gibt Musterlösung und Korrektur für einen einzelnen Lernenden frei.

  Idempotent: eine bestehende Freigabe wird nicht neu gestempelt, der
  Zeitstempel ist das Datum der *ersten* Freigabe.
  """
  def release_solution(%Scope{} = scope, %Task{} = task, submission_id) do
    with :ok <- Policy.authorize(scope, task.user_id) do
      result =
        Repo.transaction(fn ->
          locked = Repo.lock_one!(TaskSubmission, submission_id)
          if locked.task_id != task.id, do: Repo.rollback(:not_found)
          stamp_release!(locked)
        end)

      with {:ok, updated} <- result do
        broadcast_submission_updated(updated, task.course_id)
        {:ok, updated}
      end
    end
  end

  @doc """
  Gibt Musterlösung und Korrektur für viele Lernende einer Lerneinheit frei.

  `target` ist `:all` oder eine Liste von Submission-Ids. Alles läuft in einer
  Transaktion; die Sperrreihenfolge folgt ARCHITECTURE.md: erst `tasks`, dann
  `task_submissions` aufsteigend nach `id` (das `order_by` ist tragend — ohne
  es können zwei überlappende Bulk-Freigaben verklemmen).

  Auf `tasks` bewusst FOR SHARE statt FOR UPDATE: jedes Öffnen einer
  Lerneinheit fügt über `get_or_create_submission/2` eine Zeile ein und nimmt
  dabei FOR KEY SHARE auf die Elternzeile. FOR UPDATE würde die ganze Klasse
  blockieren, solange die Lehrperson freigibt.

  Wie die Einzelfreigabe idempotent: bereits freigegebene Abgaben behalten
  ihren ursprünglichen Zeitstempel.
  """
  def release_solution_bulk(%Scope{} = scope, %Task{} = task, target \\ :all) do
    with :ok <- Policy.authorize(scope, task.user_id) do
      result =
        Repo.transaction(fn ->
          _guard = Repo.lock_one!(Task, task.id, :share)

          # Only newly stamped rows count. `stamp_release!/1` returns an
          # already-released submission unchanged, so returning every locked row
          # made a second "Für alle freigeben" click report the full class as
          # freshly released when it had released nobody.
          task
          |> lock_task_submissions!(target)
          |> Enum.reject(&released?/1)
          |> Enum.map(&stamp_release!/1)
        end)

      with {:ok, updated} <- result do
        Enum.each(updated, &broadcast_submission_updated(&1, task.course_id))
        {:ok, updated}
      end
    end
  end

  defp released?(%TaskSubmission{solution_released_at: %DateTime{}}), do: true
  defp released?(%TaskSubmission{}), do: false

  defp lock_task_submissions!(%Task{} = task, :all) do
    ensure_submissions_for_enrolled!(task)

    Repo.all(
      from s in TaskSubmission,
        where: s.task_id == ^task.id,
        order_by: [asc: s.id],
        lock: "FOR UPDATE"
    )
  end

  defp lock_task_submissions!(%Task{} = task, ids) when is_list(ids) do
    Repo.all(
      from s in TaskSubmission,
        where: s.task_id == ^task.id and s.id in ^ids,
        order_by: [asc: s.id],
        lock: "FOR UPDATE"
    )
  end

  # "Für alle freigeben" heisst: für alle eingeschriebenen Lernenden — auch für
  # die, welche die Lerneinheit noch nie geöffnet haben. Deren Abgabezeile
  # entsteht sonst erst beim Öffnen (`get_or_create_submission/2`), und die
  # Freigabe würde sie schlicht verfehlen: die Lehrperson bekäme eine
  # Erfolgsmeldung, und die Lösung bliebe unsichtbar.
  #
  # Der Insert nimmt FOR KEY SHARE auf die `tasks`-Zeile, die wir hier schon
  # FOR SHARE halten — das verträgt sich.
  defp ensure_submissions_for_enrolled!(%Task{} = task) do
    existing =
      Repo.all(from s in TaskSubmission, where: s.task_id == ^task.id, select: s.student_id)

    missing =
      task.course_id
      |> Tasky.Courses.list_enrolled_students()
      |> Enum.map(& &1.id)
      |> Kernel.--(existing)

    now = DateTime.utc_now(:second)

    rows =
      Enum.map(missing, fn student_id ->
        %{
          task_id: task.id,
          student_id: student_id,
          status: "not_started",
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(TaskSubmission, rows, on_conflict: :nothing)
  end

  # Überschreibt nie einen bestehenden Zeitstempel: hier — und nur hier —
  # steckt die Regel "eine erteilte Freigabe bleibt bestehen".
  defp stamp_release!(%TaskSubmission{solution_released_at: %DateTime{}} = submission),
    do: submission

  defp stamp_release!(%TaskSubmission{} = submission) do
    submission
    |> Ecto.Changeset.change(solution_released_at: DateTime.utc_now(:second))
    |> Repo.update()
    |> case do
      {:ok, updated} -> updated
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Saves the student's answer doc for their own submission. Rejected once the
  submission is completed or approved; allowed again after a teacher sends it
  back (`review_denied`).
  """
  def save_student_answers(%Scope{user: user} = _scope, %TaskSubmission{} = submission, doc)
      when user.role == "student" and is_map(doc) do
    # Gate and write run in one transaction against the locked row, exactly as
    # `Exams.update_exam_submission_content/2` does on the other surface.
    # Checking `status` on the caller's struct (read unlocked by the controller)
    # and then issuing an UPDATE without a status predicate let an autosave that
    # was already in flight land *after* `complete_task/2` committed — the
    # student's answers changed after hand-in, and after teacher approval.
    # `Repo.transaction/1` already yields {:ok, submission} or {:error, reason},
    # with a rolled-back changeset coming back as {:error, changeset} — the
    # caller's contract is unchanged.
    Repo.transaction(fn ->
      locked = Repo.lock_one!(TaskSubmission, submission.id)

      cond do
        locked.student_id != user.id ->
          Repo.rollback(:unauthorized)

        locked.status not in @editable_statuses ->
          Repo.rollback(:not_editable)

        true ->
          case locked |> TaskSubmission.answers_changeset(doc) |> Repo.update() do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  @doc """
  Sets a teacher's review verdict on a submitted submission and saves the
  feedback in one go. `verdict` is `"review_approved"` or `"review_denied"`;
  a denied submission becomes editable for the student again.

  Only the teacher owning the learning unit (or an admin) may review, and only
  a submission the student has actually handed in.
  """
  def review_submission(%Scope{user: user} = scope, submission_id, verdict, attrs \\ %{})
      when verdict in ["review_approved", "review_denied"] do
    submission = Repo.get!(TaskSubmission, submission_id) |> Repo.preload(:task)

    with :ok <- Policy.authorize(scope, submission.task.user_id),
         :ok <- ensure_reviewable(submission),
         {:ok, updated} <-
           submission
           |> TaskSubmission.feedback_changeset(attrs, user.id)
           |> Ecto.Changeset.put_change(:status, verdict)
           |> Repo.update() do
      broadcast_submission_updated(updated, submission.task.course_id)
      {:ok, updated}
    end
  end

  defp ensure_reviewable(%TaskSubmission{status: status}) do
    if status in @reviewable_statuses, do: :ok, else: {:error, :not_reviewable}
  end

  ## Korrektur (annotiertes Antwortdokument)

  @doc """
  Das Dokument, das die Lehrperson korrigiert: die Korrektur, sobald es eine
  gibt, sonst die Antworten der/des Lernenden.

  `corrected_content` wird nie explizit initialisiert — der erste
  Speichervorgang des Korrektur-Editors legt es an. Genauso macht es
  `Tasky.Exams.correction_content/1`.
  """
  def correction_content(%TaskSubmission{corrected_content: corrected})
      when is_map(corrected) and map_size(corrected) > 0,
      do: corrected

  def correction_content(%TaskSubmission{content: content}), do: content || %{}

  @doc "True, wenn die Lehrperson an dieser Abgabe schon annotiert hat."
  def has_correction?(%TaskSubmission{corrected_content: corrected}) when is_map(corrected),
    do: map_size(corrected) > 0

  def has_correction?(_submission), do: false

  @doc """
  Das Dokument, das die/der Lernende zurückgelesen bekommt.

  `{:corrected, doc}`, sobald es eine Korrektur gibt *und* die Lösung
  freigegeben ist — sonst `{:own, doc}`.

  Achtung: das korrigierte Dokument darf ausschliesslich in den
  Read-only-Viewer. Der editierbare `TaskAnswersEditor` schreibt das ganze
  Dokument nach `submission.content` zurück, eine zurückgegebene Einheit würde
  also die Anmerkungen der Lehrperson als eigene Antwort speichern.
  """
  def answer_doc_for_student(%Task{} = task, %TaskSubmission{} = submission) do
    if solution_visible?(task, submission) and has_correction?(submission),
      do: {:corrected, submission.corrected_content},
      else: {:own, submission.content || %{}}
  end

  @doc """
  Speichert die Anmerkungen der Lehrperson am Antwortdokument.

  Nur für eingereichte Einheiten: an einem Stand, an dem gerade gearbeitet
  wird, gibt es nichts zu korrigieren.
  """
  def save_correction_content(%Scope{} = scope, %Task{} = task, submission_id, doc)
      when is_map(doc) do
    with :ok <- Policy.authorize(scope, task.user_id),
         %TaskSubmission{} = submission <- get_submission(task, submission_id),
         :ok <- ensure_reviewable(submission) do
      result =
        Repo.transaction(fn ->
          locked = Repo.lock_one!(TaskSubmission, submission.id)

          case locked |> TaskSubmission.correction_changeset(doc) |> Repo.update() do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      with {:ok, updated} <- result do
        broadcast_submission_updated(updated, task.course_id)
        {:ok, updated}
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
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
  def create_task_attachment(scope, %Task{} = task, attrs) do
    with :ok <- Policy.authorize(scope, task.user_id) do
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
  end

  @doc "Deletes an attachment record and its file on disk."
  def delete_task_attachment(scope, %TaskAttachment{} = attachment) do
    with :ok <- authorize_task_id(scope, attachment.task_id),
         {:ok, deleted} <- Repo.delete(attachment) do
      Tasky.Uploads.delete_task_attachment_file(deleted.task_id, deleted.stored_filename)
      {:ok, deleted}
    end
  end

  ## Musterlösungs-Dateien

  @doc "Lists a task's solution files in display order."
  def list_task_solution_files(%Task{} = task) do
    Repo.all(
      from f in TaskSolutionFile,
        where: f.task_id == ^task.id,
        order_by: [asc: f.position, asc: f.id]
    )
  end

  @doc "Gets a solution file of the given task, or nil."
  def get_task_solution_file(%Task{} = task, id) do
    Repo.get_by(TaskSolutionFile, id: id, task_id: task.id)
  end

  @doc "Creates a solution file record, appending it to the list."
  def create_task_solution_file(scope, %Task{} = task, attrs) do
    with :ok <- Policy.authorize(scope, task.user_id) do
      position =
        Repo.one(
          from f in TaskSolutionFile,
            where: f.task_id == ^task.id,
            select: coalesce(max(f.position), -1)
        ) + 1

      %TaskSolutionFile{task_id: task.id}
      |> TaskSolutionFile.changeset(Map.put(attrs, :position, position))
      |> Repo.insert()
    end
  end

  @doc "Deletes a solution file record and its file on disk."
  def delete_task_solution_file(scope, %TaskSolutionFile{} = file) do
    with :ok <- authorize_task_id(scope, file.task_id),
         {:ok, deleted} <- Repo.delete(file) do
      Tasky.Uploads.delete_task_solution_file(deleted.task_id, deleted.stored_filename)
      {:ok, deleted}
    end
  end

  @doc """
  Löst eine Lösungsdatei für eine/n Lernende/n auf — aber nur, wenn die Lösung
  für sie/ihn auch freigegeben ist.

  Gibt `{:ok, task, file}` oder `nil` zurück (nicht `{:error, :forbidden}`):
  der Controller antwortet damit 404 statt 403 und verrät nicht, dass es
  überhaupt eine Lösungsdatei gibt. Die ganze Zugriffslogik steckt hier, nicht
  im Controller.
  """
  def get_solution_file_for_student(%Scope{user: user} = scope, task_id, file_id)
      when user.role == "student" do
    with %Task{} = task <- get_task_for_student(scope, task_id),
         submission when not is_nil(submission) <-
           get_submission_for_student(task.id, user.id),
         true <- solution_visible?(task, submission),
         %TaskSolutionFile{} = file <- get_task_solution_file(task, file_id) do
      {:ok, task, file}
    else
      _ -> nil
    end
  end

  def get_solution_file_for_student(_scope, _task_id, _file_id), do: nil

  # Writes to anything hanging off a learning unit go through its owner (or an
  # admin / the :system scope). One indexed lookup resolves the owner from the
  # child's task_id; a unit that is gone is not an authorization pass.
  defp authorize_task_id(scope, task_id) do
    case Repo.one(from t in Task, where: t.id == ^task_id, select: t.user_id) do
      nil -> {:error, :unauthorized}
      user_id -> Policy.authorize(scope, user_id)
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
  def create_task_upload_field(scope, %Task{} = task, attrs) do
    with :ok <- Policy.authorize(scope, task.user_id) do
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
  end

  @doc "Updates an upload field."
  def update_task_upload_field(scope, %TaskUploadField{} = field, attrs) do
    with :ok <- authorize_task_id(scope, field.task_id) do
      field
      |> TaskUploadField.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes an upload field including all student files uploaded into it
  (records via FK cascade, bytes on disk explicitly).
  """
  def delete_task_upload_field(scope, %TaskUploadField{} = field) do
    files =
      Repo.all(
        from sf in TaskSubmissionFile,
          where: sf.upload_field_id == ^field.id,
          join: s in assoc(sf, :task_submission),
          select: {s.task_id, sf.task_submission_id, sf.stored_filename}
      )

    with :ok <- authorize_task_id(scope, field.task_id),
         {:ok, deleted} <- Repo.delete(field) do
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
        submission |> lock_for_file_change!() |> ensure_files_editable!()

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
        submission |> lock_for_file_change!() |> ensure_files_editable!()

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

  # Rolls the surrounding transaction back unless the student may still edit the
  # submission. Same reasoning as `save_student_answers/3`, which gates the
  # answer doc — and the same reason it belongs here rather than in the
  # LiveView: the socket's struct is from mount and may be stale, so a late or
  # replayed event would otherwise still change the files of a completed unit.
  defp ensure_files_editable!(%TaskSubmission{} = submission) do
    if submission.status in @editable_statuses,
      do: :ok,
      else: Repo.rollback(:not_editable)
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
