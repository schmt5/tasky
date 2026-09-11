defmodule Tasky.Exams do
  @moduledoc """
  The Exams context.
  """

  import Ecto.Query, warn: false
  alias Tasky.Repo

  alias Tasky.Accounts.Scope
  alias Tasky.Accounts.User
  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.AnswerKey
  alias Tasky.Correction.AnswerVariants
  alias Tasky.Correction.SolutionHints
  alias Tasky.Exams.Exam
  alias Tasky.Exams.ExamAttachment
  alias Tasky.Exams.ExamSubmission
  alias Tasky.Exams.ExamSubmissionFile
  alias Tasky.Exams.ExamUploadField
  alias Tasky.Grading
  alias Tasky.Organizations
  alias Tasky.Policy

  @doc """
  Returns the list of exams for a given scope.
  Teachers see only their own exams, admins see all exams.
  """
  def list_exams(%Scope{user: user}) do
    case user.role do
      "admin" ->
        Repo.all(from e in Exam, order_by: [desc: e.inserted_at], preload: [:teacher])

      "teacher" ->
        Repo.all(
          from e in Exam,
            where: e.teacher_id == ^user.id,
            order_by: [desc: e.inserted_at],
            preload: [:teacher]
        )

      _ ->
        []
    end
  end

  @doc """
  Gets a single exam.

  Raises `Ecto.NoResultsError` if the Exam does not exist.
  """
  def get_exam!(scope, id) do
    exam = Repo.get!(Exam, id) |> Repo.preload([:teacher])

    if Policy.can_manage?(scope, exam.teacher_id) do
      exam
    else
      raise Ecto.NoResultsError, queryable: Exam
    end
  end

  @doc """
  Creates an exam.
  """
  def create_exam(scope, attrs \\ %{}) do
    %Exam{}
    |> Exam.create_changeset(attrs, scope)
    |> Repo.insert()
  end

  @doc """
  Duplicates an existing exam under the given (caller-provided, localized)
  name, including its content images, teacher attachments and student upload
  fields. Submissions and the files students uploaded are deliberately left
  behind — a duplicate starts without any student data.

  The copy is always in "draft" status with no enrollment_token. If SEB is
  enabled, a fresh quit password is generated.
  """
  def duplicate_exam(scope, %Exam{} = source, name) do
    with {:ok, exam, jobs} <- duplicate_exam_records(scope, source, name) do
      Tasky.Uploads.run_copies(jobs)
      {:ok, exam}
    end
  end

  @doc """
  Writes a duplicate's records in one transaction and returns
  `{:ok, exam, copy_jobs}`.

  Performs no storage I/O whatsoever — a DB connection must never be held
  across object-storage round trips; see `Tasky.Courses.duplicate_course/3`.
  """
  def duplicate_exam_records(scope, %Exam{} = source, name) do
    with :ok <- Policy.authorize(scope, source.teacher_id) do
      Repo.transaction(fn ->
        case insert_exam_duplicate(scope, source, name) do
          {:ok, exam, jobs} -> {exam, jobs}
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, {exam, jobs}} -> {:ok, exam, jobs}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp insert_exam_duplicate(scope, source, name) do
    attrs = %{
      "name" => String.slice(name, 0, 255),
      # Castable on create only, so the copy is the one chance to carry it over
      # — a duplicated essay must not come back as an answer-field exam.
      "answer_mode" => source.answer_mode,
      "sample_solution_points" => source.sample_solution_points || %{},
      "sample_solution_block_points" => source.sample_solution_block_points || %{},
      "seb_enabled" => source.seb_enabled,
      # Fresh secrets for the copy: a duplicated exam is a separate session, and
      # sharing the passwords would mean one leaked `.seb` file unlocks both.
      "seb_quit_password" => if(source.seb_enabled, do: generate_quit_password(), else: nil),
      "seb_admin_password" => if(source.seb_enabled, do: generate_admin_password(), else: nil),
      "ai_correction_config" => source.ai_correction_config || %{}
      # status defaults to "draft" via schema
      # enrollment_token stays nil
      # teacher_id set from scope via create_changeset
      # content and sample_solution follow in a second step: the image URLs
      # they carry can only be rewritten once the copy has an id
    }

    with {:ok, exam} <- create_exam(scope, attrs),
         {:ok, exam, image_jobs} <- copy_exam_content(exam, source),
         {:ok, exam} <- copy_paper_layout(exam, source),
         {:ok, attachment_jobs} <- copy_exam_attachments(scope, exam, source),
         :ok <- copy_exam_upload_fields(scope, exam, source) do
      {:ok, exam, image_jobs ++ attachment_jobs}
    end
  end

  # The teacher's answer-box sizing for the paper version. Worth carrying over
  # because the copy keeps the document's `answerId`s — only image URLs are
  # rewritten above — so every entry still points at the box it was measured
  # for, and the sizing is manual work that would otherwise be redone.
  #
  # Runs after copy_exam_content/2, which writes `content` and therefore hands
  # back a fresh struct. Uses change/2 rather than cast: `:paper_layout` is
  # absent from every changeset on purpose (see Exam), and nothing
  # user-supplied reaches this value — it is copied from a row the caller was
  # already authorized for.
  defp copy_paper_layout(exam, %Exam{paper_layout: nil}), do: {:ok, exam}

  defp copy_paper_layout(exam, %Exam{paper_layout: layout}) do
    exam |> Ecto.Changeset.change(%{paper_layout: layout}) |> Repo.update()
  end

  # Both the exam body and the stored model answers can carry content images (a
  # teacher can paste one into a model answer), so both go through the
  # rewriter — otherwise the copy would keep pointing at the source's bytes and
  # go blank the moment the original is deleted. `run_copies/2` dedups by
  # destination, so an image referenced from both is still copied once.
  defp copy_exam_content(exam, %Exam{} = source) do
    {content, content_jobs} =
      Tasky.Uploads.plan_content_image_copies(source.content || %{}, :exams, source.id, exam.id)

    {sample_solution, sample_jobs} =
      Tasky.Uploads.plan_content_image_copies(
        source.sample_solution || %{},
        :exams,
        source.id,
        exam.id
      )

    with {:ok, exam} <-
           exam
           |> Exam.changeset(%{content: content, sample_solution: sample_solution})
           |> Repo.update() do
      {:ok, exam, content_jobs ++ sample_jobs}
    end
  end

  defp copy_exam_attachments(scope, exam, source) do
    source
    |> list_exam_attachments()
    |> Enum.reduce_while({:ok, []}, fn attachment, {:ok, jobs} ->
      with {:ok, stored_filename, job} <-
             Tasky.Uploads.plan_attachment_copy(
               :exams,
               source.id,
               exam.id,
               attachment.stored_filename
             ),
           {:ok, _attachment} <-
             create_exam_attachment(scope, exam, %{
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

  defp copy_exam_upload_fields(scope, exam, source) do
    source
    |> list_upload_fields()
    |> Enum.reduce_while(:ok, fn field, _acc ->
      case create_upload_field(scope, exam, %{
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
  Updates an exam's regular attributes (name, content, SEB config, …).
  Status and enrollment token are not mass-assignable — they change only
  through `update_exam_status/3` and `open_exam_session/2`.
  """
  def update_exam(scope, %Exam{} = exam, attrs) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      exam
      |> Exam.changeset(attrs)
      |> Repo.update()
    end
  end

  # The exam lifecycle is a one-way street; anything else is a caller bug or
  # a forged request. "open" additionally requires an enrollment token, so it
  # is only reachable via open_exam_session/2.
  @status_transitions %{
    "draft" => ~w(open),
    "open" => ~w(running),
    "running" => ~w(finished),
    # `finished -> running` is the escape hatch for a misclicked "Prüfung
    # beenden": the click is otherwise terminal, and after it nobody can save
    # or hand in any more. Reopening broadcasts the status change like any
    # other transition, so the participants' views follow on their own.
    "finished" => ~w(archived running),
    "archived" => ~w()
  }

  @doc """
  Advances the status of an exam along the allowed lifecycle
  (draft → open → running → finished → archived). Returns
  `{:error, :invalid_transition}` for anything else.
  """
  def update_exam_status(scope, %Exam{} = exam, status) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         :ok <- validate_status_transition(exam.status, status) do
      exam
      |> Ecto.Changeset.change(%{status: status})
      |> update_and_broadcast(&broadcast_exam_update/1)
    end
  end

  defp validate_status_transition(from, to) do
    if to in Map.get(@status_transitions, from, []) do
      :ok
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Opens an exam session in the given participation mode and sets the status to
  open.

  `"anonymous"` mints an enrollment token for the `/guest/enroll/:token` page;
  `"assigned"` deliberately leaves it `nil` — a token on an assigned exam would
  be a hole, since a leaked link would let strangers self-enrol into a session
  meant for named accounts.
  """
  def open_exam_session(scope, %Exam{} = exam, mode) when mode in ["assigned", "anonymous"] do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         :ok <- validate_status_transition(exam.status, "open") do
      # Resolved once, here, and stored on the exam — see Exam.open_changeset/4.
      allow_files? = exam_has_files?(exam)

      result =
        case mode do
          "anonymous" ->
            open_with_fresh_token(exam, allow_files?, 5)

          "assigned" ->
            exam
            |> Exam.open_changeset("assigned", nil, allow_files?)
            |> Repo.update()
        end

      case result do
        {:ok, updated_exam} ->
          broadcast_exam_update(updated_exam)
          {:ok, updated_exam}

        error ->
          error
      end
    end
  end

  # The token space is small enough that collisions are possible — retry with a
  # fresh token instead of surfacing a constraint error.
  defp open_with_fresh_token(_exam, _allow_files?, 0), do: {:error, :token_collision}

  defp open_with_fresh_token(exam, allow_files?, attempts) do
    result =
      exam
      |> Exam.open_changeset("anonymous", generate_enrollment_token(), allow_files?)
      |> Ecto.Changeset.unique_constraint(:enrollment_token)
      |> Repo.update()

    case result do
      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :enrollment_token) do
          open_with_fresh_token(exam, allow_files?, attempts - 1)
        else
          error
        end

      other ->
        other
    end
  end

  @doc "The participation modes a session can run in."
  def participation_modes, do: Exam.participation_modes()

  @doc "True when the exam runs with assigned, logged-in participants."
  def assigned_mode?(%Exam{participation_mode: "assigned"}), do: true
  def assigned_mode?(%Exam{}), do: false

  @doc "True when the exam runs with anonymous participants enrolling via link."
  def anonymous_mode?(%Exam{participation_mode: "anonymous"}), do: true
  def anonymous_mode?(%Exam{}), do: false

  @doc "True once a corrected exam has been handed back to its participants."
  def returned?(%Exam{returned_at: nil}), do: false
  def returned?(%Exam{}), do: true

  # 10 base32 chars ≈ 50 bits. The token is never typed by hand — the cockpit
  # only offers the full enrol URL as copy-to-clipboard — so length costs
  # nothing, and the previous 6 chars (~30 bits) were thin for a credential
  # that grants access to an exam.
  defp generate_enrollment_token do
    :crypto.strong_rand_bytes(10)
    |> Base.encode32(case: :lower, padding: false)
    |> String.slice(0, 10)
    |> String.upcase()
  end

  # Dictation-friendly: no 0/O, 1/I/l, or anything else that goes wrong when a
  # teacher reads it out across a room.
  @password_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  @doc """
  Generates a fresh SEB quit password. The single place quit passwords come
  from.

  Eleven characters out of a 32-symbol alphabet is ~55 bits. Length matters
  here because the password's SHA-256 travels inside the plain (`plnd`) `.seb`
  file that every participant downloads: the previous 6-digit password had
  900 000 candidates, so anyone holding the file could recover it in
  milliseconds and quit the lockdown mid-exam.
  """
  def generate_quit_password, do: random_password(11) |> group_in_fours()

  @doc """
  Generates a fresh SEB admin password, which gates SEB's own preferences and
  config-inspection windows. Never spoken aloud, so it is not grouped and it is
  long (26 chars ≈ 130 bits).
  """
  def generate_admin_password, do: random_password(26)

  defp random_password(length) do
    # Rejection-free because the alphabet size (32) divides 256 evenly, so
    # `rem/2` over strong random bytes stays uniform.
    alphabet_size = length(@password_alphabet)

    :crypto.strong_rand_bytes(length)
    |> :binary.bin_to_list()
    |> Enum.map(&Enum.at(@password_alphabet, rem(&1, alphabet_size)))
    |> List.to_string()
  end

  defp group_in_fours(string) do
    string
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join("-", &Enum.join/1)
  end

  @doc """
  Sets the SEB enforcement mode (`"observe"` / `"enforce"`).

  Not part of `update_exam/3`: the mode decides whether a participant can reach
  the exam at all, so it must not be reachable through a content form.
  """
  def set_seb_enforcement(scope, %Exam{} = exam, mode) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      exam
      |> Exam.seb_enforcement_changeset(mode)
      |> update_and_broadcast(&broadcast_exam_update/1)
    end
  end

  @doc """
  Suspends SEB enforcement for `minutes`, degrading `"enforce"` to `"observe"`
  until it expires.

  The kill switch for exam day: if the Config Key derivation is wrong for the
  SEB build in the room, this is what gets the class writing again without a
  deploy. Broadcast like any other exam update so the participants' halted
  views can be retried.
  """
  def bypass_seb(scope, %Exam{} = exam, minutes) when is_integer(minutes) and minutes > 0 do
    until =
      DateTime.utc_now()
      |> DateTime.add(minutes * 60, :second)
      |> DateTime.truncate(:second)

    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      exam
      |> Ecto.Changeset.change(%{seb_bypass_until: until})
      |> update_and_broadcast(&broadcast_exam_update/1)
    end
  end

  # Capped so a misbehaving client cannot grow the row without bound.
  @max_accepted_config_keys 10

  @doc """
  Adds an observed SEB Config Key hash to the exam's accepted list.

  The operator override behind `observe` mode: a hash a real client actually
  sent can be blessed explicitly, so a config change mid-session — or a
  derivation that is subtly wrong for one SEB build — does not end the exam for
  everybody. Idempotent.
  """
  def accept_seb_config_key(scope, %Exam{} = exam, hash) when is_binary(hash) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         {:ok, normalized} <- normalize_config_key(hash) do
      if normalized in (exam.seb_accepted_config_keys || []) do
        {:ok, exam}
      else
        keys =
          [normalized | exam.seb_accepted_config_keys || []]
          |> Enum.take(@max_accepted_config_keys)

        exam
        |> Ecto.Changeset.change(%{seb_accepted_config_keys: keys})
        |> update_and_broadcast(&broadcast_exam_update/1)
      end
    end
  end

  defp normalize_config_key(hash) do
    normalized = hash |> String.trim() |> String.downcase()

    if Regex.match?(~r/^[0-9a-f]{64}$/, normalized),
      do: {:ok, normalized},
      else: {:error, :invalid_config_key}
  end

  @doc """
  Deletes an exam.
  """
  def delete_exam(scope, %Exam{} = exam) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         {:ok, deleted} <- Repo.delete(exam) do
      # The DB cascade removes the rows; the stored bytes (content images,
      # attachments, submission files) must go too or they leak forever.
      Tasky.Uploads.delete_exam_files(exam.id)
      {:ok, deleted}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking exam changes.
  """
  def change_exam(%Exam{} = exam, attrs \\ %{}) do
    Exam.changeset(exam, attrs)
  end

  @doc """
  Changeset for the create form. Unlike `change_exam/2` this one carries
  `:answer_mode`, which is only ever chosen here — see `Exam.new_changeset/2`.
  """
  def change_new_exam(%Exam{} = exam, attrs \\ %{}) do
    Exam.new_changeset(exam, attrs)
  end

  # --- Guest / Submission functions ---

  @doc """
  Gets an exam by its enrollment token. Used for the guest enrollment page.
  Raises if not found.
  """
  def get_exam_by_enrollment_token!(token) do
    enrollment_token_query(token)
    |> Repo.one!()
    |> Repo.preload([:teacher])
  end

  @doc """
  Gets an exam by its enrollment token, or `nil` if the token is unknown.
  Lets the enrollment page render a friendly "invalid link" state instead
  of raising a generic 404.
  """
  def get_exam_by_enrollment_token(token) when is_binary(token) do
    case Repo.one(enrollment_token_query(token)) do
      nil -> nil
      exam -> Repo.preload(exam, [:teacher])
    end
  end

  # Belt and braces: the mode filter keeps a stale token from a session that
  # was reopened as assigned from resolving, and the nil guard keeps an empty
  # token from matching an arbitrary assigned exam.
  defp enrollment_token_query(token) do
    from e in Exam,
      where:
        e.enrollment_token == ^token and not is_nil(e.enrollment_token) and
          e.participation_mode == "anonymous"
  end

  @doc """
  Returns all exam submissions for a given exam, ordered by enrollment time.
  """
  def list_exam_submissions(%Exam{} = exam) do
    ExamSubmission
    |> where([s], s.exam_id == ^exam.id)
    |> order_by([s], asc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single submission of the given exam. Authorization rides on the
  exam: callers fetch it via `get_exam!/2` first. Raises if the submission
  does not exist or belongs to a different exam.
  """
  def get_submission!(%Exam{} = exam, id) do
    Repo.get_by!(ExamSubmission, id: id, exam_id: exam.id)
  end

  @doc "Like `get_submission!/2` but returns nil instead of raising."
  def get_submission(%Exam{} = exam, id) do
    Repo.get_by(ExamSubmission, id: id, exam_id: exam.id)
  end

  @doc "Lists the exam's submissions with the given ids (foreign ids are ignored)."
  def list_submissions_by_ids(%Exam{} = exam, ids) when is_list(ids) do
    Repo.all(from s in ExamSubmission, where: s.id in ^ids and s.exam_id == ^exam.id)
  end

  # Transaction-only variants of the two functions above: they take a row lock on
  # every submission they return, for the bulk operations that read-modify-write
  # each row. Deliberately private — the public listings feed LiveView renders
  # and must not lock.
  #
  # `order_by: [asc: s.id]` is load-bearing, not cosmetic: LockRows sits above
  # Sort, so rows are locked in id order and two bulk operations over
  # overlapping sets cannot deadlock against each other. (Ordering by
  # inserted_at would not do — it is not unique.)
  defp lock_exam_submissions!(%Exam{} = exam) do
    Repo.all(
      from s in ExamSubmission,
        where: s.exam_id == ^exam.id,
        order_by: [asc: s.id],
        lock: "FOR UPDATE"
    )
  end

  defp lock_submissions_by_ids!(%Exam{} = exam, ids) when is_list(ids) do
    Repo.all(
      from s in ExamSubmission,
        where: s.id in ^ids and s.exam_id == ^exam.id,
        order_by: [asc: s.id],
        lock: "FOR UPDATE"
    )
  end

  @doc """
  Creates an exam submission for a guest user.
  The exam must be in "open" or "running" status.
  """
  def create_exam_submission(%Exam{} = exam, attrs) do
    # The status is re-read from the locked row, not taken from the caller's
    # struct: `EnrollLive` loads the exam once in `mount` and subscribes to
    # nothing, so someone who opened the enrol page while the exam was open
    # could otherwise still enrol hours after the teacher closed it. FOR SHARE
    # excludes `update_exam_status/3` without blocking concurrent enrolments.
    Repo.transaction(fn ->
      locked = Repo.lock_one!(Exam, exam.id, :share)

      # The mode is re-read from the locked row too — this is the authoritative
      # layer, and it holds even against an EnrollLive mounted before the
      # session was opened for assigned participants.
      if locked.status in ["open", "running"] and locked.participation_mode == "anonymous" do
        case %ExamSubmission{exam_id: locked.id}
             |> ExamSubmission.changeset(attrs)
             |> Repo.insert() do
          {:ok, submission} -> submission
          {:error, changeset} -> Repo.rollback(changeset)
        end
      else
        Repo.rollback(:exam_not_open)
      end
    end)
  end

  # --- Assigned participants ---

  @doc """
  Lists the students who could still be assigned to this exam, optionally
  narrowed to one class.

  Limited to the organization of the exam's **owner** — the same rule
  `fetch_assignable_user/2` enforces on the write path. Deriving it from
  `exam.teacher_id` rather than from a caller scope keeps the signature unchanged
  and holds even when an admin performs the assignment.
  """
  def list_assignable_students(%Exam{} = exam, class_id \\ nil) do
    exam.teacher_id
    |> Organizations.teacher_organization_id()
    |> Organizations.students_query()
    |> where(
      [u],
      u.id not in subquery(
        from s in ExamSubmission,
          where: s.exam_id == ^exam.id and not is_nil(s.user_id),
          select: s.user_id
      )
    )
    |> then(fn q -> if class_id, do: where(q, [u], u.class_id == ^class_id), else: q end)
    |> order_by([u], asc: u.lastname, asc: u.firstname, asc: u.email)
    |> Repo.all()
  end

  @doc """
  Assigns one logged-in student to an assigned-mode exam, creating their
  submission right away so the roster, correction and grading views always show
  the full class — absentees included.
  """
  def assign_student(scope, %Exam{} = exam, user_id) when is_integer(user_id) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      Repo.transaction(fn ->
        # FOR SHARE, per the lock rules in ARCHITECTURE.md: FOR UPDATE on
        # `exams` conflicts with the FOR KEY SHARE that the child INSERT takes
        # on the parent row.
        locked = Repo.lock_one!(Exam, exam.id, :share)

        with :ok <- check_assignable(locked),
             {:ok, user} <- fetch_assignable_user(locked, user_id),
             {:ok, submission} <- insert_assignment(locked, user) do
          submission
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  @doc """
  Assigns every not-yet-assigned student of a class in one transaction.
  Returns `{:ok, %{assigned: n, skipped: n}}`; skips are students who raced in
  through another tab, not errors.
  """
  def assign_students_from_class(scope, %Exam{} = exam, class_id) when is_integer(class_id) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      Repo.transaction(fn ->
        locked = Repo.lock_one!(Exam, exam.id, :share)

        case check_assignable(locked) do
          :ok ->
            locked
            |> list_assignable_students(class_id)
            |> Enum.reduce(%{assigned: 0, skipped: 0}, fn user, acc ->
              case insert_assignment(locked, user) do
                {:ok, _submission} -> Map.update!(acc, :assigned, &(&1 + 1))
                {:error, _changeset} -> Map.update!(acc, :skipped, &(&1 + 1))
              end
            end)

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
    end
  end

  # The unique constraints on (exam_id, user_id) and (exam_id, email) rule out
  # a single `insert_all` with one `on_conflict` target, so this inserts row by
  # row. A class is ~25 rows.
  #
  # `mode: :savepoint` is load-bearing: without it a constraint violation
  # aborts the surrounding Postgres transaction, so the bulk loop could not
  # skip an already-assigned student and carry on.
  defp insert_assignment(%Exam{} = locked_exam, %User{} = user) do
    %ExamSubmission{exam_id: locked_exam.id}
    |> ExamSubmission.assignment_changeset(%{
      user_id: user.id,
      firstname: user.firstname,
      lastname: user.lastname,
      email: user.email
    })
    |> Repo.insert(mode: :savepoint)
  end

  defp check_assignable(%Exam{} = exam) do
    cond do
      exam.participation_mode != "assigned" -> {:error, :not_assigned_mode}
      exam.status not in ["open", "running"] -> {:error, :exam_not_open}
      true -> :ok
    end
  end

  # The id arrives off the wire, so both the role and the organization are
  # checked here rather than trusted — otherwise a teacher could assign an admin,
  # or a student of another organization whose name and email would then show up
  # in the cockpit, correction and grading views.
  defp fetch_assignable_user(%Exam{} = exam, user_id) do
    case Repo.get(User, user_id) do
      %User{role: "student"} = user ->
        owner_organization_id = Organizations.teacher_organization_id(exam.teacher_id)

        if Organizations.student_member?(user.id, owner_organization_id) do
          {:ok, user}
        else
          {:error, :different_organization}
        end

      _ ->
        {:error, :not_a_student}
    end
  end

  @doc """
  Removes an assignment, including any answer files the participant uploaded
  (rows via FK cascade, bytes on disk explicitly — otherwise they leak
  forever). Refuses once the exam has been submitted.
  """
  def unassign_student(scope, %Exam{} = exam, %ExamSubmission{} = submission) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         :ok <- validate_unassignable(exam, submission) do
      files =
        Repo.all(
          from sf in ExamSubmissionFile,
            where: sf.exam_submission_id == ^submission.id,
            select: sf.stored_filename
        )

      case Repo.delete(submission) do
        {:ok, deleted} ->
          # Disk deletion is not transactional and must run after the commit.
          Enum.each(files, fn stored ->
            Tasky.Uploads.delete_submission_file_from_disk(exam.id, submission.id, stored)
          end)

          {:ok, deleted}

        error ->
          error
      end
    end
  end

  defp validate_unassignable(%Exam{} = exam, %ExamSubmission{} = submission) do
    cond do
      submission.exam_id != exam.id -> {:error, :not_found}
      is_nil(submission.user_id) -> {:error, :not_assigned}
      submission.submitted -> {:error, :already_submitted}
      true -> :ok
    end
  end

  @doc """
  The submission a logged-in participant owns for this exam, or nil. Exam and
  teacher preloaded.
  """
  def get_submission_for_user(exam_id, user_id) do
    case Repo.get_by(ExamSubmission, exam_id: exam_id, user_id: user_id) do
      nil -> nil
      submission -> Repo.preload(submission, exam: [:teacher])
    end
  end

  @doc """
  The exams a student has been assigned to, as their own submissions with the
  exam preloaded — everything the student's view needs (`submitted`,
  `exam_token`, `mark`) lives on the submission, not the exam.
  """
  def list_assigned_exams(%Scope{user: %{role: "student", id: user_id}}) do
    Repo.all(
      from s in ExamSubmission,
        join: e in assoc(s, :exam),
        where: s.user_id == ^user_id and e.participation_mode == "assigned",
        order_by: [desc: e.inserted_at],
        preload: [exam: {e, [:teacher]}]
    )
  end

  def list_assigned_exams(%Scope{}), do: []

  @doc """
  Hands the corrected exam back to all assigned participants. `opts` carries
  the same four flags as the PDF export and decides what they get to see.
  """
  def return_exam(scope, %Exam{} = exam, opts) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         :ok <- validate_returnable(exam) do
      exam
      |> Exam.return_changeset(%{
        returned_at: DateTime.utc_now(:second),
        return_show_points_and_mark: !!opts[:show_points_and_mark],
        return_show_content: !!opts[:show_content],
        return_show_correction: !!opts[:show_correction],
        return_show_sample_solution: !!opts[:show_sample_solution]
      })
      |> update_and_broadcast(&broadcast_exam_update/1)
    end
  end

  @doc """
  Withdraws a return. The four flags are left as they are — they pre-fill the
  modal if the exam is handed back again.
  """
  def withdraw_exam_return(scope, %Exam{} = exam) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         :ok <- validate_returnable(exam) do
      exam
      |> Exam.return_changeset(%{returned_at: nil})
      |> update_and_broadcast(&broadcast_exam_update/1)
    end
  end

  defp validate_returnable(%Exam{} = exam) do
    cond do
      not assigned_mode?(exam) -> {:error, :not_assigned_mode}
      exam.status not in ["finished", "archived"] -> {:error, :exam_not_finished}
      true -> :ok
    end
  end

  @doc """
  Gets an exam submission by its exam_token. Used for the guest exam/waiting room view.
  Preloads the exam and its teacher.
  Raises if not found.
  """
  def get_exam_submission_by_token!(token) do
    ExamSubmission
    |> Repo.get_by!(exam_token: token)
    |> Repo.preload(exam: [:teacher])
  end

  @doc """
  Gets an exam submission by its exam_token, or `nil` if the token is unknown.
  Lets the exam page render a friendly "invalid/expired link" state (e.g. a
  stale resume link to a deleted submission) instead of raising a 404.
  """
  def get_exam_submission_by_token(token) when is_binary(token) do
    case Repo.get_by(ExamSubmission, exam_token: token) do
      nil -> nil
      submission -> Repo.preload(submission, exam: [:teacher])
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking exam_submission changes.
  """
  def change_exam_submission(%ExamSubmission{} = exam_submission, attrs \\ %{}) do
    ExamSubmission.changeset(exam_submission, attrs)
  end

  @doc """
  Updates the content (TipTap doc JSON) of a non-submitted exam submission.
  Only allowed when the associated exam is still running and the submission
  has not been submitted yet.
  """
  def update_exam_submission_content(%ExamSubmission{} = submission, content)
      when is_map(content) do
    # Gate and write run in one transaction against locked rows: an autosave
    # already in flight when the student hits submit must not land content on a
    # submission that is by then handed in (TOCTOU). This is the hottest write
    # path in the app — one keystroke debounce per student — so the transaction
    # holds nothing but the two locks, the check and the update.
    Repo.transaction(fn ->
      {exam, locked} = lock_submission_for_write!(submission)
      ensure_submission_writable!(exam, locked)

      case locked |> ExamSubmission.content_changeset(%{content: content}) |> Repo.update() do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Marks an exam submission as submitted.
  Only allowed when the associated exam is still running.
  """
  def submit_exam_submission(%ExamSubmission{} = submission) do
    # Gate checks and the write run in one transaction against freshly locked
    # rows, so the submit can't slip past a concurrently-changed exam status or
    # upload state (TOCTOU). The exam is locked FOR SHARE because its status is
    # only read here — that still excludes `update_exam_status/3`, without
    # blocking concurrent submission inserts. Exam before submission: parent
    # first, per the lock-order rule in ARCHITECTURE.md.
    result =
      Repo.transaction(fn ->
        exam = Repo.lock_one!(Exam, submission.exam_id, :share)
        locked = ExamSubmission |> Repo.lock_one!(submission.id) |> Map.put(:exam, exam)

        cond do
          exam.status != "running" ->
            Repo.rollback(:exam_not_running)

          locked.submitted ->
            Repo.rollback(:already_submitted)

          missing_required_uploads(locked) != [] ->
            Repo.rollback(:missing_required_uploads)

          true ->
            # The hand-in timestamp is written here, inside the same
            # transaction against the same locked row that flips the flag, so
            # the two can never disagree.
            changes = %{
              submitted: true,
              submitted_at: DateTime.utc_now() |> DateTime.truncate(:second)
            }

            case locked |> Ecto.Changeset.change(changes) |> Repo.update() do
              {:ok, updated} -> %{updated | exam: exam}
              {:error, changeset} -> Repo.rollback(changeset)
            end
        end
      end)

    with {:ok, updated} <- result do
      Phoenix.PubSub.broadcast(
        Tasky.PubSub,
        "exam_cockpit:#{updated.exam.id}",
        {:submission_submitted, updated}
      )

      broadcast_exam_event({:submission_submitted, updated.exam, updated.id})

      {:ok, updated}
    end
  end

  # Locks the rows every student-facing write to a submission needs: the exam
  # FOR SHARE (its status is only read, as a guard) and the submission FOR
  # UPDATE. Same order and modes as `submit_exam_submission/1` above, so none of
  # these writes can deadlock against a submit.
  #
  # For file changes the submission lock does double duty: the submit gate
  # counts this submission's files, and a row lock on the submission does *not*
  # pin rows in exam_submission_files — so without taking the same lock here, a
  # required file could be replaced or deleted between that count and the submit
  # write.
  defp lock_submission_for_write!(%ExamSubmission{} = submission) do
    exam = Repo.lock_one!(Exam, submission.exam_id, :share)
    {exam, Repo.lock_one!(ExamSubmission, submission.id)}
  end

  # Rolls the surrounding transaction back unless the student may still write to
  # this submission: only while the exam runs and nothing is handed in. The one
  # gate behind the answer doc *and* the answer files.
  #
  # It is checked here, against the freshly locked rows, rather than in the
  # LiveView, because a LiveView holds the submission it loaded at mount: a
  # stale socket, a late autosave or a replayed event would otherwise still
  # mutate a handed-in submission.
  defp ensure_submission_writable!(%Exam{} = exam, %ExamSubmission{} = submission) do
    cond do
      submission.submitted -> Repo.rollback(:already_submitted)
      exam.status != "running" -> Repo.rollback(:exam_not_running)
      true -> :ok
    end
  end

  # Domain events on the "exam_events" topic — consumed by the correction
  # orchestrator (Tasky.AI.CorrectionOrchestrator), never by this module, so
  # the Exams ↔ BulkCorrectionRunner dependency stays one-way.
  defp broadcast_exam_event(event) do
    Phoenix.PubSub.broadcast(Tasky.PubSub, Tasky.AI.CorrectionOrchestrator.topic(), event)
  end

  @doc """
  Splits a TipTap document into parts, according to the exam's `answer_mode`.

  See `Tasky.ExamDoc.split_content_into_parts/2` — with `"answer_fields"` the
  parts are question-delimited (`h3`), with `"free_document"` the whole
  document is one part.
  """
  defdelegate split_content_into_parts(doc, answer_mode), to: Tasky.ExamDoc
  defdelegate content_preamble(doc, answer_mode), to: Tasky.ExamDoc
  defdelegate assemble_parts_into_content(preamble, parts), to: Tasky.ExamDoc
  defdelegate free_document_part_id(), to: Tasky.ExamDoc

  @doc "True for an exam whose learners edit the whole document."
  def free_document?(%Exam{answer_mode: "free_document"}), do: true
  def free_document?(%Exam{}), do: false

  @doc """
  Returns the decoded submission content for correction.
  Prefers `corrected_content` if present, falls back to the original `content`.
  Both are stored as maps; this helper exists to centralise the precedence rule.
  """
  def correction_content(%ExamSubmission{} = submission) do
    case submission.corrected_content do
      c when is_map(c) and map_size(c) > 0 -> c
      _ -> submission.content || %{}
    end
  end

  # Writes to anything hanging off an exam go through the exam owner (or an
  # admin / the :system scope of a trusted background job). One indexed lookup
  # resolves the owning teacher from the child's exam_id; an exam that is gone
  # is not an authorization pass.
  defp authorize_exam_id(scope, exam_id) do
    case Repo.one(from e in Exam, where: e.id == ^exam_id, select: e.teacher_id) do
      nil -> {:error, :unauthorized}
      teacher_id -> Policy.authorize(scope, teacher_id)
    end
  end

  defp authorize_submission(scope, %ExamSubmission{} = submission),
    do: authorize_exam_id(scope, submission.exam_id)

  @doc ~S"""
  Marks a single part of a submission as corrected (idempotent).
  Broadcasts `{:submission_corrected_parts_changed, submission}` on the
  `exam_correction:#{exam_id}` topic.
  """
  def mark_part_corrected(scope, %ExamSubmission{} = submission, part_id)
      when is_binary(part_id) do
    with :ok <- authorize_submission(scope, submission) do
      update_submission_json(submission, fn locked ->
        %{corrected_parts: Enum.uniq([part_id | locked.corrected_parts || []])}
      end)
    end
  end

  @doc """
  Removes a part from the submission's corrected list.
  """
  def unmark_part_corrected(scope, %ExamSubmission{} = submission, part_id)
      when is_binary(part_id) do
    with :ok <- authorize_submission(scope, submission) do
      update_submission_json(submission, fn locked ->
        %{corrected_parts: Enum.reject(locked.corrected_parts || [], &(&1 == part_id))}
      end)
    end
  end

  # One place for the update-then-broadcast dance — success broadcasts,
  # errors pass through untouched (the divergence-prone pattern this replaces
  # was hand-copied across the context).
  defp update_and_broadcast(changeset, broadcast_fun) do
    with {:ok, updated} <- Repo.update(changeset) do
      broadcast_fun.(updated)
      {:ok, updated}
    end
  end

  # The submission-side twin of `update_exam_json/2`: `fun` gets the row locked
  # FOR UPDATE and returns the changes map, so the list it appends to is always
  # the latest committed one. Without the lock, marking two different parts of
  # the same student corrected from two tabs silently drops one of the flags —
  # and the dropped part then re-enters `list_bulk_correction_jobs/2`, so the
  # next auto-run overwrites the verdicts the teacher just entered there.
  defp update_submission_json(%ExamSubmission{} = submission, fun) when is_function(fun, 1) do
    result =
      Repo.transaction(fn ->
        locked = Repo.lock_one!(ExamSubmission, submission.id)

        case locked |> Ecto.Changeset.change(fun.(locked)) |> Repo.update() do
          {:ok, updated} -> updated
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    with {:ok, updated} <- result do
      broadcast_submission_change(updated)
      {:ok, updated}
    end
  end

  # One place for the read-modify-write over the exam's JSON columns
  # (`sample_solution_points`, `sample_solution_block_points`,
  # `ai_correction_config`). `fun` gets the row locked FOR UPDATE and returns
  # the changes map, so the base map it merges into is always the latest
  # committed one — never the possibly-stale struct a LiveView is holding.
  # Without the lock, two quick clicks in the Musterlösung tab (or the
  # "auto-correct all" toggle landing while a single toggle is in flight) both
  # start from the same base map and one of the writes is lost. This is the
  # same rule the submission-side setters follow; see the lock-order notes in
  # ARCHITECTURE.md before adding a second lock in here.
  defp update_exam_json(%Exam{} = exam, fun) when is_function(fun, 1) do
    Repo.transaction(fn ->
      locked = Repo.lock_one!(Exam, exam.id)

      case locked |> Ecto.Changeset.change(fun.(locked)) |> Repo.update() do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Marks a single part of a submission as AI-auto-corrected (idempotent).
  Broadcasts `{:submission_corrected_parts_changed, submission}`.
  """
  def mark_part_auto_corrected(scope, %ExamSubmission{} = submission, part_id)
      when is_binary(part_id) do
    with :ok <- authorize_submission(scope, submission) do
      update_submission_json(submission, fn locked ->
        %{auto_corrected_parts: Enum.uniq([part_id | locked.auto_corrected_parts || []])}
      end)
    end
  end

  @doc """
  Removes a part from the submission's AI-auto-corrected list.
  """
  def unmark_part_auto_corrected(scope, %ExamSubmission{} = submission, part_id)
      when is_binary(part_id) do
    with :ok <- authorize_submission(scope, submission) do
      update_submission_json(submission, fn locked ->
        %{auto_corrected_parts: Enum.reject(locked.auto_corrected_parts || [], &(&1 == part_id))}
      end)
    end
  end

  @doc """
  Persists the teacher's corrected content for a single part.

  `part_id` identifies the page boundary (the same id returned by
  `split_content_into_parts/2`); `part_nodes` is the new list of nodes for
  that part. The function loads the current correction doc, splits it,
  replaces the matching part, reassembles, and saves back into
  `corrected_content`. Raises if `part_id` is not present.
  """
  def update_corrected_part_content(scope, %ExamSubmission{} = submission, part_id, part_nodes)
      when is_binary(part_id) and is_list(part_nodes) do
    with :ok <- authorize_submission(scope, submission) do
      # Splice runs against a row locked FOR UPDATE so two near-simultaneous
      # part saves can't clobber each other's parts. The exam is locked first
      # (FOR SHARE — only its answer mode is read), keeping the table order of
      # every other grading write.
      Repo.transaction(fn ->
        exam = Repo.lock_one!(Exam, submission.exam_id, :share)
        locked = Repo.lock_one!(ExamSubmission, submission.id)
        doc = correction_content(locked)
        parts = split_content_into_parts(doc, exam.answer_mode)
        preamble = content_preamble(doc, exam.answer_mode)

        unless Enum.any?(parts, &(&1.id == part_id)) do
          raise ArgumentError, "unknown part_id: #{inspect(part_id)}"
        end

        new_parts =
          Enum.map(parts, fn p ->
            if p.id == part_id, do: %{p | nodes: part_nodes}, else: p
          end)

        new_doc = assemble_parts_into_content(preamble, new_parts)

        case locked
             |> Ecto.Changeset.change(%{corrected_content: new_doc})
             |> Repo.update() do
          {:ok, updated} -> updated
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end
  end

  @doc """
  Saves how big each answer field is on the printed paper version.

  Takes the whole document the paper editor sends (like every other editor)
  but persists only `Tasky.ExamPaper.extract_layout/1` of it — a
  `%{answer_id => lines}` map in `paper_layout`. `content` is never touched:
  the paper version sizes a box by putting empty paragraphs inside it, and
  those have no business in the document the learners sit.

  That narrowing is also the guard. The content lock lets the teacher type
  inside an answer field, so the incoming document may carry stray text;
  reading nothing but paragraph counts drops it instead of storing it.
  """
  def update_paper_layout(scope, %Exam{} = exam, doc) when is_map(doc) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      layout = Tasky.ExamPaper.extract_layout(doc)

      update_exam_json(exam, fn _locked -> %{paper_layout: layout} end)
    end
  end

  @doc """
  Saves the structure of the exam from the "Inhalt" tab.

  The document is answer-free (input blocks come back empty from this tab), so
  we do NOT split — we only `ensure_ids/1` and persist as `content`. Any
  entries in `sample_solution` whose block id no longer exists in the new
  content are pruned. Re-runs auto-correction so existing submissions get
  re-graded against the (possibly restructured) exam.
  """
  def save_exam_structure(scope, %Exam{} = exam, doc) when is_map(doc) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      new_content = doc |> AnswerKey.ensure_ids() |> Tasky.ExamDoc.ensure_part_ids()

      # The sample-solution columns must be read from the *locked* row. Reading
      # them off the caller's struct (loaded in the controller, outside any
      # transaction) let a concurrent "Musterlösung" autosave commit in between,
      # and this write then resurrected the stale map — losing a model answer.
      result =
        update_exam_json(exam, fn locked ->
          {pruned_block_points, synced_points} =
            prune_orphan_block_points(
              new_content,
              locked.answer_mode,
              locked.sample_solution_block_points || %{},
              locked.sample_solution_points || %{}
            )

          %{
            content: new_content,
            sample_solution: prune_orphan_answers(new_content, locked.sample_solution || %{}),
            sample_solution_block_points: pruned_block_points,
            sample_solution_points: synced_points
          }
        end)

      with {:ok, updated} <- result do
        broadcast_exam_event({:exam_answers_changed, updated})
        {:ok, updated}
      end
    end
  end

  @doc """
  Saves one part's worth of edits from the "Musterlösung" tab.

  `part_nodes` is the edited (answer-filled) list of nodes for the given part.
  We split it into blanked nodes + the part's answer payloads, splice the
  blanked nodes back into `content`, and merge the new payloads into the
  existing `sample_solution` answers map. Orphan answers (blocks the teacher
  removed) are pruned. Re-runs auto-correction.

  Per the unified-view design, incidental edits to question text in this tab
  are persisted (they ride along with the blanked nodes into `content`).
  """
  def save_sample_solution_part(scope, %Exam{} = exam, part_id, part_nodes)
      when is_binary(part_id) and is_list(part_nodes) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      do_save_sample_solution_part(exam, part_id, part_nodes)
    end
  end

  defp do_save_sample_solution_part(exam, part_id, part_nodes) do
    {blanked_doc, partial_answers} =
      AnswerKey.split(%{"type" => "doc", "content" => part_nodes})

    blanked_part_nodes = Map.get(blanked_doc, "content", [])

    # The splice below is a read-modify-write over the whole content. The
    # stacked Musterlösung view autosaves each part independently, so two
    # near-simultaneous requests for different parts could otherwise clobber
    # each other. Locking the exam row FOR UPDATE serializes them, so the read
    # inside the transaction always sees the latest committed state.
    result =
      Repo.transaction(fn ->
        locked_exam = Repo.lock_one!(Exam, exam.id)

        content = locked_exam.content || %{}
        parts = split_content_into_parts(content, locked_exam.answer_mode)
        preamble = content_preamble(content, locked_exam.answer_mode)

        unless Enum.any?(parts, &(&1.id == part_id)) do
          raise ArgumentError, "unknown part_id: #{inspect(part_id)}"
        end

        new_parts =
          Enum.map(parts, fn p ->
            if p.id == part_id, do: %{p | nodes: blanked_part_nodes}, else: p
          end)

        new_content = assemble_parts_into_content(preamble, new_parts)

        merged_answers =
          (locked_exam.sample_solution || %{})
          |> Map.merge(partial_answers)
          |> then(&prune_orphan_answers(new_content, &1))

        {pruned_block_points, synced_points} =
          prune_orphan_block_points(
            new_content,
            locked_exam.answer_mode,
            locked_exam.sample_solution_block_points || %{},
            locked_exam.sample_solution_points || %{}
          )

        case locked_exam
             |> Exam.changeset(%{
               content: new_content,
               sample_solution: merged_answers,
               sample_solution_block_points: pruned_block_points,
               sample_solution_points: synced_points
             })
             |> Repo.update() do
          {:ok, updated} -> updated
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    with {:ok, updated} <- result do
      broadcast_exam_event({:exam_answers_changed, updated})
      {:ok, updated}
    end
  end

  defp prune_orphan_answers(content, answers) do
    keep_ids = AnswerKey.block_ids(content)
    Map.take(answers, MapSet.to_list(keep_ids))
  end

  # Drops custom block-point entries whose part or answer block no longer
  # exists in `content`, and re-syncs each surviving custom part's total in
  # `points` to the (possibly shrunk) sum. A part whose custom map becomes
  # empty falls back to equal split, keeping its previous total.
  #
  # `points` must be pruned by the surviving part ids too: it is the exam's max
  # points, and an entry left behind for a deleted question inflates the grading
  # denominator forever — silently depressing every student's mark on screen and
  # in the PDF.
  defp prune_orphan_block_points(content, answer_mode, block_points, points) do
    keep_ids = AnswerKey.block_ids(content)
    part_ids = content |> split_content_into_parts(answer_mode) |> MapSet.new(& &1.id)
    part_id_list = MapSet.to_list(part_ids)

    pruned =
      block_points
      |> Enum.filter(fn {pid, _} -> MapSet.member?(part_ids, pid) end)
      |> Enum.map(fn {pid, m} -> {pid, Map.take(m, MapSet.to_list(keep_ids))} end)
      |> Enum.reject(fn {_pid, m} -> m == %{} end)
      |> Map.new()

    synced_points =
      Enum.reduce(pruned, Map.take(points, part_id_list), fn {pid, m}, acc ->
        Map.put(acc, pid, normalize_block_points(Enum.sum(Map.values(m))))
      end)

    {pruned, synced_points}
  end

  @doc """
  Sets (or clears, when `points` is `nil`) the maximum points for a single
  part of an exam's sample solution.
  """
  def set_sample_solution_part_points(scope, %Exam{} = exam, part_id, points)
      when is_binary(part_id) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      do_set_sample_solution_part_points(exam, part_id, points)
    end
  end

  defp do_set_sample_solution_part_points(exam, part_id, points) do
    update_exam_json(exam, fn locked ->
      current = locked.sample_solution_points || %{}

      new_map =
        if is_nil(points) do
          Map.delete(current, part_id)
        else
          Map.put(current, part_id, points)
        end

      %{sample_solution_points: new_map}
    end)
  end

  @doc """
  Returns whether the part uses a custom (unequal) per-block point
  distribution.
  """
  def custom_block_points?(%Exam{} = exam, part_id) when is_binary(part_id) do
    map_size(Map.get(exam.sample_solution_block_points || %{}, part_id) || %{}) > 0
  end

  @doc """
  Resolves the maximum points of every answer block in a part, keyed by the
  block's positional index.

  `blocks` are entries from `NodePatcher.list_answer_blocks/1`, each carrying
  `:index` and `:answer_id`. With a custom distribution
  (`sample_solution_block_points[part_id]` non-empty) each block's points are
  looked up by its `answer_id` — unknown ids count 0. Otherwise the part's
  max points are split equally. Returns `nil` when the part has no points
  configured at all (or has no blocks).
  """
  def resolve_block_points(%Exam{} = exam, part_id, blocks)
      when is_binary(part_id) and is_list(blocks) do
    custom = Map.get(exam.sample_solution_block_points || %{}, part_id) || %{}
    max_points = Map.get(exam.sample_solution_points || %{}, part_id)

    cond do
      blocks == [] ->
        nil

      map_size(custom) > 0 ->
        Map.new(blocks, fn b -> {b.index, block_points_value(Map.get(custom, b.answer_id))} end)

      is_number(max_points) ->
        per = max_points / length(blocks)
        Map.new(blocks, fn b -> {b.index, per} end)

      true ->
        nil
    end
  end

  defp block_points_value(n) when is_number(n), do: n
  defp block_points_value(_), do: 0

  @doc """
  Sets the points for a single answer block of a part (custom distribution).
  The part's total in `sample_solution_points` is kept in sync as the sum of
  all block values.
  """
  def set_sample_solution_block_point(scope, %Exam{} = exam, part_id, answer_id, points)
      when is_binary(part_id) and is_binary(answer_id) and is_number(points) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      do_set_sample_solution_block_point(exam, part_id, answer_id, points)
    end
  end

  defp do_set_sample_solution_block_point(exam, part_id, answer_id, points) do
    update_exam_json(exam, fn locked ->
      part_map =
        (locked.sample_solution_block_points || %{})
        |> Map.get(part_id, %{})
        |> Map.put(answer_id, normalize_block_points(points))

      custom_block_points_changes(locked, part_id, part_map)
    end)
  end

  @doc """
  Enables custom per-block point distribution for a part by seeding every
  answer block with an equal share (rounded to 0.25) of the part's current
  max points. The part total becomes the sum of the seeded shares.
  """
  def enable_custom_block_points(scope, %Exam{} = exam, part_id) when is_binary(part_id) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      do_enable_custom_block_points(exam, part_id)
    end
  end

  defp do_enable_custom_block_points(exam, part_id) do
    update_exam_json(exam, fn locked ->
      blocks = locked |> exam_part_blocks(part_id) |> Enum.filter(& &1.answer_id)
      max_points = Map.get(locked.sample_solution_points || %{}, part_id)

      part_map =
        blocks
        |> Enum.map(& &1.answer_id)
        |> equal_block_shares(max_points)

      custom_block_points_changes(locked, part_id, part_map)
    end)
  end

  # Splits `max_points` over `answer_ids` on the 0.25 grid so the shares sum to
  # *exactly* the part's total. Rounding each share independently would not:
  # 2 points over 3 blocks would give 3 × 0.75 = 2.25, and since the part total
  # is then set to the sum of the shares, merely enabling and clearing custom
  # points again would ratchet the exam's max points up by 0.25 every round.
  defp equal_block_shares(answer_ids, max_points)
       when is_number(max_points) and answer_ids != [] do
    count = length(answer_ids)
    quarters = round(max(max_points, 0) * 4)
    base = div(quarters, count)
    remainder = rem(quarters, count)

    answer_ids
    |> Enum.with_index()
    |> Map.new(fn {answer_id, idx} ->
      share = if idx < remainder, do: base + 1, else: base
      {answer_id, normalize_block_points(share / 4)}
    end)
  end

  defp equal_block_shares(answer_ids, _max_points), do: Map.new(answer_ids, &{&1, 0})

  @doc """
  Disables custom distribution for a part. The part keeps its current total
  in `sample_solution_points` and falls back to the equal split.
  """
  def clear_custom_block_points(scope, %Exam{} = exam, part_id) when is_binary(part_id) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      update_exam_json(exam, fn locked ->
        %{
          sample_solution_block_points:
            Map.delete(locked.sample_solution_block_points || %{}, part_id)
        }
      end)
    end
  end

  # Changes that put a part's custom distribution in place. The part's total in
  # `sample_solution_points` is always the sum of its per-block values, so the
  # two columns only ever move together. Pure — the caller supplies the locked
  # exam and writes the result.
  defp custom_block_points_changes(%Exam{} = exam, part_id, part_map) do
    total = part_map |> Map.values() |> Enum.sum() |> normalize_block_points()

    %{
      sample_solution_block_points:
        Map.put(exam.sample_solution_block_points || %{}, part_id, part_map),
      sample_solution_points: Map.put(exam.sample_solution_points || %{}, part_id, total)
    }
  end

  defp normalize_block_points(n) when is_number(n) do
    rounded = Grading.round_quarter(max(n, 0))
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end

  defp exam_part_blocks(%Exam{} = exam, part_id) do
    (exam.content || %{})
    |> split_content_into_parts(exam.answer_mode)
    |> Enum.find(&(&1.id == part_id))
    |> case do
      nil -> []
      part -> NodePatcher.list_answer_blocks(part.nodes)
    end
  end

  @doc """
  Sets (or clears, when `points` is `nil`) the points awarded for a single
  part of a submission. Broadcasts the updated submission so the correction
  grid stays in sync.
  """
  def set_part_points(scope, %ExamSubmission{} = submission, part_id, points)
      when is_binary(part_id) do
    with :ok <- authorize_submission(scope, submission) do
      do_set_part_points(submission, part_id, points)
    end
  end

  defp do_set_part_points(submission, part_id, points) do
    result =
      Repo.transaction(fn ->
        # Exam first (FOR SHARE — only its max points are read), then the
        # submission, matching the order of every other grading write.
        exam = Repo.lock_one!(Exam, submission.exam_id, :share)
        locked = Repo.lock_one!(ExamSubmission, submission.id)
        current = locked.points_per_part || %{}

        # `step`/`max` on the number input are client-side only: without this a
        # crafted event stores a negative or absurd value ("1e3" parses to 1000)
        # straight into the exam total.
        part_max = Map.get(exam.sample_solution_points || %{}, part_id)

        new_map =
          if is_nil(points) do
            Map.delete(current, part_id)
          else
            Map.put(current, part_id, Grading.normalize_manual_points(points, part_max))
          end

        case locked
             |> Ecto.Changeset.change(%{points_per_part: new_map})
             |> Repo.update() do
          {:ok, updated} -> updated
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    with {:ok, updated} <- result do
      broadcast_submission_change(updated)
      {:ok, updated}
    end
  end

  @doc """
  Lists the answer-bearing blocks in a single part of a submission, paired
  with the teacher's current verdict for each (if any).

  Each entry is `%{index: i, text: t, verdict: v}` where `v` is `"correct"`,
  `"half"` (legacy), `"wrong"`, a number (manual points) or `nil`.
  Verdicts are keyed by the block's stable `answerId` in
  `submission.block_verdicts`.
  """
  def list_part_answer_blocks(%Exam{} = exam, %ExamSubmission{} = submission, part_id)
      when is_binary(part_id) do
    parts =
      submission
      |> correction_content()
      |> split_content_into_parts(exam.answer_mode)

    case Enum.find(parts, &(&1.id == part_id)) do
      nil ->
        []

      part ->
        explicit = submission.block_verdicts || %{}

        part.nodes
        |> NodePatcher.list_answer_blocks()
        |> Enum.map(fn entry ->
          verdict =
            (entry.answer_id && Map.get(explicit, entry.answer_id)) || entry.inferred_verdict

          Map.put(entry, :verdict, verdict)
        end)
    end
  end

  @doc """
  Sets (or clears, when `verdict` is `nil`) the teacher's verdict for a
  single answer block in a single part of a submission.

  The verdict is either `"correct"` (full block points), `"wrong"` (0),
  a number (manual points for the block, clamped to `[0, block_max]` and
  rounded to 0.25 steps), or `nil` to clear. Legacy `"half"` values remain
  readable (0.5 × block points) but are no longer written by the UI.

  Persists three things atomically:
    * `block_verdicts` — keyed by the block's stable `answerId`
    * `corrected_content` — the trailing ✅/🟡/❌ marker on the affected
      node is rewritten to match the new verdict
    * `points_per_part[part_id]` — recomputed as the sum of each block's
      awarded points (per-block max from `resolve_block_points/3`), rounded
      to 0.25 increments. If the part has no points configured or no
      answer blocks, the entry is removed.

  Broadcasts the updated submission so the correction grid stays in sync.
  """
  def set_block_verdict(scope, %ExamSubmission{} = submission, part_id, index, verdict)
      when is_binary(part_id) and is_integer(index) and
             (verdict in ["correct", "half", "wrong", nil] or is_number(verdict)) do
    with :ok <- authorize_submission(scope, submission) do
      do_set_block_verdict(submission, part_id, index, verdict)
    end
  end

  # The read-modify-write over the three JSON columns runs against locked rows,
  # so a concurrent write (teacher click during a bulk-correction run) can never
  # be lost. Exam first (FOR SHARE — its block points are only read), then the
  # submission (FOR UPDATE): the bulk variants below take the same order, and
  # reversing it here would let the two deadlock against each other.
  defp do_set_block_verdict(submission, part_id, index, verdict) do
    result =
      Repo.transaction(fn ->
        exam = Repo.lock_one!(Exam, submission.exam_id, :share)
        locked = Repo.lock_one!(ExamSubmission, submission.id)

        case block_verdict_changes(locked, exam, part_id, index, verdict) do
          {:ok, changes} ->
            case locked |> Ecto.Changeset.change(changes) |> Repo.update() do
              {:ok, updated} -> updated
              {:error, changeset} -> Repo.rollback(changeset)
            end

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)

    with {:ok, updated} <- result do
      broadcast_submission_change(updated)
      {:ok, updated}
    end
  end

  # Pure computation of the three-column update for one verdict change.
  defp block_verdict_changes(submission, exam, part_id, index, verdict) do
    part_verdict_changes(submission, exam, part_id, %{index => verdict})
  end

  # Same, for any number of blocks of one part at once.
  #
  # Doing several blocks together is not just batching: the part total, the
  # ✅/🟡/❌ markers and the doc reassembly are whole-part operations either
  # way, and only resolving each index's answerId and normalizing its points is
  # per-block. So a bulk change costs one split of the doc and one write, where
  # looping over `block_verdict_changes/5` cost one of each per block.
  #
  # `:only_unset` (for the mark-all defaults) keeps blocks the teacher already
  # judged and silently skips indices with no answer-bearing block, rather than
  # failing the whole operation over one.
  defp part_verdict_changes(submission, exam, part_id, verdicts_by_index, opts \\ []) do
    doc = correction_content(submission)
    parts = split_content_into_parts(doc, exam.answer_mode)
    preamble = content_preamble(doc, exam.answer_mode)

    case Enum.find(parts, &(&1.id == part_id)) do
      nil ->
        {:error, :unknown_part}

      part ->
        blocks = NodePatcher.list_answer_blocks(part.nodes)

        with {:ok, keyed} <- key_verdicts(submission, blocks, verdicts_by_index, opts) do
          ctx = %{part_id: part_id, parts: parts, preamble: preamble, part: part, blocks: blocks}
          {:ok, part_verdict_changes_for_keys(submission, exam, ctx, keyed)}
        end
    end
  end

  # Resolves each requested block index to the block's stable answerId, so that
  # inserting or reordering blocks never shifts existing verdicts. Returns
  # `%{answer_id => {index, verdict}}`.
  defp key_verdicts(submission, blocks, verdicts_by_index, opts) do
    only_unset? = Keyword.get(opts, :only_unset, false)
    explicit = submission.block_verdicts || %{}

    Enum.reduce_while(verdicts_by_index, {:ok, %{}}, fn {index, verdict}, {:ok, acc} ->
      case Enum.find(blocks, &(&1.index == index)) do
        %{answer_id: key} when is_binary(key) ->
          # Under :only_unset a block the teacher has already judged keeps that
          # verdict — a default must never overwrite an explicit choice.
          if only_unset? and (is_nil(verdict) or Map.has_key?(explicit, key)) do
            {:cont, {:ok, acc}}
          else
            {:cont, {:ok, Map.put(acc, key, {index, verdict})}}
          end

        _ ->
          if only_unset?,
            do: {:cont, {:ok, acc}},
            else: {:halt, {:error, :unknown_block}}
      end
    end)
  end

  defp part_verdict_changes_for_keys(_submission, _exam, _ctx, keyed) when keyed == %{}, do: %{}

  defp part_verdict_changes_for_keys(submission, exam, ctx, keyed) do
    %{part_id: part_id, parts: parts, preamble: preamble, part: part, blocks: blocks} = ctx

    points_by_index = resolve_block_points(exam, part_id, blocks)

    new_verdicts =
      Enum.reduce(keyed, submission.block_verdicts || %{}, fn {key, {index, verdict}}, acc ->
        case normalize_verdict(verdict, points_by_index && points_by_index[index]) do
          nil -> Map.delete(acc, key)
          normalized -> Map.put(acc, key, normalized)
        end
      end)

    # Effective verdict for each block: explicit teacher choice if any,
    # otherwise fall back to the verdict inferred from the existing
    # ✅/🟡/❌ marker on the node (e.g. left by AI auto-correction).
    # This ensures untouched blocks keep their markers and contribute
    # their points when the teacher only edits a single block.
    effective_indexed = effective_verdicts_for_part(blocks, new_verdicts)

    new_part_points = compute_part_points(effective_indexed, points_by_index)

    new_points_per_part =
      if is_nil(new_part_points) do
        Map.delete(submission.points_per_part || %{}, part_id)
      else
        Map.put(submission.points_per_part || %{}, part_id, new_part_points)
      end

    marker_verdicts = marker_verdicts(effective_indexed, points_by_index)
    rewritten_nodes = NodePatcher.rewrite_markers(part.nodes, marker_verdicts)

    new_parts =
      Enum.map(parts, fn p ->
        if p.id == part_id, do: %{p | nodes: rewritten_nodes}, else: p
      end)

    %{
      block_verdicts: new_verdicts,
      corrected_content: assemble_parts_into_content(preamble, new_parts),
      points_per_part: new_points_per_part
    }
  end

  defp broadcast_submission_change(submission) do
    Phoenix.PubSub.broadcast(
      Tasky.PubSub,
      "exam_correction:#{submission.exam_id}",
      {:submission_corrected_parts_changed, submission}
    )
  end

  @doc """
  Persists one auto-corrected part in a single transaction: the
  marker-annotated nodes into `corrected_content`, the authoritative
  per-block verdicts (keyed by the blocks' `answerId`s) into
  `block_verdicts`, the part's points and the auto-corrected flag. Used by
  the bulk-correction runner — one atomic write instead of three racy ones,
  and grading no longer depends on re-inferring the runner's verdicts from
  the ✅/🟡/❌ markers.

  The part total is recomputed here from the verdicts actually stored, the
  same way `part_verdict_changes_for_keys/4` computes it for a manual edit.
  The runner does not pass a total: it only knows the verdicts it proposed,
  and a re-run keeps the teacher's verdicts for blocks they already judged,
  so the runner's own sum would be wrong for exactly those parts.
  """
  def apply_auto_correction(scope, %ExamSubmission{} = submission, part_id, part_nodes, opts)
      when is_binary(part_id) and is_list(part_nodes) do
    verdicts = Keyword.get(opts, :verdicts, %{})

    with :ok <- authorize_submission(scope, submission) do
      result =
        Repo.transaction(fn ->
          # Exam first (FOR SHARE — only its block points are read), then the
          # submission (FOR UPDATE): the same order every other grading write
          # takes, so this cannot deadlock against them.
          exam = Repo.lock_one!(Exam, submission.exam_id, :share)
          locked = Repo.lock_one!(ExamSubmission, submission.id)
          doc = correction_content(locked)
          parts = split_content_into_parts(doc, exam.answer_mode)
          preamble = content_preamble(doc, exam.answer_mode)

          unless Enum.any?(parts, &(&1.id == part_id)) do
            Repo.rollback(:unknown_part)
          end

          current = locked.block_verdicts || %{}
          prev_auto = locked.auto_block_verdicts || %{}
          manual_keys = manual_verdict_keys(current, prev_auto, Map.keys(verdicts))

          {merged_verdicts, merged_auto} =
            merge_auto_verdicts(current, prev_auto, verdicts, manual_keys)

          blocks = NodePatcher.list_answer_blocks(part_nodes)
          points_by_index = resolve_block_points(exam, part_id, blocks)

          # The markers must follow the verdicts we actually store — otherwise a
          # block the teacher already judged keeps the machine's ✅/❌.
          marked_nodes =
            NodePatcher.rewrite_markers(
              part_nodes,
              marker_verdicts_by_index(blocks, merged_verdicts, points_by_index)
            )

          new_parts =
            Enum.map(parts, fn p ->
              if p.id == part_id, do: %{p | nodes: marked_nodes}, else: p
            end)

          # Recomputed from what we are about to store, never frozen and never
          # taken from the runner. A re-run refreshes every block the teacher
          # has *not* judged — verdicts and markers both — so a total carried
          # over from the last manual write would contradict both of them.
          # Same helpers as the manual path, so the two agree by construction.
          new_part_points =
            blocks
            |> effective_verdicts_for_part(merged_verdicts)
            |> compute_part_points(points_by_index)

          new_points =
            if is_nil(new_part_points) do
              Map.delete(locked.points_per_part || %{}, part_id)
            else
              Map.put(locked.points_per_part || %{}, part_id, new_part_points)
            end

          changes = %{
            corrected_content: assemble_parts_into_content(preamble, new_parts),
            block_verdicts: merged_verdicts,
            auto_block_verdicts: merged_auto,
            points_per_part: new_points,
            auto_corrected_parts: Enum.uniq([part_id | locked.auto_corrected_parts || []])
          }

          case locked |> Ecto.Changeset.change(changes) |> Repo.update() do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      with {:ok, updated} <- result do
        broadcast_submission_change(updated)
        {:ok, updated}
      end
    end
  end

  # A block whose stored verdict still equals what the auto-corrector last wrote
  # is the machine's own and may be refreshed. Anything else — a verdict the
  # teacher set, or changed — is theirs, and a re-run must not touch it.
  defp manual_verdict_keys(current, prev_auto, keys) do
    Enum.filter(keys, fn key ->
      Map.has_key?(current, key) and Map.get(current, key) != Map.get(prev_auto, key)
    end)
  end

  defp merge_auto_verdicts(current, prev_auto, incoming, manual_keys) do
    manual = MapSet.new(manual_keys)

    Enum.reduce(incoming, {current, prev_auto}, fn {key, verdict}, {verdicts, auto} ->
      if MapSet.member?(manual, key) do
        {verdicts, auto}
      else
        {Map.put(verdicts, key, verdict), Map.put(auto, key, verdict)}
      end
    end)
  end

  defp marker_verdicts_by_index(blocks, verdicts, points_by_index) do
    Map.new(blocks, fn block ->
      verdict = Map.get(verdicts, block.answer_id)

      {block.index,
       Grading.marker_verdict(verdict, points_by_index && points_by_index[block.index])}
    end)
  end

  @doc """
  Un-marks a part as corrected on every submission of the exam — one
  transaction instead of N racy writes. Leaves `block_verdicts` untouched so
  re-marking doesn't lose teacher overrides.
  """
  def unmark_part_corrected_bulk(scope, %Exam{} = exam, part_id) when is_binary(part_id) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      result =
        Repo.transaction(fn ->
          for submission <- lock_exam_submissions!(exam) do
            parts = Enum.reject(submission.corrected_parts || [], &(&1 == part_id))

            case submission
                 |> Ecto.Changeset.change(%{corrected_parts: parts})
                 |> Repo.update() do
              {:ok, updated} -> updated
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end
        end)

      with {:ok, updated} <- result do
        Enum.each(updated, &broadcast_submission_change/1)
        {:ok, updated}
      end
    end
  end

  @doc """
  Marks a part as corrected on every submission of the exam, first persisting
  the given default verdicts for blocks the teacher left untouched (no
  explicit verdict yet), so points get tallied. `defaults` maps
  `submission_id => %{block_index => verdict}`. One transaction for the whole
  operation instead of N×M racy writes.
  """
  def mark_part_corrected_bulk(scope, %Exam{} = exam, part_id, defaults)
      when is_binary(part_id) and is_map(defaults) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      result =
        Repo.transaction(fn ->
          exam = Repo.lock_one!(Exam, exam.id, :share)

          for submission <- lock_exam_submissions!(exam) do
            mark_one_corrected!(submission, exam, part_id, Map.get(defaults, submission.id, %{}))
          end
        end)

      with {:ok, updated} <- result do
        Enum.each(updated, &broadcast_submission_change/1)
        {:ok, updated}
      end
    end
  end

  # One submission, one write: the whole part's default verdicts and the
  # corrected-parts flag go into a single changeset. This runs while every
  # submission row of the exam is locked FOR UPDATE, so a write per (submission,
  # block) — which is what looping over the single-block path amounted to — kept
  # the whole class's rows locked far longer than it needed to.
  defp mark_one_corrected!(submission, exam, part_id, defaults) do
    changes =
      case part_verdict_changes(submission, exam, part_id, defaults, only_unset: true) do
        {:ok, changes} -> changes
        # An unknown part is nothing to fill in, but marking it corrected is
        # still what the teacher asked for.
        {:error, _reason} -> %{}
      end

    changes =
      Map.put(changes, :corrected_parts, Enum.uniq([part_id | submission.corrected_parts || []]))

    case submission |> Ecto.Changeset.change(changes) |> Repo.update() do
      {:ok, updated} -> updated
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Sets the same block verdict on many submissions of the exam at once (the
  grouped bulk-correction view) — one transaction instead of N racy writes.
  Unknown submission ids are ignored; returns `{:ok, updated_submissions}`.

  A submission in which the part or block cannot be resolved is **skipped**,
  not fatal. The grouped view builds its groups over every submission of the
  exam, so one student who enrolled and never opened the exam lands in the
  "keine Antwort" group with an empty document — and rolling the batch back for
  them left every other student in the group ungraded, with nothing on screen to
  say why. `mark_part_corrected_bulk/3` already tolerates exactly this.
  """
  def set_block_verdict_bulk(scope, %Exam{} = exam, part_id, index, verdict, submission_ids)
      when is_binary(part_id) and is_integer(index) and is_list(submission_ids) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      result =
        Repo.transaction(fn ->
          exam = Repo.lock_one!(Exam, exam.id, :share)

          for submission <- lock_submissions_by_ids!(exam, submission_ids),
              {:ok, changes} <-
                [block_verdict_changes(submission, exam, part_id, index, verdict)] do
            case submission |> Ecto.Changeset.change(changes) |> Repo.update() do
              {:ok, updated} -> updated
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end
        end)

      with {:ok, updated_submissions} <- result do
        Enum.each(updated_submissions, &broadcast_submission_change/1)
        {:ok, updated_submissions}
      end
    end
  end

  defp effective_verdicts_for_part(blocks, explicit_verdicts) do
    Enum.reduce(blocks, %{}, fn entry, acc ->
      case entry.answer_id && Map.get(explicit_verdicts, entry.answer_id) do
        nil ->
          case entry.inferred_verdict do
            nil -> acc
            v -> Map.put(acc, entry.index, v)
          end

        v ->
          Map.put(acc, entry.index, v)
      end
    end)
  end

  @doc """
  The teacher's explicit verdict for the block at `index` in the given part,
  or nil. Resolves the block's stable answerId from the submission's doc.
  """
  def explicit_block_verdict(%Exam{} = exam, %ExamSubmission{} = submission, part_id, index)
      when is_binary(part_id) and is_integer(index) do
    parts = submission |> correction_content() |> split_content_into_parts(exam.answer_mode)

    with %{} = part <- Enum.find(parts, &(&1.id == part_id)),
         %{answer_id: answer_id} when is_binary(answer_id) <-
           part.nodes |> NodePatcher.list_answer_blocks() |> Enum.find(&(&1.index == index)) do
      Map.get(submission.block_verdicts || %{}, answer_id)
    else
      _ -> nil
    end
  end

  # Manual numeric verdicts are rounded to 0.25 steps and clamped to the
  # block's max points (when known). String verdicts pass through.
  defp normalize_verdict(v, block_max) when is_number(v),
    do: Grading.normalize_manual_points(v, block_max)

  defp normalize_verdict(v, _block_max), do: v

  defp compute_part_points(indexed, points_by_index),
    do: Grading.part_points(indexed, points_by_index)

  # Maps numeric (manual) verdicts to the marker vocabulary understood by
  # NodePatcher.rewrite_markers: full block points → ✅, zero → ❌, else 🟡.
  defp marker_verdicts(indexed, points_by_index) do
    Map.new(indexed, fn
      {idx, v} when is_number(v) ->
        {idx, Grading.marker_verdict(v, points_by_index && points_by_index[idx])}

      {idx, v} ->
        {idx, v}
    end)
  end

  @doc """
  Updates the grading max-points override for the exam. Pass `nil` to clear
  the override (the grading view then falls back to the sum of
  `sample_solution_points`).

  The value is validated here rather than in the LiveView because a bad max
  divides into *every* mark of the exam: a negative one clamps the whole class
  to 1.0, a zero removes every mark. Same reasoning as `set_part_points/4`.
  """
  def update_grading_max_points(scope, %Exam{} = exam, value) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         {:ok, normalized} <- normalize_grading_max_points(value) do
      exam
      |> Ecto.Changeset.change(%{grading_max_points: normalized})
      |> Repo.update()
    end
  end

  defp normalize_grading_max_points(nil), do: {:ok, nil}

  defp normalize_grading_max_points(value) when is_number(value) do
    case Grading.normalize_points(value) do
      n when n > 0 -> {:ok, n / 1}
      _ -> {:error, :invalid_max_points}
    end
  end

  defp normalize_grading_max_points(_), do: {:error, :invalid_max_points}

  @doc """
  Sets (or clears, when `mark` is `nil`) the teacher-adjusted final mark for
  a submission. The mark is stored as a float; when `nil`, callers should
  fall back to the calculated mark from `points / max_points`.
  """
  def set_submission_mark(scope, %ExamSubmission{} = submission, mark) do
    with :ok <- authorize_submission(scope, submission),
         {:ok, normalized} <- normalize_submission_mark(mark) do
      submission
      |> Ecto.Changeset.change(%{mark: normalized})
      |> Repo.update()
    end
  end

  defp normalize_submission_mark(nil), do: {:ok, nil}

  defp normalize_submission_mark(mark) when is_number(mark),
    do: {:ok, Grading.normalize_mark(mark) / 1}

  defp normalize_submission_mark(_), do: {:error, :invalid_mark}

  @doc """
  Updates the AI correction configuration for a single part of an exam.
  The config is stored as a map keyed by part_id.
  """
  def update_ai_correction_config(scope, %Exam{} = exam, part_id, config)
      when is_binary(part_id) and is_map(config) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      update_exam_json(exam, fn locked ->
        %{ai_correction_config: Map.put(locked.ai_correction_config || %{}, part_id, config)}
      end)
    end
  end

  @doc """
  Bulk-updates the AI correction configuration for multiple parts at once.
  `updates` is a map of `%{part_id => %{key => value, ...}, ...}`.
  Each part's config is merged with the existing config for that part.
  """
  def update_ai_correction_config_bulk(scope, %Exam{} = exam, updates) when is_map(updates) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      update_exam_json(exam, fn locked ->
        merged =
          Enum.reduce(updates, locked.ai_correction_config || %{}, fn {part_id, new_config},
                                                                      acc ->
            existing = Map.get(acc, part_id, %{})
            Map.put(acc, part_id, Map.merge(existing, new_config))
          end)

        %{ai_correction_config: merged}
      end)
    end
  end

  @doc """
  Counts how many parts of the exam are enabled for automatic AI correction.
  """
  def count_auto_correct_parts(%Exam{} = exam) do
    config = exam.ai_correction_config || %{}

    Enum.count(config, fn {_part_id, part_config} ->
      is_map(part_config) and Map.get(part_config, "auto_correct") == true
    end)
  end

  @doc """
  Enumerates correction job descriptors eligible for bulk AI correction across
  all submissions of the exam. Each job carries `ignore_spelling` and
  `ignore_case` flags from the per-part config. Excludes parts without a
  max-points entry or without content for that submission.

  Always empty for a `free_document` exam: auto-correction compares answer
  fields against a sample solution, and such an exam has neither. Without this
  the runner would still produce jobs that each fail with `:no_answer_fields`.

  Jobs are grouped by `part_id` (all submissions for part A, then all for
  part B, ...) so that consecutive Anthropic calls reuse the same cached
  system prefix (rules + sample solution) within the 5-minute cache TTL.
  """
  def list_bulk_correction_jobs(exam, opts \\ [])

  def list_bulk_correction_jobs(%Exam{answer_mode: "free_document"}, _opts), do: []

  def list_bulk_correction_jobs(%Exam{} = exam, opts) do
    config = exam.ai_correction_config || %{}
    max_points_map = exam.sample_solution_points || %{}
    submission_filter = Keyword.get(opts, :submission_id)

    auto_correct_part_ids =
      for {part_id, part_config} <- config,
          is_map(part_config),
          Map.get(part_config, "auto_correct") == true,
          Map.get(max_points_map, part_id) not in [nil, 0],
          into: MapSet.new(),
          do: part_id

    if MapSet.size(auto_correct_part_ids) == 0 do
      []
    else
      exam
      |> list_exam_submissions()
      |> Enum.filter(fn s ->
        s.submitted and (is_nil(submission_filter) or s.id == submission_filter)
      end)
      |> Enum.flat_map(fn submission ->
        parts =
          submission
          |> correction_content()
          |> split_content_into_parts(exam.answer_mode)

        for part <- parts,
            MapSet.member?(auto_correct_part_ids, part.id),
            part.nodes != [],
            part.id not in (submission.corrected_parts || []) do
          part_cfg = Map.get(config, part.id, %{})

          %{
            submission_id: submission.id,
            part_id: part.id,
            ignore_spelling: Map.get(part_cfg, "ignore_spelling", false) == true,
            ignore_case: Map.get(part_cfg, "ignore_case", false) == true
          }
        end
      end)
      |> Enum.sort_by(& &1.part_id)
    end
  end

  @doc """
  Groups the answers given by every submission to a single part, one group per
  unique answer text, paired with the system's pre-judged verdict against the
  sample solution and the teacher's current verdict (if any).

  Returns a list of `%{index, label, max_points, sample_answers, groups}` —
  one entry per answer-bearing block in the part, in document order.
  `max_points` is the block's share resolved via `resolve_block_points/3`
  (`nil` when the part has no points configured). Within `groups`:

      %{
        text: "fliegen" | nil,            # nil = "no answer"
        count: 18,
        students: [%{submission_id, firstname, lastname}, ...],
        default_verdict: "correct" | "wrong",
        current_verdict: "correct" | "half" | "wrong" | number | nil | :mixed,
        diff: [{:eq | :ins | :del, string}, ...],
        nearest_sample: "fliegen" | nil
      }

  `current_verdict` is `nil` when no submission in the group has an explicit
  teacher verdict, `:mixed` when submissions disagree, otherwise the shared
  value. `default_verdict` honors the part's `ignore_case`/`ignore_spelling`
  options, using the same matcher (`Tasky.Correction.StringComparator.text_match?/3`)
  as auto-correction.
  """
  def list_part_answer_groups(%Exam{} = exam, part_id) when is_binary(part_id) do
    part_cfg = Map.get(exam.ai_correction_config || %{}, part_id, %{})

    opts = %{
      ignore_case: Map.get(part_cfg, "ignore_case", false) == true,
      ignore_spelling: Map.get(part_cfg, "ignore_spelling", false) == true
    }

    sample_part =
      exam
      |> sample_solution_doc()
      |> split_content_into_parts(exam.answer_mode)
      |> Enum.find(&(&1.id == part_id))

    sample_blocks =
      case sample_part do
        nil -> []
        p -> NodePatcher.list_answer_blocks(p.nodes)
      end

    sample_text_by_index =
      Enum.into(sample_blocks, %{}, fn b -> {b.index, b.text} end)

    exam_part =
      (exam.content || %{})
      |> split_content_into_parts(exam.answer_mode)
      |> Enum.find(&(&1.id == part_id))

    labels_by_index =
      case exam_part do
        nil -> %{}
        p -> Tasky.ExamDoc.answer_block_labels(p.nodes)
      end

    exam_blocks =
      case exam_part do
        nil -> sample_blocks
        p -> NodePatcher.list_answer_blocks(p.nodes)
      end

    exam_block_indices = Enum.map(exam_blocks, & &1.index)
    points_by_index = resolve_block_points(exam, part_id, exam_blocks)

    submissions = list_exam_submissions(exam)

    per_submission_blocks =
      Enum.map(submissions, fn sub ->
        blocks =
          sub
          |> correction_content()
          |> split_content_into_parts(exam.answer_mode)
          |> Enum.find(&(&1.id == part_id))
          |> case do
            nil -> []
            p -> NodePatcher.list_answer_blocks(p.nodes)
          end

        {sub, blocks}
      end)

    Enum.map(exam_block_indices, fn index ->
      sample_text = Map.get(sample_text_by_index, index)

      sample_answers = AnswerVariants.split(sample_text)

      groups = build_answer_groups(per_submission_blocks, index, sample_answers, opts)

      %{
        index: index,
        label: Map.get(labels_by_index, index),
        max_points: points_by_index && Map.get(points_by_index, index),
        sample_answers: sample_answers,
        groups: groups
      }
    end)
  end

  defp build_answer_groups(per_submission_blocks, index, sample_answers, opts) do
    entries =
      Enum.map(per_submission_blocks, fn {sub, blocks} ->
        case Enum.find(blocks, &(&1.index == index)) do
          nil -> {sub, nil, nil}
          %{text: t, answer_id: id} -> {sub, normalize_group_text(t), id}
        end
      end)

    entries
    |> Enum.group_by(fn {_sub, text, _id} -> text end)
    |> Enum.map(fn {text, members} ->
      subs_with_ids = Enum.map(members, fn {sub, _text, id} -> {sub, id} end)
      build_one_group(text, subs_with_ids, sample_answers, opts)
    end)
    |> Enum.sort_by(fn g -> -g.count end)
  end

  defp build_one_group(text, subs_with_ids, sample_answers, opts) do
    subs = Enum.map(subs_with_ids, fn {sub, _id} -> sub end)

    # Verdicts are keyed by each submission's own block answerId.
    verdicts =
      Enum.map(subs_with_ids, fn {s, answer_id} ->
        answer_id && Map.get(s.block_verdicts || %{}, answer_id)
      end)

    current_verdict =
      case Enum.uniq(verdicts) do
        [v] -> v
        _ -> :mixed
      end

    default_verdict = default_group_verdict(text, sample_answers, opts)
    nearest = nearest_sample(text, sample_answers)
    diff = diff_against(text, nearest)

    students =
      Enum.map(subs, fn s ->
        %{submission_id: s.id, firstname: s.firstname, lastname: s.lastname}
      end)

    %{
      text: text,
      count: length(subs),
      students: students,
      default_verdict: default_verdict,
      current_verdict: current_verdict,
      diff: diff,
      nearest_sample: nearest
    }
  end

  defp normalize_group_text(nil), do: nil

  defp normalize_group_text(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      t -> t
    end
  end

  defp default_group_verdict(nil, _samples, _opts), do: "wrong"
  defp default_group_verdict(_text, [], _opts), do: "wrong"

  defp default_group_verdict(text, samples, opts) do
    trimmed = String.trim(text)

    if trimmed != "" and
         Enum.any?(samples, &Tasky.Correction.StringComparator.text_match?(trimmed, &1, opts)),
       do: "correct",
       else: "wrong"
  end

  defp nearest_sample(nil, _), do: nil
  defp nearest_sample(_text, []), do: nil

  defp nearest_sample(_text, [single]), do: single

  defp nearest_sample(text, samples) do
    lower = String.downcase(text)

    Enum.max_by(samples, fn s ->
      String.jaro_distance(lower, String.downcase(s))
    end)
  end

  defp diff_against(nil, _), do: []
  defp diff_against(text, nil), do: [{:eq, text}]
  defp diff_against(text, sample), do: String.myers_difference(text, sample)

  @doc """
  Reconstructs the answer-filled "sample solution" document by merging the
  exam's answer-free `content` with the stored answers map (`sample_solution`).
  This is the single reconstruction point used by correction and previews.
  """
  def sample_solution_doc(%Exam{} = exam) do
    AnswerKey.merge(exam.content || %{}, exam.sample_solution || %{})
  end

  @doc """
  Dieselbe Musterlösung, aber für Teilnehmende statt für die Korrektur.

  Der einzige Unterschied ist das `;`: mehrere gültige Antworten werden zu
  `"pdf, .pdf"` aufgelöst (siehe `Tasky.Correction.AnswerVariants`). Das
  darf **nicht** in `sample_solution_doc/1` selbst passieren — daran hängen die
  Autokorrektur und die Editoren der Lehrperson, und beide brauchen das rohe
  Trennzeichen.
  """
  def sample_solution_doc_for_learner(%Exam{} = exam),
    do: exam |> sample_solution_doc() |> AnswerVariants.humanize_doc()

  @doc """
  Die Verdikte einer Abgabe, keyed by `answerId`, für die Anzeige bei Lernenden.

  `"correct"`, `"half"` oder `"wrong"` — dasselbe Vokabular, das
  `Tasky.Correction.SolutionHints` an den Antwortknoten schreibt. Manuell
  vergebene Teilpunkte werden dafür über `Grading.marker_verdict/2` aufgelöst,
  mit dem Blockmaximum aus `resolve_block_points/3`: derselbe Pfad, den auch
  `set_block_verdict/5` beim Setzen der ✅/🟡/❌ nimmt.

  `block_verdicts` ist die verbindliche Quelle. Der Textmarker im korrigierten
  Dokument dient nur als Rückfall für Blöcke, die noch aus einer Bulk-Korrektur
  stammen und deren Verdikt nie einzeln gespeichert wurde.
  """
  @spec learner_verdicts(Exam.t(), ExamSubmission.t()) :: %{String.t() => String.t()}
  def learner_verdicts(%Exam{} = exam, %ExamSubmission{} = submission) do
    explicit = submission.block_verdicts || %{}

    submission
    |> correction_content()
    |> split_content_into_parts(exam.answer_mode)
    |> Enum.reduce(%{}, fn part, acc ->
      blocks = NodePatcher.list_answer_blocks(part.nodes)
      points = resolve_block_points(exam, part.id, blocks)

      Enum.reduce(blocks, acc, fn entry, acc ->
        verdict =
          (entry.answer_id && Map.get(explicit, entry.answer_id)) || entry.inferred_verdict

        if is_binary(entry.answer_id) and not is_nil(verdict) do
          block_max = points && Map.get(points, entry.index)
          Map.put(acc, entry.answer_id, Grading.marker_verdict(verdict, block_max))
        else
          acc
        end
      end)
    end)
  end

  @doc """
  Das zurückgegebene Dokument mit der Musterlösung an den Antwortfeldern.

  `base_doc` ist, was die/der Lernende ohnehin zu sehen bekäme — die Korrektur
  der Lehrperson oder die eigenen Antworten. `verdicts` ist `learner_verdicts/2`
  oder `%{}`, wenn die Korrektur nicht freigegeben ist.

  Sobald Verdikte mitkommen, fallen die Textmarker ✅/🟡/❌ weg: das Verdikt hängt
  dann als Attribut am Knoten und wird vom Stylesheet gezeichnet. Stünden beide
  da, hätte jedes korrigierte Feld zwei Marker. Ohne Verdikte wird der Text
  nicht angefasst — dort gibt es keine Korrektur, und was die/der Lernende
  geschrieben hat, bleibt stehen.
  """
  @spec return_doc_for_learner(Exam.t(), map() | nil, map()) :: map()
  def return_doc_for_learner(%Exam{} = exam, base_doc, verdicts) when is_map(verdicts) do
    base_doc = base_doc || %{}

    base_doc
    |> strip_markers(verdicts)
    |> SolutionHints.annotate(exam.sample_solution, verdicts)
  end

  defp strip_markers(doc, verdicts) when map_size(verdicts) == 0, do: doc

  defp strip_markers(doc, _verdicts) do
    nodes = Map.get(doc, "content", []) || []
    Map.put(doc, "content", NodePatcher.rewrite_markers(nodes, %{}))
  end

  @doc """
  Subscribes to correction-grid events for a given exam ID.
  """
  def subscribe_correction(exam_id) do
    Phoenix.PubSub.subscribe(Tasky.PubSub, "exam_correction:#{exam_id}")
  end

  @doc """
  Broadcasts a bulk-correction lifecycle event on the correction topic.
  Payload shapes:
    {:bulk_correction_progress, %{done: integer, total: integer, errors: integer}}
    {:bulk_correction_done, %{total: integer, errors: list}}
    {:bulk_correction_cancelled, %{done: integer, total: integer, errors: list}}
  """
  def broadcast_bulk_correction(exam_id, message) do
    Phoenix.PubSub.broadcast(Tasky.PubSub, "exam_correction:#{exam_id}", message)
  end

  # --- PubSub for exam status ---

  @doc """
  Subscribes to exam status updates for a given exam ID.
  """
  def subscribe_exam(exam_id) do
    Phoenix.PubSub.subscribe(Tasky.PubSub, "exam:#{exam_id}")
  end

  @doc """
  Broadcasts an exam status change to all subscribers.
  """
  def broadcast_exam_update(%Exam{} = exam) do
    Phoenix.PubSub.broadcast(Tasky.PubSub, "exam:#{exam.id}", {:exam_status_changed, exam})
  end

  # --- Attachments (Anhänge) ---

  @doc "Lists an exam's attachments in display order."
  def list_exam_attachments(%Exam{} = exam) do
    Repo.all(
      from a in ExamAttachment,
        where: a.exam_id == ^exam.id,
        order_by: [asc: a.position, asc: a.id]
    )
  end

  @doc "Gets an attachment of the given exam, or nil."
  def get_exam_attachment(%Exam{} = exam, id) do
    Repo.get_by(ExamAttachment, id: id, exam_id: exam.id)
  end

  @doc "Gets an attachment by its stored (UUID) filename, or nil."
  def get_exam_attachment_by_stored_filename(exam_id, stored_filename) do
    Repo.get_by(ExamAttachment, exam_id: exam_id, stored_filename: stored_filename)
  end

  @doc """
  Creates an attachment record for a file already stored on disk (see
  `Tasky.Uploads.save_exam_attachment/3`).
  """
  def create_exam_attachment(scope, %Exam{} = exam, attrs) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      position =
        Repo.one(
          from a in ExamAttachment,
            where: a.exam_id == ^exam.id,
            select: coalesce(max(a.position), -1)
        ) + 1

      %ExamAttachment{exam_id: exam.id}
      |> ExamAttachment.changeset(Map.put(attrs, :position, position))
      |> Repo.insert()
    end
  end

  @doc "Deletes an attachment record and its file on disk."
  def delete_exam_attachment(scope, %ExamAttachment{} = attachment) do
    with :ok <- authorize_exam_id(scope, attachment.exam_id),
         {:ok, deleted} <- Repo.delete(attachment) do
      Tasky.Uploads.delete_exam_attachment_file(deleted.exam_id, deleted.stored_filename)
      {:ok, deleted}
    end
  end

  # --- Upload fields (Datei-Abgaben) ---

  @doc "Lists an exam's upload fields in display order."
  def list_upload_fields(%Exam{} = exam), do: list_upload_fields_by_exam_id(exam.id)

  defp list_upload_fields_by_exam_id(exam_id) do
    Repo.all(
      from f in ExamUploadField,
        where: f.exam_id == ^exam_id,
        order_by: [asc: f.position, asc: f.id]
    )
  end

  @doc "Gets an upload field of the given exam, or nil."
  def get_upload_field(%Exam{} = exam, id) do
    Repo.get_by(ExamUploadField, id: id, exam_id: exam.id)
  end

  @doc "Creates an upload field, appended at the end."
  def create_upload_field(scope, %Exam{} = exam, attrs) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      position =
        Repo.one(
          from f in ExamUploadField,
            where: f.exam_id == ^exam.id,
            select: coalesce(max(f.position), -1)
        ) + 1

      %ExamUploadField{exam_id: exam.id}
      |> ExamUploadField.changeset(Map.put(attrs, "position", position))
      |> Repo.insert()
    end
  end

  @doc "Updates an upload field."
  def update_upload_field(scope, %ExamUploadField{} = field, attrs) do
    with :ok <- authorize_exam_id(scope, field.exam_id) do
      field
      |> ExamUploadField.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes an upload field including all student files uploaded into it
  (records via FK cascade, bytes on disk explicitly).
  """
  def delete_upload_field(scope, %ExamUploadField{} = field) do
    files =
      Repo.all(
        from sf in ExamSubmissionFile,
          where: sf.upload_field_id == ^field.id,
          join: s in assoc(sf, :exam_submission),
          select: {s.exam_id, sf.exam_submission_id, sf.stored_filename}
      )

    with :ok <- authorize_exam_id(scope, field.exam_id),
         {:ok, deleted} <- Repo.delete(field) do
      Enum.each(files, fn {exam_id, submission_id, stored} ->
        Tasky.Uploads.delete_submission_file_from_disk(exam_id, submission_id, stored)
      end)

      {:ok, deleted}
    end
  end

  @doc "True when the exam has attachments or upload fields (student tab visibility)."
  def exam_has_files?(%Exam{} = exam) do
    Repo.exists?(from a in ExamAttachment, where: a.exam_id == ^exam.id) or
      Repo.exists?(from f in ExamUploadField, where: f.exam_id == ^exam.id)
  end

  # --- Student answer files ---

  @doc """
  Lists all answer files uploaded for an exam (upload field preloaded),
  for the teacher's correction overview.
  """
  def list_exam_submission_files(%Exam{} = exam) do
    Repo.all(
      from sf in ExamSubmissionFile,
        join: s in assoc(sf, :exam_submission),
        where: s.exam_id == ^exam.id,
        join: f in assoc(sf, :upload_field),
        order_by: [asc: f.position, asc: f.id],
        preload: [upload_field: f]
    )
  end

  @doc "Lists a submission's uploaded files."
  def list_submission_files(%ExamSubmission{} = submission) do
    Repo.all(from sf in ExamSubmissionFile, where: sf.exam_submission_id == ^submission.id)
  end

  @doc "Gets a submission's file for one upload field, or nil."
  def get_submission_file(%ExamSubmission{} = submission, field_id) do
    Repo.get_by(ExamSubmissionFile,
      exam_submission_id: submission.id,
      upload_field_id: field_id
    )
  end

  @doc "Gets a file of the given submission by its id, or nil."
  def get_submission_file_by_id(%ExamSubmission{} = submission, file_id) do
    Repo.get_by(ExamSubmissionFile, id: file_id, exam_submission_id: submission.id)
  end

  @doc """
  Stores/replaces the answer file of one upload field for a submission whose
  bytes are already on disk. A previously uploaded file for the same field is
  replaced and its bytes removed.
  """
  def put_submission_file(%ExamSubmission{} = submission, %ExamUploadField{} = field, attrs) do
    result =
      Repo.transaction(fn ->
        {exam, locked} = lock_submission_for_write!(submission)
        ensure_submission_writable!(exam, locked)

        old = get_submission_file(submission, field.id)

        changeset =
          case old do
            nil ->
              %ExamSubmissionFile{exam_submission_id: submission.id, upload_field_id: field.id}
              |> ExamSubmissionFile.changeset(attrs)

            existing ->
              ExamSubmissionFile.changeset(existing, attrs)
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
  def delete_submission_file(%ExamSubmission{} = submission, %ExamSubmissionFile{} = file) do
    result =
      Repo.transaction(fn ->
        {exam, locked} = lock_submission_for_write!(submission)
        ensure_submission_writable!(exam, locked)

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

  defp delete_submission_file_bytes(submission, stored_filename) do
    Tasky.Uploads.delete_submission_file_from_disk(
      submission.exam_id,
      submission.id,
      stored_filename
    )
  end

  @doc """
  Required upload fields of the submission's exam that have no file yet.
  Used to gate the exam submit.
  """
  def missing_required_uploads(%ExamSubmission{} = submission) do
    uploaded_ids =
      Repo.all(
        from sf in ExamSubmissionFile,
          where: sf.exam_submission_id == ^submission.id,
          select: sf.upload_field_id
      )

    submission.exam_id
    |> list_upload_fields_by_exam_id()
    |> Enum.filter(&(&1.required and &1.id not in uploaded_ids))
  end
end
