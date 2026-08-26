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
  alias Tasky.Organizations

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
  Wie `get_course_for_student!/2`, aber ohne Preloads und ohne `raise` — `nil`,
  wenn der Kurs nicht existiert oder die Person nicht eingeschrieben ist.

  Für Aufrufer, die den Kurs selbst brauchen (nicht nur das Ja/Nein von
  `enrolled?/2`) und den Fehlerfall als Wert behandeln wollen.
  """
  def get_enrolled_course(student_id, course_id) do
    Repo.one(
      from c in Course,
        join: e in CourseEnrollment,
        on: c.id == e.course_id,
        where: c.id == ^course_id and e.student_id == ^student_id
    )
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

  Records first, bytes after. The transaction writes rows only and hands back
  the file copies it owes storage; those run afterwards, in parallel. A DB
  connection must never be held open across an object-storage round trip:
  copying inline used to spend well over the connection's 15 s checkout limit
  inside the transaction for a course with a few dozen files, and took the
  calling LiveView down with a `DBConnection.ConnectionError`.

  The tradeoff is therefore the reverse of what it once was: the records are
  always complete and consistent, while a storage failure can leave a unit
  pointing at bytes that never arrived (a broken content image, an attachment
  that 404s). `Tasky.Uploads.run_copies/2` logs and counts those; the fix is
  to delete the incomplete copy and duplicate again.

  Runs the copies synchronously — fine for scripts and tests, but the web
  layer should use `duplicate_course_records/3` via
  `Tasky.Courses.DuplicateRunner` so the LiveView stays responsive.
  """
  def duplicate_course(scope, %Course{} = source, name) do
    with {:ok, course, jobs} <- duplicate_course_records(scope, source, name) do
      Tasky.Uploads.run_copies(jobs)
      {:ok, course}
    end
  end

  @doc """
  Writes a duplicate's records in one transaction and returns
  `{:ok, course, copy_jobs}`.

  Performs no storage I/O whatsoever — that is the whole point; see
  `duplicate_course/3`.
  """
  def duplicate_course_records(scope, %Course{} = source, name) do
    with :ok <- Tasky.Policy.authorize(scope, source.teacher_id) do
      do_duplicate_records(scope, source, name, :owner)
    end
  end

  defp do_duplicate_records(scope, %Course{} = source, name, mode) do
    tasks_query = from t in Task, order_by: [asc: t.position]
    source = Repo.preload(source, tasks: tasks_query)

    attrs = %{
      "name" => String.slice(name, 0, 255),
      "description" => source.description
    }

    scope
    |> transact_duplicate(source, attrs, mode)
    |> unwrap_duplicate()
  end

  # Genau zwei Achsen, als ein Atom statt zweier Booleans: so ist an jeder
  # Aufrufstelle sichtbar, welcher Pfad gemeint ist, und die unsinnige
  # Kombination "Prüfung überspringen, Freigabe übernehmen" ist nicht bildbar.
  defp task_copy_opts(:owner), do: []

  defp task_copy_opts(:catalog_import),
    do: [source_authorized: true, reset_release_state: true]

  defp transact_duplicate(scope, source, attrs, mode),
    do: Repo.transaction(fn -> insert_duplicate(scope, source, attrs, mode) end)

  # Trägt für `duplicate_course_records/3` einen `%Course{}` und für
  # `copy_task_into_courses/3` die Liste der Kopien — beide Male "die
  # geschriebenen Datensätze plus die geschuldeten Datei-Kopien".
  defp unwrap_duplicate({:ok, {records, jobs}}), do: {:ok, records, jobs}
  defp unwrap_duplicate({:error, reason}), do: {:error, reason}

  defp insert_duplicate(scope, source, attrs, mode) do
    with {:ok, course} <- create_course(scope, attrs),
         {:ok, jobs} <- duplicate_tasks(scope, source.tasks, course.id, mode) do
      {course, jobs}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp duplicate_tasks(scope, tasks, course_id, mode) do
    opts = task_copy_opts(mode)

    tasks
    |> Enum.reduce_while({:ok, []}, fn task, {:ok, acc} ->
      case Tasky.Tasks.duplicate_task_into_course(scope, task, course_id, opts) do
        {:ok, _task, jobs} -> {:cont, {:ok, [jobs | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, acc |> Enum.reverse() |> Enum.concat()}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Kopiert **eine** Lerneinheit in einen oder mehrere *bestehende* Kurse und
  liefert `{:ok, kopien, copy_jobs}`.

  Das Gegenstück zu `duplicate_course/3`: dort entsteht ein neuer Kurs, hier
  wandert eine einzelne Einheit in Kurse, die es schon gibt — der Fall
  "dieselbe Lerneinheit, zwei Klassen". Jede Kopie landet **am Schluss** des
  Zielkurses (`Tasky.Tasks.next_task_position/1`) und kommt als
  unveröffentlichter, offener Entwurf mit versteckter Musterlösung an
  (`reset_release_state: true`): wann die andere Klasse etwas sieht, entscheidet
  die Lehrperson dort selbst.

  Es gibt keine Verknüpfung zur Quelle. Ein zweiter Aufruf legt eine zweite
  Kopie an; ein Abgleich bestehender Kopien findet nicht statt.

  Alles oder nichts: ein Zielkurs, der nicht existiert oder nicht der
  aufrufenden Person gehört, rollt die ganze Transaktion zurück — eine halb
  ausgeführte Kopie über mehrere Kurse wäre schlimmer als keine.

  Schreibt wie `duplicate_course_records/3` nur Datensätze und gibt die
  geschuldeten Datei-Kopien zurück, statt sie auszuführen; die Begründung steht
  bei `duplicate_course/3`. Die Web-Schicht ruft das über
  `Tasky.Courses.DuplicateRunner.start_task_copy/4` auf.
  """
  def copy_task_into_courses(%Scope{} = scope, %Task{} = source, course_ids)
      when is_list(course_ids) do
    with :ok <- Tasky.Policy.authorize(scope, source.user_id),
         {:ok, courses} <- fetch_copy_targets(scope, course_ids) do
      Repo.transaction(fn -> insert_task_copies(scope, source, courses) end)
      |> unwrap_duplicate()
    end
  end

  # Die Ziele werden *vor* der Transaktion vollständig geprüft: so scheitert ein
  # fremder Kurs, bevor irgendetwas geschrieben wurde, und `:unauthorized` bleibt
  # ein gewöhnlicher Fehlerwert statt eines Rollback-Grunds.
  defp fetch_copy_targets(scope, course_ids) do
    course_ids
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn course_id, {:ok, acc} ->
      case fetch_copy_target(scope, course_id) do
        {:ok, course} -> {:cont, {:ok, [course | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, courses} -> {:ok, Enum.reverse(courses)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Ein Kurs, den es nicht gibt, und einer, der einer anderen Lehrperson gehört,
  # sind für die Aufrufende dasselbe: nicht ihr Kurs.
  defp fetch_copy_target(scope, course_id) do
    with %Course{} = course <- Repo.get(Course, course_id),
         :ok <- Tasky.Policy.authorize(scope, course.teacher_id) do
      {:ok, course}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp insert_task_copies(scope, source, courses) do
    courses
    |> Enum.reduce_while({[], []}, fn course, {tasks, jobs} ->
      opts = [reset_release_state: true, position: Tasky.Tasks.next_task_position(course.id)]

      case Tasky.Tasks.duplicate_task_into_course(scope, source, course.id, opts) do
        {:ok, task, new_jobs} -> {:cont, {[task | tasks], [new_jobs | jobs]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} ->
        Repo.rollback(reason)

      {tasks, jobs} ->
        {Enum.reverse(tasks), jobs |> Enum.reverse() |> Enum.concat()}
    end
  end

  @doc """
  Updates a course.
  """
  def update_course(scope, %Course{} = course, attrs) do
    with :ok <- Tasky.Policy.authorize(scope, course.teacher_id) do
      course
      |> Course.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes a course together with the stored files of every learning unit in
  it.

  The bytes have to be cleared here explicitly. Tasks go away through the DB
  cascade (`on_delete: :delete_all`), which means `Tasky.Tasks.delete_task/2`
  — the only other place that clears a unit's uploads — never runs, and
  without this every content image and attachment in the course would be
  orphaned in storage forever.

  Storage is cleared after the row is gone and outside any transaction: on a
  remote adapter that is a list plus a delete per object, and a DB connection
  must never be held across those (see `duplicate_course/3`). A cleanup
  failure is logged, not surfaced — the deletion the caller asked for has
  already happened.
  """
  def delete_course(%Course{} = course) do
    # Read the ids before the cascade takes the rows out from under us.
    task_ids = Repo.all(from t in Task, where: t.course_id == ^course.id, select: t.id)

    with {:ok, deleted} <- Repo.delete(course) do
      Tasky.Uploads.delete_task_files_many(task_ids)
      {:ok, deleted}
    end
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

  # Kurs-Katalog

  @doc """
  Alle im Katalog veröffentlichten Kurse, neueste Veröffentlichung zuerst.

  Nur für Lehrpersonen und Admins; jeder andere Scope bekommt `[]`. Die Route
  ist zusätzlich rollengesichert — das hier ist die zweite Linie, analog zu
  `list_courses/1`.

  Liefert `%Course{}` mit vorgeladener `:teacher`-Assoziation und gefülltem
  virtuellem `unit_count`. Absichtlich OHNE `:tasks`-Preload: `tasks.content`
  ist das ganze Tiptap-Dokument (bis 5 MB pro Einheit), und die Liste braucht
  nur die Anzahl.
  """
  def list_catalog_courses(%Scope{} = scope) do
    if Scope.admin_or_teacher?(scope) do
      Repo.all(
        from c in Course,
          left_join: t in assoc(c, :tasks),
          where: not is_nil(c.catalog_published_at),
          group_by: c.id,
          order_by: [desc: c.catalog_published_at, desc: c.id],
          select_merge: %{unit_count: count(t.id)}
      )
      |> Repo.preload(:teacher)
    else
      []
    end
  end

  def list_catalog_courses(_scope), do: []

  @doc """
  Gets a single catalog course for the read-only preview.

  Absichtlich NICHT besitzergebunden — der Katalog ist für alle Lehrpersonen
  und Admins lesbar. Das Gate ist die Rolle plus `catalog_published_at`: die
  Veröffentlichung IST hier die Berechtigung, genau wie der Slug es in
  `get_course_by_share_slug/1` ist.

  Raises `Ecto.NoResultsError`, wenn der Kurs nicht existiert, nicht im Katalog
  ist oder der Scope keine Lehrperson und kein Admin ist — bewusst 404 statt
  403, wie `get_course!/2`: die Fehlerseite verrät so nicht, ob es den Kurs
  gibt.

  Lädt nur `:teacher`. Die Lerneinheiten holt der Aufrufer über
  `Tasky.Tasks.list_tasks_for_export/1` (Position, Anhänge, Upload-Felder).
  """
  def get_catalog_course!(%Scope{} = scope, id) do
    course =
      if Scope.admin_or_teacher?(scope) do
        Repo.one(
          from c in Course,
            where: c.id == ^id and not is_nil(c.catalog_published_at),
            preload: [:teacher]
        )
      end

    case course do
      %Course{} = course -> course
      nil -> raise Ecto.NoResultsError, queryable: Course
    end
  end

  @doc """
  Stellt den Kurs in den Kurs-Katalog: alle Lehrpersonen und Admins können ihn
  danach lesen und in ihre eigenen Kurse übernehmen.

  Ein Kurs ohne Lerneinheiten wird abgewiesen (`{:error, :no_units}`) — im
  Katalog wäre er nur Rauschen. Erneutes Veröffentlichen aktualisiert das
  Datum, weil die Katalogliste danach sortiert.
  """
  def publish_to_catalog(%Scope{} = scope, %Course{} = course) do
    with :ok <- Tasky.Policy.authorize(scope, course.teacher_id),
         :ok <- ensure_has_units(course) do
      course
      |> Ecto.Changeset.change(catalog_published_at: DateTime.utc_now(:second))
      |> Repo.update()
    end
  end

  defp ensure_has_units(%Course{id: course_id}) do
    if Repo.exists?(from t in Task, where: t.course_id == ^course_id),
      do: :ok,
      else: {:error, :no_units}
  end

  @doc """
  Nimmt den Kurs aus dem Katalog.

  Bereits erstellte Importe anderer Lehrpersonen bleiben bestehen — eine Kopie
  ist ab dem Import eigenständig und hat ihre eigenen Dateien.
  """
  def unpublish_from_catalog(%Scope{} = scope, %Course{} = course) do
    with :ok <- Tasky.Policy.authorize(scope, course.teacher_id) do
      course
      |> Ecto.Changeset.change(catalog_published_at: nil)
      |> Repo.update()
    end
  end

  @doc """
  Übernimmt einen Katalog-Kurs in das Konto der aufrufenden Lehrperson und
  schreibt dessen Records in einer Transaktion; liefert
  `{:ok, course, copy_jobs}` wie `duplicate_course_records/3`.

  Das ist der einzige Pfad, auf dem eine Lehrperson Inhalte einer *anderen*
  Lehrperson kopieren darf, und darum liegt die ganze Berechtigung hier:
  Rolle (Lehrperson oder Admin) plus `catalog_published_at` an der Quelle. Die
  Veröffentlichung IST die Berechtigung — dieselbe Form wie der Slug in
  `get_course_by_share_slug/1`. Die Besitzprüfung pro Lerneinheit in
  `Tasky.Tasks.duplicate_task_into_course/4` wird deshalb bewusst übersprungen;
  sie kann hier per Definition nicht bestehen.

  Nimmt eine `source_id`, nicht einen `%Course{}`: die Vorschauseite kann
  minutenlang offen stehen, und ein beim Mount gefangener Struct würde einen
  Import erlauben, nachdem die Autorin den Kurs aus dem Katalog genommen hat.
  Bewusst ohne Row-Lock — das Rennen zu verlieren ist harmlos (der Import war
  eine Millisekunde früher legal), und ein `FOR SHARE` auf `courses` würde eine
  neue Lock-Order-Frage aufwerfen, ohne etwas zu sichern.

  Jede kopierte Lerneinheit entsteht als unveröffentlichter, offener Entwurf
  (siehe `Tasky.Tasks.duplicate_task_into_course/4`). Die Kopie ist nicht im
  Katalog, hat keine Lernenden, keine Abgaben und keinen offenen
  Feedback-Briefkasten.
  """
  def import_catalog_course_records(%Scope{} = scope, source_id, name) do
    with {:ok, source} <- fetch_importable_course(scope, source_id) do
      do_duplicate_records(scope, source, name, :catalog_import)
    end
  end

  defp fetch_importable_course(scope, source_id) do
    if Scope.admin_or_teacher?(scope),
      do: importable(Repo.get(Course, source_id)),
      else: {:error, :unauthorized}
  end

  defp importable(%Course{} = course) do
    if Course.catalog_published?(course), do: {:ok, course}, else: {:error, :not_found}
  end

  defp importable(nil), do: {:error, :not_found}

  @doc """
  Wie `import_catalog_course_records/3`, führt die Datei-Kopien aber synchron
  aus. Für Skripte und Tests; die Web-Schicht nimmt
  `Tasky.Courses.DuplicateRunner.start_catalog_import/4`, damit die LiveView
  ansprechbar bleibt.
  """
  def import_catalog_course(%Scope{} = scope, source_id, name) do
    with {:ok, course, jobs} <- import_catalog_course_records(scope, source_id, name) do
      Tasky.Uploads.run_copies(jobs)
      {:ok, course}
    end
  end

  # Enrollment functions

  @doc """
  Enrolls a student in a course.

  The student id arrives off the wire (a `phx-value-student_id`), so membership
  is verified here rather than trusted: the student must belong to the
  organization of the course's **owner**. Scoping the picker in the UI would only
  clean up the modal — this event handler is directly reachable, and an enrolled
  student's name, email and progress become visible to the teacher.

  Deriving the organization from the owner rather than from a caller scope keeps
  the signature unchanged and makes the rule hold even when an admin (who has no
  organization) performs the enrollment.
  """
  def enroll_student(course_id, student_id) do
    owner_organization_id =
      Repo.one(from c in Course, where: c.id == ^course_id, select: c.teacher_id)
      |> Organizations.teacher_organization_id()

    if Organizations.student_member?(student_id, owner_organization_id) do
      %CourseEnrollment{}
      |> CourseEnrollment.changeset(%{course_id: course_id, student_id: student_id})
      |> Repo.insert()
    else
      {:error, :different_organization}
    end
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

  Deliberately **not** organization-filtered: both callers load the course
  through `get_course!/2` or `Tasks.get_task_with_course!/2` first, so
  enrollment is the authorization boundary here. Filtering would only make
  students vanish from a progress grid while their submissions stay in the
  database. Accepted consequence: a student an admin moves to another class
  stays visible in the old roster.
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
  Returns the students who could still be enrolled in this course, optionally
  narrowed to one class.

  Limited to the organization of the course's **owner**, which is also what
  `enroll_student/2` enforces on the write path.
  """
  def list_unenrolled_students(course_id, class_id \\ nil) do
    owner_organization_id =
      Repo.one(from c in Course, where: c.id == ^course_id, select: c.teacher_id)
      |> Organizations.teacher_organization_id()

    owner_organization_id
    |> Organizations.students_query()
    |> where(
      [u],
      u.id not in subquery(
        from e in CourseEnrollment,
          where: e.course_id == ^course_id,
          select: e.student_id
      )
    )
    |> then(fn q -> if class_id, do: where(q, [u], u.class_id == ^class_id), else: q end)
    |> order_by([u], asc: u.email)
    |> Repo.all()
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
