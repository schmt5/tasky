defmodule Tasky.Exams do
  @moduledoc """
  The Exams context.
  """

  import Ecto.Query, warn: false
  alias Tasky.Repo

  alias Tasky.Exams.Exam
  alias Tasky.Exams.ExamSubmission
  alias Tasky.Accounts.Scope
  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.AnswerKey

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

    case scope.user.role do
      "admin" ->
        exam

      "teacher" ->
        if exam.teacher_id == scope.user.id do
          exam
        else
          raise Ecto.NoResultsError, queryable: Exam
        end

      _ ->
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
  Duplicates an existing exam. The copy is always in "draft" status with no
  enrollment_token. If SEB is enabled, a fresh quit password is generated.
  """
  def duplicate_exam(scope, %Exam{} = source) do
    attrs = %{
      "name" => String.slice("Kopie von — #{source.name}", 0, 255),
      "content" => source.content || %{},
      "sample_solution" => source.sample_solution || %{},
      "sample_solution_points" => source.sample_solution_points || %{},
      "sample_solution_block_points" => source.sample_solution_block_points || %{},
      "seb_enabled" => source.seb_enabled,
      "seb_quit_password" =>
        if(source.seb_enabled,
          do: (:rand.uniform(899_999) + 100_000) |> Integer.to_string(),
          else: nil
        ),
      "ai_correction_config" => source.ai_correction_config || %{}
      # status defaults to "draft" via schema
      # enrollment_token stays nil
      # teacher_id set from scope via create_changeset
    }

    create_exam(scope, attrs)
  end

  @doc """
  Updates an exam.
  """
  def update_exam(%Exam{} = exam, attrs) do
    exam
    |> Exam.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the status of an exam.
  """
  def update_exam_status(%Exam{} = exam, status) do
    result =
      exam
      |> Ecto.Changeset.change(%{status: status})
      |> Ecto.Changeset.validate_inclusion(:status, ~w(draft open running finished archived))
      |> Repo.update()

    case result do
      {:ok, updated_exam} ->
        broadcast_exam_update(updated_exam)
        {:ok, updated_exam}

      error ->
        error
    end
  end

  @doc """
  Opens an exam session by generating an enrollment token and setting status to open.
  """
  def open_exam_session(%Exam{} = exam) do
    token = generate_enrollment_token()

    result =
      exam
      |> Ecto.Changeset.change(%{status: "open", enrollment_token: token})
      |> Repo.update()

    case result do
      {:ok, updated_exam} ->
        broadcast_exam_update(updated_exam)
        {:ok, updated_exam}

      error ->
        error
    end
  end

  defp generate_enrollment_token do
    :crypto.strong_rand_bytes(4)
    |> Base.encode32(case: :lower, padding: false)
    |> String.slice(0, 6)
    |> String.upcase()
  end

  @doc """
  Deletes an exam.
  """
  def delete_exam(%Exam{} = exam) do
    Repo.delete(exam)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking exam changes.
  """
  def change_exam(%Exam{} = exam, attrs \\ %{}) do
    Exam.changeset(exam, attrs)
  end

  # --- Guest / Submission functions ---

  @doc """
  Gets an exam by its enrollment token. Used for the guest enrollment page.
  Raises if not found.
  """
  def get_exam_by_enrollment_token!(token) do
    Repo.get_by!(Exam, enrollment_token: token)
    |> Repo.preload([:teacher])
  end

  @doc """
  Gets an exam by its enrollment token, or `nil` if the token is unknown.
  Lets the enrollment page render a friendly "invalid link" state instead
  of raising a generic 404.
  """
  def get_exam_by_enrollment_token(token) when is_binary(token) do
    case Repo.get_by(Exam, enrollment_token: token) do
      nil -> nil
      exam -> Repo.preload(exam, [:teacher])
    end
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
  Creates an exam submission for a guest user.
  The exam must be in "open" or "running" status.
  """
  def create_exam_submission(%Exam{} = exam, attrs) do
    if exam.status not in ["open", "running"] do
      {:error, :exam_not_open}
    else
      %ExamSubmission{exam_id: exam.id}
      |> ExamSubmission.changeset(attrs)
      |> Repo.insert()
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
    submission = Repo.preload(submission, :exam, force: true)

    cond do
      submission.submitted ->
        {:error, :already_submitted}

      submission.exam.status != "running" ->
        {:error, :exam_not_running}

      true ->
        submission
        |> ExamSubmission.content_changeset(%{content: content})
        |> Repo.update()
    end
  end

  @doc """
  Marks an exam submission as submitted.
  Only allowed when the associated exam is still running.
  """
  def submit_exam_submission(%ExamSubmission{} = submission) do
    submission = Repo.preload(submission, :exam, force: true)

    if submission.exam.status != "running" do
      {:error, :exam_not_running}
    else
      case submission
           |> Ecto.Changeset.change(%{submitted: true})
           |> Repo.update() do
        {:ok, updated} = result ->
          Phoenix.PubSub.broadcast(
            Tasky.PubSub,
            "exam_cockpit:#{submission.exam.id}",
            {:submission_submitted, updated}
          )

          Tasky.AI.BulkCorrectionRunner.start_for_exam(
            submission.exam,
            submission_id: updated.id
          )

          result

        error ->
          error
      end
    end
  end

  @doc """
  Splits a TipTap document into question-delimited parts.

  Each part begins with a level-3 heading (`h3`) which represents the
  question. Anything before the first `h3` is *preamble* (intro /
  instructions) and is NOT returned — use `content_preamble/1` to access it.

  Returns a list of `%{id, label, nodes}`:
    * `id` — positional, `"q-1"`, `"q-2"`, …
    * `label` — the heading's inline text content, or fallback `"Frage N"`
    * `nodes` — the part's nodes, starting with the leading `h3` node
  """
  def split_content_into_parts(doc) when is_map(doc) do
    nodes = Map.get(doc, "content", []) || []

    {parts, current} =
      Enum.reduce(nodes, {[], nil}, fn
        node, {parts, current} when is_map(node) ->
          if question_heading?(node) do
            part = build_part_from_heading(node, length(parts) + count_if(current))
            parts = if current, do: [current | parts], else: parts
            {parts, part}
          else
            if current,
              do: {parts, %{current | nodes: current.nodes ++ [node]}},
              # pre-first-question content = preamble; ignore here
              else: {parts, nil}
          end
      end)

    parts = if current, do: [current | parts], else: parts
    Enum.reverse(parts)
  end

  def split_content_into_parts(_), do: []

  defp question_heading?(%{"type" => "heading", "attrs" => %{"level" => 3}}), do: true
  defp question_heading?(_), do: false

  defp count_if(nil), do: 0
  defp count_if(_), do: 1

  defp build_part_from_heading(h, idx) do
    label = heading_text(h) || "Frage #{idx + 1}"
    %{id: "q-#{idx + 1}", label: label, nodes: [h]}
  end

  defp heading_text(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map_join("", fn
      %{"text" => t} when is_binary(t) -> t
      _ -> ""
    end)
    |> case do
      "" -> nil
      t -> t
    end
  end

  defp heading_text(_), do: nil

  @doc """
  Returns the preamble — nodes before the first level-3 heading. Empty list
  if the document has no preamble (starts with an h3) or no h3 headings.
  """
  def content_preamble(doc) when is_map(doc) do
    (doc |> Map.get("content", []) || [])
    |> Enum.take_while(fn n -> not question_heading?(n) end)
  end

  def content_preamble(_), do: []

  @doc """
  Reassembles a TipTap doc from a preamble (nodes before the first question)
  and a list of parts (as returned by `split_content_into_parts/1`).

  Each part's `nodes` already includes its leading `question` node, so the
  reassembly is just concatenation. Inverse of `split_content_into_parts/1`
  + `content_preamble/1`.
  """
  def assemble_parts_into_content(preamble, parts)
      when is_list(preamble) and is_list(parts) do
    %{
      "type" => "doc",
      "content" => preamble ++ Enum.flat_map(parts, & &1.nodes)
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
  def mark_part_corrected(%ExamSubmission{} = submission, part_id)
      when is_binary(part_id) do
    parts = Enum.uniq([part_id | submission.corrected_parts || []])
    update_corrected_parts(submission, parts)
  end

  @doc """
  Removes a part from the submission's corrected list.
  """
  def unmark_part_corrected(%ExamSubmission{} = submission, part_id)
      when is_binary(part_id) do
    parts = Enum.reject(submission.corrected_parts || [], &(&1 == part_id))
    update_corrected_parts(submission, parts)
  end

  defp update_corrected_parts(submission, parts) do
    case submission
         |> Ecto.Changeset.change(%{corrected_parts: parts})
         |> Repo.update() do
      {:ok, updated} = result ->
        Phoenix.PubSub.broadcast(
          Tasky.PubSub,
          "exam_correction:#{updated.exam_id}",
          {:submission_corrected_parts_changed, updated}
        )

        result

      error ->
        error
    end
  end

  @doc """
  Marks a single part of a submission as AI-auto-corrected (idempotent).
  Broadcasts `{:submission_corrected_parts_changed, submission}`.
  """
  def mark_part_auto_corrected(%ExamSubmission{} = submission, part_id)
      when is_binary(part_id) do
    parts = Enum.uniq([part_id | submission.auto_corrected_parts || []])
    update_auto_corrected_parts(submission, parts)
  end

  @doc """
  Removes a part from the submission's AI-auto-corrected list.
  """
  def unmark_part_auto_corrected(%ExamSubmission{} = submission, part_id)
      when is_binary(part_id) do
    parts = Enum.reject(submission.auto_corrected_parts || [], &(&1 == part_id))
    update_auto_corrected_parts(submission, parts)
  end

  defp update_auto_corrected_parts(submission, parts) do
    case submission
         |> Ecto.Changeset.change(%{auto_corrected_parts: parts})
         |> Repo.update() do
      {:ok, updated} = result ->
        Phoenix.PubSub.broadcast(
          Tasky.PubSub,
          "exam_correction:#{updated.exam_id}",
          {:submission_corrected_parts_changed, updated}
        )

        result

      error ->
        error
    end
  end

  @doc """
  Persists the teacher's corrected content for a single part.

  `part_id` identifies the page boundary (the same id returned by
  `split_content_into_parts/1`); `part_nodes` is the new list of nodes for
  that part. The function loads the current correction doc, splits it,
  replaces the matching part, reassembles, and saves back into
  `corrected_content`. Raises if `part_id` is not present.
  """
  def update_corrected_part_content(%ExamSubmission{} = submission, part_id, part_nodes)
      when is_binary(part_id) and is_list(part_nodes) do
    doc = correction_content(submission)
    parts = split_content_into_parts(doc)
    preamble = content_preamble(doc)

    unless Enum.any?(parts, &(&1.id == part_id)) do
      raise ArgumentError, "unknown part_id: #{inspect(part_id)}"
    end

    new_parts =
      Enum.map(parts, fn p -> if p.id == part_id, do: %{p | nodes: part_nodes}, else: p end)

    new_doc = assemble_parts_into_content(preamble, new_parts)

    submission
    |> Ecto.Changeset.change(%{corrected_content: new_doc})
    |> Repo.update()
  end

  @doc """
  Saves the structure of the exam from the "Inhalt" tab.

  The document is answer-free (input blocks come back empty from this tab), so
  we do NOT split — we only `ensure_ids/1` and persist as `content`. Any
  entries in `sample_solution` whose block id no longer exists in the new
  content are pruned. Re-runs auto-correction so existing submissions get
  re-graded against the (possibly restructured) exam.
  """
  def save_exam_structure(%Exam{} = exam, doc) when is_map(doc) do
    new_content = AnswerKey.ensure_ids(doc)
    pruned_answers = prune_orphan_answers(new_content, exam.sample_solution || %{})

    persist_content_and_answers(exam, new_content, pruned_answers)
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
  def save_sample_solution_part(%Exam{} = exam, part_id, part_nodes)
      when is_binary(part_id) and is_list(part_nodes) do
    {blanked_doc, partial_answers} =
      AnswerKey.split(%{"type" => "doc", "content" => part_nodes})

    blanked_part_nodes = Map.get(blanked_doc, "content", [])

    # The splice below is a read-modify-write over the whole content. The
    # stacked Musterlösung view autosaves each part independently, so two
    # near-simultaneous requests for different parts could otherwise clobber
    # each other. BEGIN IMMEDIATE takes SQLite's write lock up front, so the
    # refetch inside the transaction always sees the latest committed state.
    result =
      Repo.transaction(
        fn ->
          locked_exam = Repo.get!(Exam, exam.id)

          content = locked_exam.content || %{}
          parts = split_content_into_parts(content)
          preamble = content_preamble(content)

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
        end,
        mode: :immediate
      )

    with {:ok, updated} <- result do
      Tasky.AI.BulkCorrectionRunner.start_for_exam(updated)
      {:ok, updated}
    end
  end

  defp persist_content_and_answers(exam, content, answers) do
    {pruned_block_points, synced_points} =
      prune_orphan_block_points(
        content,
        exam.sample_solution_block_points || %{},
        exam.sample_solution_points || %{}
      )

    case exam
         |> Exam.changeset(%{
           content: content,
           sample_solution: answers,
           sample_solution_block_points: pruned_block_points,
           sample_solution_points: synced_points
         })
         |> Repo.update() do
      {:ok, updated} = result ->
        Tasky.AI.BulkCorrectionRunner.start_for_exam(updated)
        result

      error ->
        error
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
  defp prune_orphan_block_points(content, block_points, points) do
    keep_ids = AnswerKey.block_ids(content)
    part_ids = content |> split_content_into_parts() |> MapSet.new(& &1.id)

    pruned =
      block_points
      |> Enum.filter(fn {pid, _} -> MapSet.member?(part_ids, pid) end)
      |> Enum.map(fn {pid, m} -> {pid, Map.take(m, MapSet.to_list(keep_ids))} end)
      |> Enum.reject(fn {_pid, m} -> m == %{} end)
      |> Map.new()

    synced_points =
      Enum.reduce(pruned, points, fn {pid, m}, acc ->
        Map.put(acc, pid, normalize_block_points(Enum.sum(Map.values(m))))
      end)

    {pruned, synced_points}
  end

  @doc """
  Sets (or clears, when `points` is `nil`) the maximum points for a single
  part of an exam's sample solution.
  """
  def set_sample_solution_part_points(%Exam{} = exam, part_id, points)
      when is_binary(part_id) do
    current = exam.sample_solution_points || %{}

    new_map =
      if is_nil(points) do
        Map.delete(current, part_id)
      else
        Map.put(current, part_id, points)
      end

    exam
    |> Ecto.Changeset.change(%{sample_solution_points: new_map})
    |> Repo.update()
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
  def set_sample_solution_block_point(%Exam{} = exam, part_id, answer_id, points)
      when is_binary(part_id) and is_binary(answer_id) and is_number(points) do
    part_map =
      (exam.sample_solution_block_points || %{})
      |> Map.get(part_id, %{})
      |> Map.put(answer_id, normalize_block_points(points))

    put_custom_block_points(exam, part_id, part_map)
  end

  @doc """
  Enables custom per-block point distribution for a part by seeding every
  answer block with an equal share (rounded to 0.25) of the part's current
  max points. The part total becomes the sum of the seeded shares.
  """
  def enable_custom_block_points(%Exam{} = exam, part_id) when is_binary(part_id) do
    blocks = exam_part_blocks(exam, part_id)
    max_points = Map.get(exam.sample_solution_points || %{}, part_id)

    share =
      if is_number(max_points) and blocks != [] do
        normalize_block_points(max_points / length(blocks))
      else
        0
      end

    part_map =
      blocks
      |> Enum.filter(& &1.answer_id)
      |> Map.new(fn b -> {b.answer_id, share} end)

    put_custom_block_points(exam, part_id, part_map)
  end

  @doc """
  Disables custom distribution for a part. The part keeps its current total
  in `sample_solution_points` and falls back to the equal split.
  """
  def clear_custom_block_points(%Exam{} = exam, part_id) when is_binary(part_id) do
    block_points = Map.delete(exam.sample_solution_block_points || %{}, part_id)

    exam
    |> Ecto.Changeset.change(%{sample_solution_block_points: block_points})
    |> Repo.update()
  end

  defp put_custom_block_points(%Exam{} = exam, part_id, part_map) do
    block_points = Map.put(exam.sample_solution_block_points || %{}, part_id, part_map)
    total = part_map |> Map.values() |> Enum.sum() |> normalize_block_points()
    points = Map.put(exam.sample_solution_points || %{}, part_id, total)

    exam
    |> Ecto.Changeset.change(%{
      sample_solution_block_points: block_points,
      sample_solution_points: points
    })
    |> Repo.update()
  end

  defp normalize_block_points(n) when is_number(n) do
    rounded = Float.round(max(n, 0) * 4.0) / 4
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end

  defp exam_part_blocks(%Exam{} = exam, part_id) do
    (exam.content || %{})
    |> split_content_into_parts()
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
  def set_part_points(%ExamSubmission{} = submission, part_id, points)
      when is_binary(part_id) do
    current = submission.points_per_part || %{}

    new_map =
      if is_nil(points) do
        Map.delete(current, part_id)
      else
        Map.put(current, part_id, points)
      end

    case submission
         |> Ecto.Changeset.change(%{points_per_part: new_map})
         |> Repo.update() do
      {:ok, updated} = result ->
        Phoenix.PubSub.broadcast(
          Tasky.PubSub,
          "exam_correction:#{updated.exam_id}",
          {:submission_corrected_parts_changed, updated}
        )

        result

      error ->
        error
    end
  end

  @doc """
  Lists the answer-bearing blocks in a single part of a submission, paired
  with the teacher's current verdict for each (if any).

  Each entry is `%{index: i, text: t, verdict: v}` where `v` is `"correct"`,
  `"half"` (legacy), `"wrong"`, a number (manual points) or `nil`.
  Verdicts are keyed by `"<part_id>:<index>"` in `submission.block_verdicts`.
  """
  def list_part_answer_blocks(%ExamSubmission{} = submission, part_id)
      when is_binary(part_id) do
    parts =
      submission
      |> correction_content()
      |> split_content_into_parts()

    case Enum.find(parts, &(&1.id == part_id)) do
      nil ->
        []

      part ->
        explicit = submission.block_verdicts || %{}

        part.nodes
        |> NodePatcher.list_answer_blocks()
        |> Enum.map(fn entry ->
          key = block_verdict_key(part_id, entry.index)
          verdict = Map.get(explicit, key) || entry.inferred_verdict
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
    * `block_verdicts` — keyed by `"<part_id>:<index>"`
    * `corrected_content` — the trailing ✅/🟡/❌ marker on the affected
      node is rewritten to match the new verdict
    * `points_per_part[part_id]` — recomputed as the sum of each block's
      awarded points (per-block max from `resolve_block_points/3`), rounded
      to 0.25 increments. If the part has no points configured or no
      answer blocks, the entry is removed.

  Broadcasts the updated submission so the correction grid stays in sync.
  """
  def set_block_verdict(%ExamSubmission{} = submission, part_id, index, verdict)
      when is_binary(part_id) and is_integer(index) and
             (verdict in ["correct", "half", "wrong", nil] or is_number(verdict)) do
    exam = Repo.get!(Exam, submission.exam_id)

    doc = correction_content(submission)
    parts = split_content_into_parts(doc)
    preamble = content_preamble(doc)

    case Enum.find(parts, &(&1.id == part_id)) do
      nil ->
        {:error, :unknown_part}

      part ->
        blocks = NodePatcher.list_answer_blocks(part.nodes)
        points_by_index = resolve_block_points(exam, part_id, blocks)

        verdict = normalize_verdict(verdict, points_by_index && points_by_index[index])

        key = block_verdict_key(part_id, index)
        current_verdicts = submission.block_verdicts || %{}

        new_verdicts =
          if is_nil(verdict) do
            Map.delete(current_verdicts, key)
          else
            Map.put(current_verdicts, key, verdict)
          end

        # Effective verdict for each block: explicit teacher choice if any,
        # otherwise fall back to the verdict inferred from the existing
        # ✅/🟡/❌ marker on the node (e.g. left by AI auto-correction).
        # This ensures untouched blocks keep their markers and contribute
        # their points when the teacher only edits a single block.
        effective_indexed = effective_verdicts_for_part(blocks, new_verdicts, part_id)

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

        new_doc = assemble_parts_into_content(preamble, new_parts)

        case submission
             |> Ecto.Changeset.change(%{
               block_verdicts: new_verdicts,
               corrected_content: new_doc,
               points_per_part: new_points_per_part
             })
             |> Repo.update() do
          {:ok, updated} = result ->
            Phoenix.PubSub.broadcast(
              Tasky.PubSub,
              "exam_correction:#{updated.exam_id}",
              {:submission_corrected_parts_changed, updated}
            )

            result

          error ->
            error
        end
    end
  end

  defp block_verdict_key(part_id, index), do: "#{part_id}:#{index}"

  defp effective_verdicts_for_part(blocks, explicit_verdicts, part_id) do
    Enum.reduce(blocks, %{}, fn entry, acc ->
      key = block_verdict_key(part_id, entry.index)

      case Map.get(explicit_verdicts, key) do
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

  # Manual numeric verdicts are rounded to 0.25 steps and clamped to the
  # block's max points (when known). String verdicts pass through.
  defp normalize_verdict(v, block_max) when is_number(v) do
    v = max(v, 0)
    v = if is_number(block_max), do: min(v, block_max), else: v
    Float.round(v * 4.0) / 4
  end

  defp normalize_verdict(v, _block_max), do: v

  defp compute_part_points(_indexed, nil), do: nil

  defp compute_part_points(indexed, points_by_index) when is_map(points_by_index) do
    total =
      Enum.reduce(indexed, 0.0, fn
        {idx, "correct"}, acc -> acc + block_points_value(points_by_index[idx])
        {idx, "half"}, acc -> acc + block_points_value(points_by_index[idx]) * 0.5
        {_idx, "wrong"}, acc -> acc
        {_idx, v}, acc when is_number(v) -> acc + v
        _, acc -> acc
      end)

    rounded = Float.round(total * 4) / 4

    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end

  # Maps numeric (manual) verdicts to the marker vocabulary understood by
  # NodePatcher.rewrite_markers: full block points → ✅, zero → ❌, else 🟡.
  defp marker_verdicts(indexed, points_by_index) do
    Map.new(indexed, fn
      {idx, v} when is_number(v) ->
        block_max = points_by_index && points_by_index[idx]

        cond do
          v == 0 -> {idx, "wrong"}
          is_number(block_max) and v >= block_max -> {idx, "correct"}
          true -> {idx, "half"}
        end

      {idx, v} ->
        {idx, v}
    end)
  end

  @doc """
  Updates the grading max-points override for the exam. Pass `nil` to clear
  the override (the grading view then falls back to the sum of
  `sample_solution_points`).
  """
  def update_grading_max_points(%Exam{} = exam, value) do
    exam
    |> Ecto.Changeset.change(%{grading_max_points: value})
    |> Repo.update()
  end

  @doc """
  Sets (or clears, when `mark` is `nil`) the teacher-adjusted final mark for
  a submission. The mark is stored as a float; when `nil`, callers should
  fall back to the calculated mark from `points / max_points`.
  """
  def set_submission_mark(%ExamSubmission{} = submission, mark) do
    submission
    |> Ecto.Changeset.change(%{mark: mark})
    |> Repo.update()
  end

  @doc """
  Updates the AI correction configuration for a single part of an exam.
  The config is stored as a map keyed by part_id.
  """
  def update_ai_correction_config(%Exam{} = exam, part_id, config)
      when is_binary(part_id) and is_map(config) do
    current = exam.ai_correction_config || %{}
    updated = Map.put(current, part_id, config)

    exam
    |> Ecto.Changeset.change(%{ai_correction_config: updated})
    |> Repo.update()
  end

  @doc """
  Bulk-updates the AI correction configuration for multiple parts at once.
  `updates` is a map of `%{part_id => %{key => value, ...}, ...}`.
  Each part's config is merged with the existing config for that part.
  """
  def update_ai_correction_config_bulk(%Exam{} = exam, updates) when is_map(updates) do
    current = exam.ai_correction_config || %{}

    merged =
      Enum.reduce(updates, current, fn {part_id, new_config}, acc ->
        existing = Map.get(acc, part_id, %{})
        Map.put(acc, part_id, Map.merge(existing, new_config))
      end)

    exam
    |> Ecto.Changeset.change(%{ai_correction_config: merged})
    |> Repo.update()
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

  Jobs are grouped by `part_id` (all submissions for part A, then all for
  part B, ...) so that consecutive Anthropic calls reuse the same cached
  system prefix (rules + sample solution) within the 5-minute cache TTL.
  """
  def list_bulk_correction_jobs(%Exam{} = exam, opts \\ []) do
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
          |> split_content_into_parts()

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
      |> split_content_into_parts()
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
      |> split_content_into_parts()
      |> Enum.find(&(&1.id == part_id))

    labels_by_index =
      case exam_part do
        nil -> %{}
        p -> answer_block_labels(p.nodes)
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
          |> split_content_into_parts()
          |> Enum.find(&(&1.id == part_id))
          |> case do
            nil -> []
            p -> NodePatcher.list_answer_blocks(p.nodes)
          end

        {sub, blocks}
      end)

    Enum.map(exam_block_indices, fn index ->
      sample_text = Map.get(sample_text_by_index, index)

      sample_answers =
        (sample_text || "")
        |> String.split(";")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      groups = build_answer_groups(per_submission_blocks, part_id, index, sample_answers, opts)

      %{
        index: index,
        label: Map.get(labels_by_index, index),
        max_points: points_by_index && Map.get(points_by_index, index),
        sample_answers: sample_answers,
        groups: groups
      }
    end)
  end

  defp build_answer_groups(per_submission_blocks, part_id, index, sample_answers, opts) do
    entries =
      Enum.map(per_submission_blocks, fn {sub, blocks} ->
        text =
          case Enum.find(blocks, &(&1.index == index)) do
            nil -> nil
            %{text: t} -> t
          end

        {sub, normalize_group_text(text)}
      end)

    entries
    |> Enum.group_by(fn {_sub, text} -> text end)
    |> Enum.map(fn {text, members} ->
      subs = Enum.map(members, fn {sub, _} -> sub end)
      build_one_group(text, subs, part_id, index, sample_answers, opts)
    end)
    |> Enum.sort_by(fn g -> -g.count end)
  end

  defp build_one_group(text, subs, part_id, index, sample_answers, opts) do
    verdicts =
      Enum.map(subs, fn s ->
        Map.get(s.block_verdicts || %{}, "#{part_id}:#{index}")
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

  defp answer_block_labels(nodes) when is_list(nodes) do
    {labels, _, _} = walk_labels(nodes, %{}, "", 0)
    labels
  end

  defp walk_labels(nodes, labels, buffer, counter) when is_list(nodes) do
    Enum.reduce(nodes, {labels, buffer, counter}, fn node, {l, b, c} ->
      visit_label(node, l, b, c)
    end)
  end

  @answer_node_types ["answerBlock", "lueckentext", "taskItem"]

  defp visit_label(%{"type" => type}, labels, buffer, counter)
       when type in @answer_node_types do
    label =
      case String.trim(buffer || "") do
        "" -> nil
        t -> t
      end

    {Map.put(labels, counter, label), "", counter + 1}
  end

  defp visit_label(%{"type" => "text", "text" => t}, labels, buffer, counter)
       when is_binary(t) do
    {labels, (buffer || "") <> t, counter}
  end

  # The leading h3 of a part is the question heading; its inline text is the
  # question label, not a sub-input label. Reset the buffer and skip its
  # content so the first answer block doesn't inherit the question text.
  defp visit_label(
         %{"type" => "heading", "attrs" => %{"level" => 3}},
         labels,
         _buffer,
         counter
       ),
       do: {labels, "", counter}

  # Tables: an answer cell is labelled by the preceding cell in the same row
  # (the common "Begriff | [Antwort]" layout, often repeated across the row).
  # We handle the row explicitly because the linear text buffer has no notion
  # of cell boundaries — without this, the header row and other cells leak
  # into the first answer's label.
  defp visit_label(%{"type" => "tableRow", "content" => cells}, labels, _buffer, counter)
       when is_list(cells) do
    {labels, _prev, counter} =
      Enum.reduce(cells, {labels, nil, counter}, fn cell, {l, prev, c} ->
        if cell_contains_answer?(cell) do
          {l2, c2} = label_answers(cell, l, prev, c)
          {l2, nil, c2}
        else
          {l, cell_text(cell), c}
        end
      end)

    {labels, "", counter}
  end

  defp visit_label(%{"content" => content}, labels, buffer, counter) when is_list(content) do
    walk_labels(content, labels, buffer, counter)
  end

  defp visit_label(_, labels, buffer, counter), do: {labels, buffer, counter}

  defp label_answers(%{"type" => type}, labels, label, counter)
       when type in @answer_node_types do
    normalized =
      case String.trim(label || "") do
        "" -> nil
        t -> t
      end

    {Map.put(labels, counter, normalized), counter + 1}
  end

  defp label_answers(%{"content" => content}, labels, label, counter) when is_list(content) do
    Enum.reduce(content, {labels, counter}, fn node, {l, c} ->
      label_answers(node, l, label, c)
    end)
  end

  defp label_answers(_, labels, _label, counter), do: {labels, counter}

  defp cell_contains_answer?(%{"type" => type}) when type in @answer_node_types, do: true

  defp cell_contains_answer?(%{"content" => content}) when is_list(content) do
    Enum.any?(content, &cell_contains_answer?/1)
  end

  defp cell_contains_answer?(_), do: false

  defp cell_text(%{"type" => "text", "text" => t}) when is_binary(t), do: t

  defp cell_text(%{"content" => content}) when is_list(content) do
    Enum.map_join(content, "", &cell_text/1)
  end

  defp cell_text(_), do: ""

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
end
