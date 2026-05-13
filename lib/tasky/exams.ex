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
  The exam must be in "open" status.
  """
  def create_exam_submission(%Exam{} = exam, attrs) do
    if exam.status != "open" do
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

          result

        error ->
          error
      end
    end
  end

  @doc """
  Splits a TipTap document into parts separated by pageBreak nodes.

  Returns a list of `%{id, label, nodes}`:
    * `id` — the pageBreak's `pageId` (string), or `"start"` for the first part
    * `label` — the text of the first heading found in the part, or `"Teil N"`
    * `nodes` — the nodes belonging to this part (pageBreak markers excluded)
  """
  def split_content_into_parts(doc) when is_map(doc) do
    nodes = Map.get(doc, "content", []) || []

    {parts, last} =
      Enum.reduce(nodes, {[], %{id: "start", nodes: []}}, fn node, {acc, current} ->
        case node do
          %{"type" => "pageBreak"} = pb ->
            page_id =
              pb |> Map.get("attrs", %{}) |> Map.get("pageId") |> to_string_or_nil() ||
                "page-#{length(acc) + 1}"

            {[current | acc], %{id: page_id, nodes: []}}

          other ->
            {acc, %{current | nodes: current.nodes ++ [other]}}
        end
      end)

    [last | parts]
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.map(fn {part, idx} ->
      %{
        id: part.id,
        label: first_heading_text(part.nodes) || "Teil #{idx}",
        nodes: part.nodes
      }
    end)
  end

  def split_content_into_parts(_), do: []

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(v), do: to_string(v)

  defp first_heading_text(nodes) do
    Enum.find_value(nodes, fn
      %{"type" => "heading", "content" => children} when is_list(children) ->
        children
        |> Enum.map_join("", fn
          %{"text" => text} -> text
          _ -> ""
        end)
        |> case do
          "" -> nil
          text -> text
        end

      _ ->
        nil
    end)
  end

  @doc """
  Reassembles a list of parts (as returned by `split_content_into_parts/1`)
  back into a TipTap doc, inserting pageBreak nodes between parts.
  The first part's id (`"start"` by convention) is dropped as a marker.
  """
  def assemble_parts_into_content(parts) when is_list(parts) do
    nodes =
      parts
      |> Enum.with_index()
      |> Enum.flat_map(fn {part, idx} ->
        if idx == 0 do
          part.nodes
        else
          [%{"type" => "pageBreak", "attrs" => %{"pageId" => part.id}} | part.nodes]
        end
      end)

    %{"type" => "doc", "content" => nodes}
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
    parts =
      submission
      |> correction_content()
      |> split_content_into_parts()

    unless Enum.any?(parts, &(&1.id == part_id)) do
      raise ArgumentError, "unknown part_id: #{inspect(part_id)}"
    end

    new_parts =
      Enum.map(parts, fn p -> if p.id == part_id, do: %{p | nodes: part_nodes}, else: p end)

    new_doc = assemble_parts_into_content(new_parts)

    submission
    |> Ecto.Changeset.change(%{corrected_content: new_doc})
    |> Repo.update()
  end

  @doc """
  Persists the teacher's sample solution for a single part.

  `part_id` identifies the page boundary (the same id returned by
  `split_content_into_parts/1` over the sample solution); `part_nodes` is the
  new list of nodes for that part. The function loads the current sample
  solution, splits it, replaces the matching part, reassembles, and saves
  back into `sample_solution`. Raises if `part_id` is not present.
  """
  def update_sample_solution_part_content(%Exam{} = exam, part_id, part_nodes)
      when is_binary(part_id) and is_list(part_nodes) do
    doc =
      case exam.sample_solution do
        s when is_map(s) and map_size(s) > 0 -> s
        _ -> exam.content || %{}
      end

    parts = split_content_into_parts(doc)

    unless Enum.any?(parts, &(&1.id == part_id)) do
      raise ArgumentError, "unknown part_id: #{inspect(part_id)}"
    end

    new_parts =
      Enum.map(parts, fn p ->
        if p.id == part_id, do: %{p | nodes: part_nodes}, else: p
      end)

    new_doc = assemble_parts_into_content(new_parts)

    exam
    |> Ecto.Changeset.change(%{sample_solution: new_doc})
    |> Repo.update()
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

  Each entry is `%{index: i, text: t, verdict: "correct" | "half" | "wrong" | nil}`.
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

  Persists three things atomically:
    * `block_verdicts` — keyed by `"<part_id>:<index>"`
    * `corrected_content` — the trailing ✅/🟡/❌ marker on the affected
      node is rewritten to match the new verdict
    * `points_per_part[part_id]` — recomputed as
      `(correct + 0.5 * half) * (max_points / block_count)`, rounded to
      0.5 increments. If the part has no `max_points` configured or no
      answer blocks, the entry is removed.

  Broadcasts the updated submission so the correction grid stays in sync.
  """
  def set_block_verdict(%ExamSubmission{} = submission, part_id, index, verdict)
      when is_binary(part_id) and is_integer(index) and
             verdict in ["correct", "half", "wrong", nil] do
    exam = Repo.get!(Exam, submission.exam_id)
    max_points = Map.get(exam.sample_solution_points || %{}, part_id)

    parts =
      submission
      |> correction_content()
      |> split_content_into_parts()

    case Enum.find(parts, &(&1.id == part_id)) do
      nil ->
        {:error, :unknown_part}

      part ->
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
        blocks = NodePatcher.list_answer_blocks(part.nodes)
        effective_indexed = effective_verdicts_for_part(blocks, new_verdicts, part_id)

        block_count = length(blocks)

        new_part_points =
          compute_part_points_from_indexed(effective_indexed, block_count, max_points)

        new_points_per_part =
          if is_nil(new_part_points) do
            Map.delete(submission.points_per_part || %{}, part_id)
          else
            Map.put(submission.points_per_part || %{}, part_id, new_part_points)
          end

        rewritten_nodes = NodePatcher.rewrite_markers(part.nodes, effective_indexed)

        new_parts =
          Enum.map(parts, fn p ->
            if p.id == part_id, do: %{p | nodes: rewritten_nodes}, else: p
          end)

        new_doc = assemble_parts_into_content(new_parts)

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

  defp compute_part_points_from_indexed(_indexed, 0, _max_points), do: nil
  defp compute_part_points_from_indexed(_indexed, _count, nil), do: nil

  defp compute_part_points_from_indexed(indexed, block_count, max_points)
       when is_number(max_points) and block_count > 0 do
    per_block = max_points / block_count

    weighted_sum =
      Enum.reduce(indexed, 0.0, fn
        {_idx, "correct"}, acc -> acc + 1.0
        {_idx, "half"}, acc -> acc + 0.5
        {_idx, "wrong"}, acc -> acc + 0.0
        _, acc -> acc
      end)

    total = weighted_sum * per_block

    rounded = Float.round(total * 2) / 2

    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
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
  Enumerates `(submission, part, ignore_spelling?)` triples eligible for bulk
  AI correction across all submissions of the exam. Excludes parts without a
  max-points entry or without content for that submission.

  Jobs are grouped by `part_id` (all submissions for part A, then all for
  part B, ...) so that consecutive Anthropic calls reuse the same cached
  system prefix (rules + sample solution) within the 5-minute cache TTL.
  """
  def list_bulk_correction_jobs(%Exam{} = exam) do
    config = exam.ai_correction_config || %{}
    max_points_map = exam.sample_solution_points || %{}

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
      |> Enum.flat_map(fn submission ->
        parts =
          submission
          |> correction_content()
          |> split_content_into_parts()

        for part <- parts,
            MapSet.member?(auto_correct_part_ids, part.id),
            part.nodes != [] do
          %{
            submission_id: submission.id,
            part_id: part.id,
            ignore_spelling:
              config |> Map.get(part.id, %{}) |> Map.get("ignore_spelling", false) == true
          }
        end
      end)
      |> Enum.sort_by(& &1.part_id)
    end
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
end
