defmodule Tasky.Exams do
  @moduledoc """
  The Exams context.
  """

  import Ecto.Query, warn: false
  import Tasky.Exams.Access
  alias Tasky.Repo

  alias Tasky.Accounts.Scope
  alias Tasky.Accounts.User
  alias Tasky.AI.NodePatcher
  alias Tasky.AudioPlays
  alias Tasky.Correction.AnswerKey
  alias Tasky.Correction.ImagePin
  alias Tasky.Correction.PartConfig
  alias Tasky.Correction.PlainAnswers
  alias Tasky.Correction.StringComparator
  alias Tasky.Exams.Exam
  alias Tasky.Exams.ExamSubmission
  alias Tasky.Exams.ExamSubmissionFile
  alias Tasky.Grading
  alias Tasky.Organizations
  alias Tasky.Policy

  @doc """
  Returns the list of exams for a given scope.
  Teachers see only their own exams, admins see all exams.

  Archived exams are left out unless `archived: true` is given, in which case
  only archived exams are returned, most recently archived first.

  The structs come without the document columns (`@document_fields`) — those
  read as their empty defaults here, since a teacher's list would otherwise
  load every exam they ever wrote in full. Every other column is loaded.
  Refetch with `get_exam!/2` before acting on one.
  """
  def list_exams(%Scope{user: user}, opts \\ []) do
    archived? = Keyword.get(opts, :archived, false)

    case user.role do
      "admin" -> Repo.all(exams_query(archived?))
      "teacher" -> Repo.all(from e in exams_query(archived?), where: e.teacher_id == ^user.id)
      _ -> []
    end
  end

  @document_fields [
    :content,
    :sample_solution,
    :sample_solution_points,
    :sample_solution_block_points,
    :ai_correction_config,
    :paper_layout
  ]
  @list_fields Exam.__schema__(:fields) -- @document_fields

  defp exams_query(false) do
    from e in Exam,
      where: is_nil(e.archived_at),
      order_by: [desc: e.inserted_at],
      select: struct(e, ^@list_fields),
      preload: [:teacher]
  end

  defp exams_query(true) do
    from e in Exam,
      where: not is_nil(e.archived_at),
      order_by: [desc: e.archived_at, desc: e.inserted_at],
      select: struct(e, ^@list_fields),
      preload: [:teacher]
  end

  @doc """
  Returns how many archived exams the scope can see — the count on the list's
  link to the archive.
  """
  def count_archived_exams(%Scope{user: user}) do
    base = from e in Exam, where: not is_nil(e.archived_at)

    case user.role do
      "admin" -> Repo.aggregate(base, :count)
      "teacher" -> Repo.aggregate(from(e in base, where: e.teacher_id == ^user.id), :count)
      _ -> 0
    end
  end

  @phases ~w(draft open running correcting ready_to_return returned)

  @doc """
  Where each exam stands, for the exam list's filter and chips:
  `%{exam_id => phase}`, one of `phases/0`.

    * `"returned"` — `returned_at` is set. Wins over everything else: a
      withdrawn correction is not the list's business once handed back.
    * `"correcting"` — finished, and some submission's `corrected_parts`
      does not contain every one of the exam's `part_ids`.
    * `"ready_to_return"` — finished and nothing left to correct, including
      an exam nobody sat. The mark needs no step of its own: it follows from
      the points (`Tasky.Grading`).
    * otherwise the status: `"draft"`, `"open"`, `"running"`.

  Every submission counts, handed in or not — the same set the correction
  views count. One grouped query for all finished exams, reading
  `exams.part_ids` rather than the documents, which `list_exams/2` does not
  load. Exams the scope cannot manage are left out.
  """
  def exam_phases(%Scope{} = scope, exams) do
    exams = Enum.filter(exams, &Policy.can_manage?(scope, &1.teacher_id))

    finished_ids =
      for %Exam{status: "finished", returned_at: nil, id: id} <- exams, do: id

    open_correction =
      if finished_ids == [] do
        []
      else
        from(s in ExamSubmission,
          join: e in Exam,
          on: e.id == s.exam_id,
          where: e.id in ^finished_ids,
          where: fragment("NOT (? <@ ?)", e.part_ids, s.corrected_parts),
          distinct: true,
          select: s.exam_id
        )
        |> Repo.all()
      end

    Map.new(exams, fn exam -> {exam.id, phase(exam, open_correction)} end)
  end

  @doc "The phases `exam_phases/2` returns, in lifecycle order."
  def phases, do: @phases

  defp phase(%Exam{returned_at: %DateTime{}}, _), do: "returned"

  defp phase(%Exam{status: "finished", id: id}, open_correction) do
    if id in open_correction, do: "correcting", else: "ready_to_return"
  end

  defp phase(%Exam{status: status}, _), do: status

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
    {exam, attrs} =
      if essay_kind?(attrs),
        do: {%Exam{content: essay_template()}, as_answer_fields(attrs)},
        else: {%Exam{}, attrs}

    exam
    |> Exam.create_changeset(attrs, scope)
    |> Repo.insert()
  end

  @essay_kind "essay"

  @doc """
  The create form's "Aufsatz": not a mode of its own but an answer-field exam
  that starts with a task and an essay field (`essay_template/0`). It replaces
  the free document for new exams — an essay field has a sample solution,
  points and per-field correction, which a free document lacks.
  """
  def essay_kind, do: @essay_kind

  @doc "The start of an essay exam: a question, room for the task, an essay field."
  def essay_template do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3},
          "content" => [%{"type" => "text", "text" => "Aufsatz"}]
        },
        %{"type" => "paragraph"},
        %{
          "type" => "answerBlock",
          "attrs" => %{"rich" => true},
          "content" => [%{"type" => "paragraph"}]
        },
        %{"type" => "paragraph"}
      ]
    }
    |> AnswerKey.ensure_ids()
    |> Tasky.ExamDoc.ensure_part_ids()
  end

  defp essay_kind?(attrs),
    do: (Map.get(attrs, "answer_mode") || Map.get(attrs, :answer_mode)) == @essay_kind

  defp as_answer_fields(attrs) do
    key = if Map.has_key?(attrs, :answer_mode), do: :answer_mode, else: "answer_mode"
    Map.put(attrs, key, "answer_fields")
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
      "seb_enabled" => source.seb_enabled,
      # Fresh secrets for the copy: a duplicated exam is a separate session, and
      # sharing the passwords would mean one leaked `.seb` file unlocks both.
      "seb_quit_password" => if(source.seb_enabled, do: generate_quit_password(), else: nil),
      "seb_admin_password" => if(source.seb_enabled, do: generate_admin_password(), else: nil)
      # status defaults to "draft" via schema
      # enrollment_token stays nil
      # teacher_id set from scope via create_changeset
      # the document and grading columns follow in copy_exam_content/2: the
      # image URLs they carry can only be rewritten once the copy has an id
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
           |> Exam.document_changeset(%{
             content: content,
             sample_solution: sample_solution,
             sample_solution_points: source.sample_solution_points || %{},
             sample_solution_block_points: source.sample_solution_block_points || %{},
             ai_correction_config: source.ai_correction_config || %{}
           })
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
    #
    # Archiving is not a status: see `archive_exam/2`.
    "finished" => ~w(running)
  }

  @doc """
  Advances the status of an exam along the allowed lifecycle
  (draft → open → running → finished). Returns
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

  @doc """
  Archives an exam: it leaves the teacher's exam list for the archive.

  Works in every status and leaves the status alone, so `unarchive_exam/2`
  puts the exam back exactly where it was. Archiving is the teacher's
  bookkeeping only — an open or running session goes on, and participants
  keep seeing their exam.
  """
  def archive_exam(scope, %Exam{} = exam) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      exam
      |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second))
      |> Repo.update()
    end
  end

  @doc "Brings an archived exam back into the teacher's exam list."
  def unarchive_exam(scope, %Exam{} = exam) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      exam
      |> Ecto.Changeset.change(archived_at: nil)
      |> Repo.update()
    end
  end

  @doc "True when the teacher has archived the exam."
  def archived?(%Exam{archived_at: nil}), do: false
  def archived?(%Exam{}), do: true

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
    attrs = if essay_kind?(attrs), do: as_answer_fields(attrs), else: attrs
    Exam.new_changeset(exam, attrs)
  end

  # --- Guest / Submission functions ---

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
  The participant rows of the exam cockpit: who is enrolled, their SEB
  exemption and hand-in state, and `never_started` (no answer written yet).

  The cockpit refreshes on every presence change, so this deliberately leaves
  out the answer documents `list_exam_submissions/1` loads — `never_started`
  is the only thing the cockpit needs from them, and SQL answers it.
  """
  def list_cockpit_rows(%Exam{} = exam) do
    ExamSubmission
    |> where([s], s.exam_id == ^exam.id)
    |> order_by([s], asc: s.inserted_at)
    |> select([s], %{
      id: s.id,
      firstname: s.firstname,
      lastname: s.lastname,
      exam_token: s.exam_token,
      seb_exempt: s.seb_exempt,
      audio_plays: s.audio_plays,
      submitted: s.submitted,
      submitted_at: s.submitted_at,
      inserted_at: s.inserted_at,
      never_started: fragment("NOT ? AND ? = '{}'::jsonb", s.submitted, s.content)
    })
    |> Repo.all()
  end

  @doc """
  Who is in the exam, in the order the correction views step through them:
  `%{id:, firstname:, lastname:}` per submission, sorted with `sort_by_name/1`.
  For the prev/next arrows, which used to hold every answer document of the
  exam in memory just to find a neighbour.
  """
  def list_correction_roster(%Exam{} = exam) do
    ExamSubmission
    |> where([s], s.exam_id == ^exam.id)
    |> select([s], %{id: s.id, firstname: s.firstname, lastname: s.lastname})
    |> Repo.all()
    |> sort_by_name()
  end

  @doc """
  The one order of participants in the correction views: first name, then
  last name, case-insensitive.
  """
  def sort_by_name(submissions) do
    Enum.sort_by(submissions, fn s ->
      {String.downcase(s.firstname || ""), String.downcase(s.lastname || "")}
    end)
  end

  @doc """
  Each submission's `corrected_parts`, for the "how many are done" counts of
  the correction views — `%{id:, corrected_parts:}` per submission, without
  the answer documents `list_exam_submissions/1` carries.
  """
  def list_corrected_parts(%Exam{} = exam) do
    ExamSubmission
    |> where([s], s.exam_id == ^exam.id)
    |> select([s], %{id: s.id, corrected_parts: s.corrected_parts})
    |> Repo.all()
  end

  @doc """
  The participants of an exam for the progress grid, without the heavy JSON
  columns: `id`, names, `email`, `submitted` and `updated_at`. Ordered like
  `list_exam_submissions/1`. Authorization rides on the exam.
  """
  def list_progress_rows(%Exam{} = exam) do
    ExamSubmission
    |> where([s], s.exam_id == ^exam.id)
    |> order_by([s], asc: s.inserted_at)
    |> select([s], %{
      id: s.id,
      firstname: s.firstname,
      lastname: s.lastname,
      email: s.email,
      submitted: s.submitted,
      updated_at: s.updated_at
    })
    |> Repo.all()
  end

  @doc """
  `%{submission_id => content}` for the given submissions of the exam — only
  the answer document, for the progress grid to re-read what changed.
  """
  def list_submission_contents(%Exam{}, []), do: %{}

  def list_submission_contents(%Exam{} = exam, ids) when is_list(ids) do
    ExamSubmission
    |> where([s], s.exam_id == ^exam.id and s.id in ^ids)
    |> select([s], {s.id, s.content})
    |> Repo.all()
    |> Map.new()
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
    Repo.get_child(ExamSubmission, id, exam_id: exam.id)
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
  narrowed to one class and/or a name search (see `Tasky.Accounts.search_users/2`).

  Limited to the organization of the exam's **owner** — the same rule
  `fetch_assignable_user/2` enforces on the write path. Deriving it from
  `exam.teacher_id` rather than from a caller scope keeps the signature unchanged
  and holds even when an admin performs the assignment.
  """
  def list_assignable_students(%Exam{} = exam, class_id \\ nil, search \\ nil) do
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
    |> Tasky.Accounts.search_users(search)
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
  Removes a participant from the exam for good: their submission, answers and
  uploaded files (rows via FK cascade, bytes on disk explicitly — otherwise
  they leak forever).

  Allowed at any point of the session — before the start, while it runs and
  after it has been stopped, handed in or not — and in both participation
  modes. The typical case is someone who turns out not to come after the exam
  has already started; their empty submission would otherwise sit in the
  correction and the grade overview.

  Broadcasts `{:participant_removed, submission_id}` on the exam topic so an
  open participant view ends the session at once.
  """
  def remove_participant(scope, %Exam{} = exam, %ExamSubmission{} = submission) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         :ok <- validate_removable(exam, submission) do
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

          Phoenix.PubSub.broadcast(
            Tasky.PubSub,
            "exam:#{exam.id}",
            {:participant_removed, deleted.id}
          )

          {:ok, deleted}

        error ->
          error
      end
    end
  end

  defp validate_removable(%Exam{} = exam, %ExamSubmission{} = submission) do
    if submission.exam_id == exam.id, do: :ok, else: {:error, :not_found}
  end

  @doc """
  Releases one participant from the exam's Safe Exam Browser requirement, or
  puts them back under it.

  Allowed at any point of the session, because the case it exists for — an SEB
  that will not start on one laptop — shows up on exam day. Takes effect at
  once: `TaskyWeb.Plugs.SebGuard` reads the submission fresh on every request,
  and the broadcast `{:seb_exemption_changed, %{id:, seb_exempt:}}` on the exam topic
  lifts (or brings back) the gate in an open participant view.
  """
  def set_seb_exempt(scope, %Exam{} = exam, %ExamSubmission{} = submission, exempt?)
      when is_boolean(exempt?) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         :ok <- validate_removable(exam, submission),
         {:ok, updated} <-
           submission
           |> ExamSubmission.seb_exemption_changeset(exempt?)
           |> Repo.update() do
      # Ids and the flag only: every open participant view of the exam gets
      # this message, and the whole struct carried this learner's answers to
      # all of them.
      Phoenix.PubSub.broadcast(
        Tasky.PubSub,
        "exam:#{exam.id}",
        {:seb_exemption_changed, %{id: updated.id, seb_exempt: updated.seb_exempt}}
      )

      {:ok, updated}
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

  On an exam that is already returned this only changes the flags: the
  learners keep their access, and `returned_at` stays the date it was first
  handed back.
  """
  def return_exam(scope, %Exam{} = exam, opts) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         :ok <- validate_returnable(exam) do
      exam
      |> Exam.return_changeset(%{
        returned_at: exam.returned_at || DateTime.utc_now(:second),
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
      exam.status != "finished" -> {:error, :exam_not_finished}
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
  Resolves an exam token for one of the learner write functions
  (`save_exam_submission_answers/2`, `update_exam_submission_content/2`).

  Those lock and re-read the exam and the submission inside their own
  transaction, so this loads only `id` and `exam_id` — every other field of
  the returned struct is a default and must not be read. It sits on the
  autosave path, which every learner hits every few seconds; loading the
  submission's document and the exam with it there doubled each request's
  reads. Raises `Ecto.NoResultsError` for an unknown token.
  """
  def get_submission_for_write_by_token!(token) when is_binary(token) do
    Repo.one!(
      from s in ExamSubmission,
        where: s.exam_token == ^token,
        select: struct(s, [:id, :exam_id])
    )
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
  Updates the content (TipTap doc JSON) of a non-submitted exam submission.
  Only allowed when the associated exam is still running and the submission
  has not been submitted yet.

  In a free-document exam the doc *is* the answer and is stored as sent. In an
  answer-field exam only the answers are taken from it and set into the
  server's own skeleton (see `merge_submission_answers/3`) — the question text
  cannot be changed from the client. That path is what a learner still on the
  Tiptap editor sends; the native fields use `save_exam_submission_answers/2`.
  """
  def update_exam_submission_content(%ExamSubmission{} = submission, content)
      when is_map(content) do
    write_submission_content(submission, fn exam, locked ->
      if free_document?(exam) do
        {:ok, content}
      else
        {_blanked, answers} = AnswerKey.split(content)
        {:ok, merge_submission_answers(exam, locked, answers)}
      end
    end)
  end

  @doc """
  Saves the answers of the native answer fields (`TaskyWeb.ExamDocComponents`)
  of a non-submitted exam submission: `%{"answers" => ..., "choices" => ...}`,
  see `Tasky.Correction.PlainAnswers.from_params/2`. Same gate as
  `update_exam_submission_content/2`. A free-document exam has no answer
  fields and refuses with `:free_document`.
  """
  def save_exam_submission_answers(%ExamSubmission{} = submission, params)
      when is_map(params) do
    write_submission_content(submission, fn exam, locked ->
      if free_document?(exam) do
        {:error, :free_document}
      else
        with {:ok, answers} <-
               PlainAnswers.from_params(submission_answer_base(exam, locked), params) do
          {:ok, merge_submission_answers(exam, locked, answers)}
        end
      end
    end)
  end

  # Gate and write run in one transaction against locked rows: an autosave
  # already in flight when the student hits submit must not land content on a
  # submission that is by then handed in (TOCTOU). This is the hottest write
  # path in the app — one keystroke debounce per student — so the transaction
  # holds nothing but the two locks, the check, the merge and the update.
  defp write_submission_content(submission, build_content) do
    Repo.transaction(fn ->
      {exam, locked} = lock_submission_for_write!(submission)
      ensure_submission_writable!(exam, locked)

      with {:ok, content} <- build_content.(exam, locked),
           {:ok, updated} <-
             locked |> ExamSubmission.content_changeset(%{content: content}) |> Repo.update() do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # The document the answers go into: the learner's own copy once there is one,
  # else the exam. Not always the exam's current content — the teacher may
  # edit it during the exam, and an answer field removed there must not wipe
  # the learner's answer from their submission.
  defp submission_answer_base(exam, submission) do
    case submission.content do
      content when is_map(content) and map_size(content) > 0 -> content
      _ -> exam.content || %{}
    end
  end

  # Fields the payload leaves out keep their previous answer.
  defp merge_submission_answers(exam, submission, answers) do
    {skeleton, previous} =
      exam
      |> submission_answer_base(submission)
      |> Map.put_new("type", "doc")
      |> AnswerKey.split()

    AnswerKey.merge(skeleton, Map.merge(previous, answers))
  end

  ## Audio blocks (see Tasky.AudioPlays)

  @doc """
  Starts a play of an audio block, or resumes the running one, for a learner
  still writing. Returns `{:ok, view}` (see `Tasky.AudioPlays.view/2`) or
  `{:error, :exhausted | :not_found | :already_submitted | :exam_not_running}`.
  The limit comes from the exam's own content, never from the client.
  """
  def start_audio_play(%ExamSubmission{} = submission, audio_id),
    do: update_audio_play(submission, audio_id, &AudioPlays.start/2, check_file: true)

  @doc "Records how far the running play of an audio block has got."
  def record_audio_progress(%ExamSubmission{} = submission, audio_id, position),
    do:
      update_audio_play(submission, audio_id, fn state, _max ->
        {:ok, AudioPlays.progress(state, position)}
      end)

  @doc "Closes the running play of an audio block."
  def finish_audio_play(%ExamSubmission{} = submission, audio_id),
    do:
      update_audio_play(submission, audio_id, fn state, _max ->
        {:ok, AudioPlays.finish(state)}
      end)

  # `check_file`: a play must not be spent on a file that cannot load (gone,
  # or a block pasted over from another exam whose `src` points there).
  defp update_audio_play(submission, audio_id, fun, opts \\ []) do
    Repo.transaction(fn ->
      {exam, locked} = lock_submission_for_write!(submission)
      ensure_submission_writable!(exam, locked)

      with %{} = node <- AudioPlays.find(exam.content, audio_id) || {:error, :not_found},
           :ok <- audio_file_check(opts, node, :exams, exam.id),
           max = AudioPlays.max_plays(node),
           state = AudioPlays.state(locked.audio_plays, audio_id),
           {:ok, new_state} <- fun.(state, max),
           {:ok, _} <- write_audio_state(locked, audio_id, state, new_state) do
        AudioPlays.view(new_state, max)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp audio_file_check(opts, node, kind, owner_id) do
    if Keyword.get(opts, :check_file, false) do
      case Tasky.Uploads.fetch_audio(AudioPlays.src(node), kind, owner_id) do
        {:ok, _} -> :ok
        {:error, _} -> {:error, :file_missing}
      end
    else
      :ok
    end
  end

  # A progress report that changes nothing must not cost an UPDATE.
  defp write_audio_state(submission, _audio_id, state, state), do: {:ok, submission}

  defp write_audio_state(submission, audio_id, _state, new_state) do
    submission
    |> ExamSubmission.audio_plays_changeset(
      AudioPlays.put(submission.audio_plays, audio_id, new_state)
    )
    |> Repo.update()
  end

  @doc """
  The stored audio file a learner may load right now, by exam token:
  `{:ok, {source, content_type}}` or `{:error, :not_found | :not_playable}`.

  A block without a limit plays once the exam runs (and afterwards); one with
  a limit only during one of the learner's plays while the exam still runs.
  """
  def learner_audio_source(token, audio_id) when is_binary(token) do
    with %ExamSubmission{} = submission <- Repo.get_by(ExamSubmission, exam_token: token),
         %Exam{} = exam <- Repo.get(Exam, submission.exam_id),
         %{} = node <- AudioPlays.find(exam.content, audio_id),
         :ok <- learner_may_play(exam, submission, node, audio_id) do
      Tasky.Uploads.fetch_audio(AudioPlays.src(node), :exams, exam.id)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_found}
    end
  end

  defp learner_may_play(exam, submission, node, audio_id) do
    case AudioPlays.max_plays(node) do
      nil ->
        if exam.status in ["running", "finished"], do: :ok, else: {:error, :not_playable}

      max ->
        state = AudioPlays.state(submission.audio_plays, audio_id)

        if exam.status == "running" and not submission.submitted and
             AudioPlays.playable?(state, max),
           do: :ok,
           else: {:error, :not_playable}
    end
  end

  @doc """
  Gives a participant one play of an audio block back (after a technical
  problem). Only the exam owner (or an admin).
  """
  def grant_audio_play(%Scope{} = scope, %ExamSubmission{} = submission, audio_id)
      when is_binary(audio_id) do
    with :ok <- authorize_submission(scope, submission) do
      Repo.transaction(fn ->
        locked = Repo.lock_one!(ExamSubmission, submission.id)
        state = AudioPlays.state(locked.audio_plays, audio_id)

        case write_audio_state(locked, audio_id, state, AudioPlays.grant(state)) do
          {:ok, updated} -> updated
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
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
  The exam's mark rounding grid. **The one place the `nil` fallback lives** —
  `Grading.round_mark/2` raises for `nil` on purpose, so every mark
  computation resolves the step through here.

  An exam whose teacher has not chosen yet grades on 0.25, exactly as the
  app always did, which is what keeps a print or a hand-back correct before
  they ever open the Benotung.
  """
  def mark_step(%Exam{mark_step: nil}), do: Grading.default_mark_step()
  def mark_step(%Exam{mark_step: step}), do: step

  @doc """
  True once the teacher has chosen a mark step. The grading table gates on
  this and sends an unconfigured exam to the configuration page first.
  """
  def mark_step_configured?(%Exam{mark_step: nil}), do: false
  def mark_step_configured?(%Exam{}), do: true

  @doc """
  The points that earn a 6 — what every mark of the exam divides by: the
  teacher's explicit override, else the sum of the sample solution's points.
  `nil` when that leaves nothing to divide by — no divisor, no mark.

  Not the same as `total_points/1`: the override may sit below the total (a 6
  without every point) or above it.
  """
  def points_for_six(%Exam{} = exam) do
    case exam.grading_max_points || Grading.sum_points(exam.sample_solution_points) do
      n when is_number(n) and n > 0 -> n
      _ -> nil
    end
  end

  @doc """
  The most points the exam can award: the sum of the sample solution's
  points, whatever the teacher set as the points for a 6. `nil` when the
  sample solution has no points (free documents).
  """
  def total_points(%Exam{} = exam) do
    case Grading.sum_points(exam.sample_solution_points) do
      n when is_number(n) and n > 0 -> n
      _ -> nil
    end
  end

  @doc """
  Everything the grading surfaces need for one submission, in one call:

      %{points:, total_points:, points_for_six:, mark_step:, calculated_mark:,
       effective_mark:}

  **This is the only place the `submission.mark || calculated` precedence
  exists.** It used to be inlined in the grading table, the PDF export and
  the learner's view, and the PDF once printed a different mark than the
  screen because the formula had drifted (`docs/ROBUSTNESS_PLAN.md`). With a
  per-exam mark step there are two things to keep in sync instead of one, so
  they all go through here. Pure — no `Repo`, works on bare structs.
  """
  def grading_result(%Exam{} = exam, %ExamSubmission{} = submission) do
    step = mark_step(exam)
    points_for_six = points_for_six(exam)
    points = Grading.sum_points(submission.points_per_part)
    calculated = Grading.mark(points, points_for_six, step)

    %{
      points: points,
      total_points: total_points(exam),
      points_for_six: points_for_six,
      mark_step: step,
      calculated_mark: calculated,
      effective_mark: submission.mark || calculated
    }
  end

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
  Like `mark_part_corrected/3`, first persisting `defaults`
  (`%{block_index => verdict}`) for the part's blocks the teacher left
  untouched — the single-submission twin of `mark_part_corrected_bulk/4`. With
  a read-only total, a part accepted as pre-judged would otherwise be marked
  done without any points.

  The defaults are only applied while the part has no stored total yet: a
  total typed by hand before stays as it is.
  """
  def mark_part_corrected(scope, %ExamSubmission{} = submission, part_id, defaults)
      when is_binary(part_id) and is_map(defaults) do
    with :ok <- authorize_submission(scope, submission) do
      result =
        Repo.transaction(fn ->
          # Exam first (FOR SHARE), then the submission — the lock order of
          # every other grading write.
          exam = Repo.lock_one!(Exam, submission.exam_id, :share)
          locked = Repo.lock_one!(ExamSubmission, submission.id)

          defaults =
            if Map.has_key?(locked.points_per_part || %{}, part_id), do: %{}, else: defaults

          mark_one_corrected!(locked, exam, part_id, defaults)
        end)

      with {:ok, updated} <- result do
        broadcast_submission_change(updated)
        {:ok, updated}
      end
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

      case locked
           |> Ecto.Changeset.change(fun.(locked))
           |> Exam.put_part_ids()
           |> Repo.update() do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
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

        # The zones the correction view drew are the exam's, not the answer's.
        part_nodes = ImagePin.without_solution(part_nodes)

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
      new_content =
        doc
        |> AnswerKey.ensure_ids()
        |> Tasky.ExamDoc.ensure_part_ids()
        |> keep_choice_groups_in_parts(exam.answer_mode)

      # The sample-solution columns must be read from the *locked* row. Reading
      # them off the caller's struct (loaded in the controller, outside any
      # transaction) let a concurrent "Musterlösung" autosave commit in between,
      # and this write then resurrected the stale map — losing a model answer.
      result =
        update_exam_json(exam, fn locked ->
          # How many pins a pin image has is the sample solution's to say —
          # this tab never sets them (`ImagePin.sync_public_pins/2`).
          new_content = ImagePin.sync_public_pins(new_content, locked.sample_solution)

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
        Phoenix.PubSub.broadcast(Tasky.PubSub, "exam_content:#{updated.id}", :exam_content_saved)
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
             |> Exam.document_changeset(%{
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

  # A radio group must not span two questions (see `Choice.separate_by_part/3`).
  # A free document is a single part, so nothing can span anything there.
  defp keep_choice_groups_in_parts(content, "free_document"), do: content

  defp keep_choice_groups_in_parts(content, _answer_mode) do
    Tasky.Correction.Choice.separate_by_part(
      content,
      &Tasky.ExamDoc.question_heading?/1,
      AnswerKey.block_ids(content)
    )
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

      # On the 0.25 grid, so the shares add up to the part's total: 1 point
      # over 3 blocks used to be 3 × 0.333…, and two right checkboxes then
      # summed to 0.67 and were rounded to 0.75.
      is_number(max_points) ->
        blocks |> Enum.map(& &1.index) |> equal_block_shares(max_points)

      true ->
        nil
    end
  end

  defp block_points_value(n) when is_number(n), do: n
  defp block_points_value(_), do: 0

  @doc """
  Splits `max_points` over `keys` (answer ids or block indices) on the 0.25
  grid, the shares summing to exactly `max_points` — what the equal split and
  the start of a custom distribution both use.
  """
  def equal_shares(keys, max_points) when is_list(keys), do: equal_block_shares(keys, max_points)

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

  Each entry is a `Tasky.AI.NodePatcher.list_answer_blocks/1` entry plus
  `verdict` — `"correct"`, `"half"` (legacy), `"wrong"`, a number (manual
  points) or `nil` — `expected_checked`, whether the sample solution ticks
  that checkbox (`nil` for anything but a `taskItem`), and `expected_option`,
  the label of the radio the sample solution chooses (`nil` for anything but
  a `choice` group, or when the sample chooses none). Verdicts are keyed by
  the block's stable `answerId` in `submission.block_verdicts`.
  """
  def list_part_answer_blocks(%Exam{} = exam, %ExamSubmission{} = submission, part_id)
      when is_binary(part_id) do
    sample_blocks = sample_blocks_by_index(exam, part_id)

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

          sample = Map.get(sample_blocks, entry.index)

          entry
          |> Map.put(:verdict, verdict)
          |> Map.put(:expected_checked, expected_checked(sample))
          |> Map.put(:expected_option, expected_option(sample))
          |> put_pin_hits(sample)
        end)
    end
  end

  # The sample solution's blocks of the part, by block index — the same
  # positional index the submission's blocks carry.
  defp sample_blocks_by_index(exam, part_id) do
    exam
    |> sample_solution_doc()
    |> split_content_into_parts(exam.answer_mode)
    |> Enum.find(&(&1.id == part_id))
    |> case do
      nil -> %{}
      part -> part.nodes |> NodePatcher.list_answer_blocks() |> Map.new(&{&1.index, &1})
    end
  end

  # A pin image has no text to show beside its verdict buttons; how many pins
  # hit is what the teacher needs there.
  defp put_pin_hits(%{type: "imagePin"} = entry, %{type: "imagePin"} = sample) do
    {hits, total} = ImagePin.score(entry.pins, sample.pins, sample.aspect)
    Map.put(entry, :text, "#{hits} von #{total} Pins im Zielbereich")
  end

  defp put_pin_hits(entry, _sample), do: entry

  defp expected_checked(%{type: "taskItem", checked: checked}), do: checked
  defp expected_checked(_sample), do: nil

  # A sample block's `text` is the label of the radio it chooses.
  defp expected_option(%{type: "choice", text: label}) when label != "", do: label
  defp expected_option(_sample), do: nil

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

    new_part_points =
      compute_part_points(
        effective_indexed,
        points_by_index,
        checkbox_lists(exam, part_id, blocks)
      )

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
            |> compute_part_points(points_by_index, checkbox_lists(exam, part_id, blocks))

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
    set_block_verdicts_bulk(scope, exam, part_id, %{index => verdict}, submission_ids)
  end

  @doc """
  Like `set_block_verdict_bulk/6`, for several blocks of one part at once —
  `verdicts_by_index` is `%{block_index => verdict}` (`nil` clears the
  teacher's verdict). The checkbox patterns of the grouped view judge every
  checkbox of a list together, and this keeps that one write per submission.
  """
  def set_block_verdicts_bulk(scope, %Exam{} = exam, part_id, verdicts_by_index, submission_ids)
      when is_binary(part_id) and is_map(verdicts_by_index) and is_list(submission_ids) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         :ok <- validate_verdicts(verdicts_by_index) do
      result =
        Repo.transaction(fn ->
          exam = Repo.lock_one!(Exam, exam.id, :share)

          for submission <- lock_submissions_by_ids!(exam, submission_ids),
              {:ok, changes} <-
                [part_verdict_changes(submission, exam, part_id, verdicts_by_index)] do
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

  # The binding verdict vocabulary — the same one set_block_verdict/5 guards.
  # normalize_verdict/2 passes anything that is not a number through, so a
  # value outside it would be stored and silently read back as ungraded.
  defp validate_verdicts(verdicts_by_index) do
    if Enum.all?(verdicts_by_index, fn {index, verdict} ->
         is_integer(index) and
           (verdict in ["correct", "half", "wrong", nil] or is_number(verdict))
       end),
       do: :ok,
       else: {:error, :invalid_verdict}
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

  defp compute_part_points(indexed, points_by_index, checkbox_lists),
    do: Grading.part_points(indexed, points_by_index, checkbox_lists)

  @doc """
  The checkbox lists of a part that are scored by a rule other than per
  checkbox, as `Tasky.Grading.part_points/3` takes them:
  `[%{indices: [block_index], rule:}]`, one per list.

  The rule is chosen per question in the sample solution
  (`ai_correction_config[part_id]["checkbox_scoring"]`) and applies to every
  checkbox list in it. `blocks` are the part's answer blocks
  (`NodePatcher.list_answer_blocks/1`).
  """
  def checkbox_lists(%Exam{} = exam, part_id, blocks) when is_binary(part_id) do
    %{rule: rule} = checkbox_scoring(exam, part_id)

    if rule == "per_checkbox" do
      []
    else
      blocks
      |> Enum.filter(&(&1.type == "taskItem" and not is_nil(&1[:group])))
      |> Enum.group_by(& &1.group, & &1.index)
      |> Enum.map(fn {_group, indices} ->
        %{indices: indices, rule: rule}
      end)
    end
  end

  @doc """
  A part's checkbox scoring rule, `"per_checkbox"` unless set:
  `%{rule: "per_checkbox" | "all_or_nothing"}`. A rule that no longer exists
  reads as `"per_checkbox"`.
  """
  def checkbox_scoring(%Exam{} = exam, part_id) when is_binary(part_id),
    do: %{
      rule: exam.ai_correction_config |> PartConfig.get(part_id) |> PartConfig.checkbox_rule()
    }

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
  Sets the exam's mark rounding grid and re-rounds every stored manual mark
  onto it, in one transaction.

  The re-rounding is the whole reason this is not a plain column write. A
  manually set 4.25 is not a point on the 0.1 grid, so leaving it would put
  a value into the grading table that the ± buttons cannot reproduce and the
  number input flags as a step mismatch. Rounding is silent and needs no
  decision from the teacher: ties go away from zero, so 4.25 becomes 4.3 —
  in the learner's favour — and the teacher sees the result in the table.

  Marks already on the new grid are not rewritten, so switching back and
  forth does not touch rows it does not have to. Returns
  `{:ok, exam, rounded_count}`.
  """
  def set_mark_step(scope, %Exam{} = exam, step) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         :ok <- validate_mark_step(step) do
      case do_set_mark_step(exam, step) do
        {:ok, {updated, changed}} ->
          Enum.each(changed, &broadcast_submission_change/1)
          broadcast_exam_update(updated)
          {:ok, updated, length(changed)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Saves the whole grading configuration — mark step and max-points override
  — in one transaction, so the configuration page has one «Speichern» and
  never a half-written state.

  `:max_points` follows `update_grading_max_points/3` (`nil` clears the
  override) and may be left out to keep what is stored; `:mark_step` follows
  `set_mark_step/3`, including the re-rounding of every stored manual mark.
  Both are validated before anything is written. Returns
  `{:ok, exam, rounded_count}`.
  """
  def update_grading_config(scope, %Exam{} = exam, %{mark_step: step} = attrs) do
    with :ok <- Policy.authorize(scope, exam.teacher_id),
         :ok <- validate_mark_step(step),
         {:ok, exam_changes} <- grading_max_points_changes(attrs) do
      case do_set_mark_step(exam, step, exam_changes) do
        {:ok, {updated, changed}} ->
          Enum.each(changed, &broadcast_submission_change/1)
          broadcast_exam_update(updated)
          {:ok, updated, length(changed)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp grading_max_points_changes(%{max_points: max_points}) do
    with {:ok, normalized} <- normalize_grading_max_points(max_points),
         do: {:ok, %{grading_max_points: normalized}}
  end

  defp grading_max_points_changes(_attrs), do: {:ok, %{}}

  defp validate_mark_step(step) do
    if Grading.mark_step?(step), do: :ok, else: {:error, :invalid_mark_step}
  end

  # Locks the exam FOR UPDATE (it is written here) and then its submissions,
  # parent before child and ascending id within the table — the ordering rule
  # in ARCHITECTURE.md. Taking FOR UPDATE rather than FOR SHARE on the exam
  # is deliberate: this transaction writes the exam row *and* must exclude a
  # concurrent set_submission_mark/3, which reads the step under FOR SHARE.
  #
  # `exam_changes` rides along on the same exam write, for
  # update_grading_config/3.
  defp do_set_mark_step(%Exam{} = exam, step, exam_changes \\ %{}) do
    Repo.transaction(fn ->
      locked = Repo.lock_one!(Exam, exam.id, :update)

      changed =
        locked
        |> lock_exam_submissions!()
        |> Enum.filter(&(not is_nil(&1.mark)))
        |> Enum.map(fn submission ->
          {submission, Grading.normalize_mark(submission.mark, step) / 1}
        end)
        |> Enum.filter(fn {submission, rounded} -> submission.mark != rounded end)
        |> Enum.map(fn {submission, rounded} ->
          submission
          |> Ecto.Changeset.change(%{mark: rounded})
          |> Repo.update!()
        end)

      updated =
        locked
        |> Exam.mark_step_changeset(%{mark_step: step})
        |> Ecto.Changeset.change(exam_changes)
        |> Repo.update!()

      {updated, changed}
    end)
  end

  @doc """
  Sets (or clears, when `mark` is `nil`) the teacher-adjusted final mark for
  a submission. The mark is stored as a float; when `nil`, callers should
  fall back to the calculated mark (see `grading_result/2`).

  The rounding grid is read off the exam inside the transaction rather than
  taken from the caller: a teacher typing 4.7 while a second tab switches the
  exam to 0.25 steps must not be able to store an off-grid mark.
  """
  def set_submission_mark(scope, %ExamSubmission{} = submission, mark) do
    with :ok <- authorize_submission(scope, submission) do
      # Exam FOR SHARE before submission FOR UPDATE — the same order as
      # do_set_block_verdict/5, so the two cannot deadlock against each other.
      Repo.transaction(fn ->
        exam = Repo.lock_one!(Exam, submission.exam_id, :share)
        locked = Repo.lock_one!(ExamSubmission, submission.id, :update)

        case normalize_submission_mark(mark, mark_step(exam)) do
          {:ok, normalized} ->
            locked
            |> Ecto.Changeset.change(%{mark: normalized})
            |> Repo.update!()

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
    end
  end

  defp normalize_submission_mark(nil, _step), do: {:ok, nil}

  defp normalize_submission_mark(mark, step) when is_number(mark),
    do: {:ok, Grading.normalize_mark(mark, step) / 1}

  defp normalize_submission_mark(_, _step), do: {:error, :invalid_mark}

  @doc """
  Applies the correction options of one part as the sample solution's options
  dialog submits them, in one transaction:

    * `:max_points` — the part's total (ignored while `:block_points` is set)
    * `:block_points` — `%{answer_id => points}` for a custom distribution
      (the total becomes their sum), or `nil` for the equal split
    * `:config` — see below

  A key left out keeps what is stored; leaving out both points keys keeps the
  part's points as they are.

  The config holds the part's flags (`"auto_correct"`, the text options) and
  its checkbox rule (`"checkbox_scoring"`); text
  options are switched off together with auto-correction, as in the form.

  When the part's settings changed, every submission whose total on the part
  is still the sum of its verdicts is rescored, so the grading table never
  shows totals of the previous settings; a total the teacher typed by hand
  (`set_part_points/4`) stays. The auto-correction then compares again, since
  the text options change what counts as a match.
  """
  def apply_part_options(scope, %Exam{} = exam, part_id, opts)
      when is_binary(part_id) and is_map(opts) do
    with :ok <- Policy.authorize(scope, exam.teacher_id) do
      result =
        Repo.transaction(fn ->
          locked = Repo.lock_one!(Exam, exam.id)

          changes =
            locked
            |> part_points_changes(part_id, opts)
            |> Map.put(:ai_correction_config, part_config_changes(locked, part_id, opts))

          updated = locked |> Ecto.Changeset.change(changes) |> Repo.update!()
          changed? = part_settings(locked, part_id) != part_settings(updated, part_id)

          submissions =
            if changed?, do: recompute_part_totals!(locked, updated, part_id), else: []

          {updated, changed?, submissions}
        end)

      with {:ok, {updated, changed?, submissions}} <- result do
        Enum.each(submissions, &broadcast_submission_change/1)
        if changed?, do: broadcast_exam_event({:exam_answers_changed, updated})
        {:ok, updated}
      end
    end
  end

  # Everything `apply_part_options/4` can change about one part.
  defp part_settings(exam, part_id) do
    {Map.get(exam.ai_correction_config || %{}, part_id),
     Map.get(exam.sample_solution_points || %{}, part_id),
     Map.get(exam.sample_solution_block_points || %{}, part_id)}
  end

  defp part_points_changes(exam, part_id, %{block_points: block_points})
       when is_map(block_points) and map_size(block_points) > 0 do
    part_map = Map.new(block_points, fn {id, pts} -> {id, normalize_block_points(pts || 0)} end)
    custom_block_points_changes(exam, part_id, part_map)
  end

  defp part_points_changes(_exam, _part_id, opts)
       when not is_map_key(opts, :max_points) and not is_map_key(opts, :block_points),
       do: %{}

  defp part_points_changes(exam, part_id, opts) do
    points =
      case Map.get(opts, :max_points) do
        n when is_number(n) -> normalize_block_points(n)
        _ -> nil
      end

    %{
      sample_solution_block_points: Map.delete(exam.sample_solution_block_points || %{}, part_id),
      sample_solution_points:
        if(is_nil(points),
          do: Map.delete(exam.sample_solution_points || %{}, part_id),
          else: Map.put(exam.sample_solution_points || %{}, part_id, points)
        )
    }
  end

  defp part_config_changes(exam, part_id, opts),
    do: PartConfig.put(exam.ai_correction_config, part_id, Map.get(opts, :config, %{}))

  # Recomputes `points_per_part[part_id]` from the stored verdicts under
  # `exam`'s settings, for every submission whose total is still what its
  # verdicts gave under `old_exam`'s. A total that differs was typed by hand
  # (`set_part_points/4`): the verdicts don't explain it, so they must not
  # replace it — without verdicts they would sum to 0. Runs inside the
  # caller's transaction, with the exam row already locked.
  defp recompute_part_totals!(old_exam, exam, part_id) do
    for submission <-
          lock_submissions_by_ids!(exam, submission_ids_with_part_total(exam, part_id)),
        part =
          submission
          |> correction_content()
          |> split_content_into_parts(exam.answer_mode)
          |> Enum.find(&(&1.id == part_id)),
        part != nil,
        blocks = NodePatcher.list_answer_blocks(part.nodes),
        verdicts = effective_verdicts_for_part(blocks, submission.block_verdicts || %{}),
        submission.points_per_part[part_id] == verdict_total(old_exam, part_id, blocks, verdicts) do
      total = verdict_total(exam, part_id, blocks, verdicts)

      points =
        if is_nil(total),
          do: Map.delete(submission.points_per_part || %{}, part_id),
          else: Map.put(submission.points_per_part || %{}, part_id, total)

      submission |> Ecto.Changeset.change(points_per_part: points) |> Repo.update!()
    end
  end

  defp verdict_total(exam, part_id, blocks, verdicts) do
    compute_part_points(
      verdicts,
      resolve_block_points(exam, part_id, blocks),
      checkbox_lists(exam, part_id, blocks)
    )
  end

  defp submission_ids_with_part_total(exam, part_id) do
    from(s in ExamSubmission, where: s.exam_id == ^exam.id, select: {s.id, s.points_per_part})
    |> Repo.all()
    |> Enum.filter(fn {_id, points} -> is_map_key(points || %{}, part_id) end)
    |> Enum.map(fn {id, _points} -> id end)
  end

  @doc """
  Counts how many parts of the exam are auto-corrected (see `auto_correct_part_ids/1`).
  """
  def count_auto_correct_parts(%Exam{} = exam),
    do: exam |> auto_correct_part_ids() |> MapSet.size()

  @doc """
  Whether the part `part_id` is auto-corrected: the teacher switched it on, or
  the part only asks for ticks (`choice_only_blocks?/1`).
  """
  def auto_correct_part?(%Exam{} = exam, part_id) when is_binary(part_id),
    do: MapSet.member?(auto_correct_part_ids(exam), part_id)

  @doc """
  The ids of the parts the auto-correction grades: those whose config has
  `"auto_correct" => true`, plus every part made only of checkboxes, radios
  and pin images.

  A tick or a pin compares exactly against the sample solution, so there is
  nothing to switch off there — such a part is always auto-corrected, whatever its stored
  flag says. The flag stays untouched, so a part that later gains a text field
  falls back to it.
  """
  def auto_correct_part_ids(%Exam{} = exam) do
    flagged =
      for {part_id, part_config} <- exam.ai_correction_config || %{},
          is_map(part_config),
          Map.get(part_config, "auto_correct") == true,
          into: MapSet.new(),
          do: part_id

    MapSet.union(flagged, choice_only_part_ids(exam))
  end

  @doc """
  The ids of the parts whose answer fields are all checkboxes (`taskItem`),
  radios (`choice`) or pin images (`imagePin`) — at least one, and no text
  field.
  """
  def choice_only_part_ids(%Exam{} = exam) do
    for part <-
          exam |> sample_solution_doc() |> split_content_into_parts(exam.answer_mode),
        choice_only_blocks?(NodePatcher.list_answer_blocks(part.nodes)),
        into: MapSet.new(),
        do: part.id
  end

  @doc """
  Whether `blocks` (from `Tasky.AI.NodePatcher.list_answer_blocks/1`) are all
  checkboxes, radios or pin images, and there is at least one.
  """
  defdelegate choice_only_blocks?(blocks), to: PartConfig

  @doc """
  Enumerates correction job descriptors eligible for bulk AI correction across
  all submissions of the exam. Each job carries the part's text comparison
  options as `match_opts` (see `Tasky.Correction.StringComparator.match_opts/1`). Excludes parts without a
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
      exam
      |> auto_correct_part_ids()
      |> MapSet.reject(&(Map.get(max_points_map, &1) in [nil, 0]))

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
            match_opts: StringComparator.match_opts(part_cfg)
          }
        end
      end)
      |> Enum.sort_by(& &1.part_id)
    end
  end

  # --- AnswerGroups: see Tasky.Exams.AnswerGroups ---

  defdelegate list_part_answer_groups(exam, part_id), to: Tasky.Exams.AnswerGroups

  @doc """
  Reconstructs the answer-filled "sample solution" document by merging the
  exam's answer-free `content` with the stored answers map (`sample_solution`).
  This is the single reconstruction point used by correction and previews.
  """
  def sample_solution_doc(%Exam{} = exam) do
    AnswerKey.merge(exam.content || %{}, exam.sample_solution || %{})
  end

  # --- LearnerReturn: see Tasky.Exams.LearnerReturn ---

  defdelegate sample_solution_doc_for_learner(exam), to: Tasky.Exams.LearnerReturn
  defdelegate learner_verdicts(exam, submission), to: Tasky.Exams.LearnerReturn
  defdelegate learner_points(exam, submission), to: Tasky.Exams.LearnerReturn
  defdelegate learner_part_points(exam, sub), to: Tasky.Exams.LearnerReturn

  defdelegate return_doc_for_learner(exam, base_doc, verdicts, opts \\ []),
    to: Tasky.Exams.LearnerReturn

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

  # --- PubSub for exam content ---

  @doc """
  Subscribes to saves of an exam's content: `:exam_content_saved` after each
  `save_exam_structure/3`. The teacher's preview follows it — the editor's
  last autosave lands only after the switch to the preview tab.
  """
  def subscribe_exam_content(exam_id) do
    Phoenix.PubSub.subscribe(Tasky.PubSub, "exam_content:#{exam_id}")
  end

  # --- PubSub for exam status ---

  @doc """
  Subscribes to exam status updates for a given exam ID.
  """
  def subscribe_exam(exam_id) do
    Phoenix.PubSub.subscribe(Tasky.PubSub, "exam:#{exam_id}")
  end

  @doc """
  The exam as a learner's process may hold it: the sample solution, the
  correction settings and the SEB passwords blanked out.

  A participant view keeps the exam in its assigns for as long as the exam
  runs. None of these is rendered there, but holding them meant one careless
  `{@exam...}` or hook attribute away from handing them to the learner. The
  Config Key check that needs the passwords runs before, in
  `TaskyWeb.SebGuardHook`, on its own copy.
  """
  def learner_exam(%Exam{} = exam) do
    %{
      exam
      | sample_solution: %{},
        sample_solution_points: %{},
        sample_solution_block_points: %{},
        ai_correction_config: %{},
        seb_quit_password: nil,
        seb_admin_password: nil
    }
  end

  @doc """
  Broadcasts an exam status change to all subscribers.
  """
  def broadcast_exam_update(%Exam{} = exam) do
    Phoenix.PubSub.broadcast(Tasky.PubSub, "exam:#{exam.id}", {:exam_status_changed, exam})
  end

  # --- Files: see Tasky.Exams.Files ---

  defdelegate list_exam_attachments(exam), to: Tasky.Exams.Files
  defdelegate get_exam_attachment(exam, id), to: Tasky.Exams.Files

  defdelegate get_exam_attachment_by_stored_filename(exam_id, stored_filename),
    to: Tasky.Exams.Files

  defdelegate create_exam_attachment(scope, exam, attrs), to: Tasky.Exams.Files
  defdelegate delete_exam_attachment(scope, attachment), to: Tasky.Exams.Files
  defdelegate list_upload_fields(exam), to: Tasky.Exams.Files
  defdelegate get_upload_field(exam, id), to: Tasky.Exams.Files
  defdelegate create_upload_field(scope, exam, attrs), to: Tasky.Exams.Files
  defdelegate update_upload_field(scope, field, attrs), to: Tasky.Exams.Files
  defdelegate delete_upload_field(scope, field), to: Tasky.Exams.Files
  defdelegate exam_has_files?(exam), to: Tasky.Exams.Files
  defdelegate list_exam_submission_files(exam), to: Tasky.Exams.Files
  defdelegate list_submission_files(submission), to: Tasky.Exams.Files
  defdelegate get_submission_file(submission, field_id), to: Tasky.Exams.Files
  defdelegate get_submission_file_by_id(submission, file_id), to: Tasky.Exams.Files
  defdelegate put_submission_file(submission, field, attrs), to: Tasky.Exams.Files
  defdelegate delete_submission_file(submission, file), to: Tasky.Exams.Files
  defdelegate missing_required_uploads(submission), to: Tasky.Exams.Files
end
