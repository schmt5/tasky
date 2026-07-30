defmodule Tasky.AI.BulkCorrectionRunner do
  @moduledoc """
  Runs auto-correction for every eligible (submission, part) pair of an
  exam, sequentially, under `Tasky.TaskSupervisor`. Broadcasts progress to
  the `exam_correction:<exam_id>` PubSub topic so the LiveView can react.

  Triggered automatically by `Exams.submit_exam_submission/1` (per-submission)
  and `Exams.save_exam_structure/2` / `Exams.save_sample_solution_part/3`
  (across all submitted submissions of the exam, when the teacher edits the
  exam structure or the model answers).

  Each job delegates to `Tasky.Correction.StringComparator` for
  deterministic, AI-free comparison. (The former AI-backed client was
  removed — rebuild a client cleanly if AI correction returns; see
  docs/ROBUSTNESS_PLAN.md Phase 7.)
  """

  require Logger

  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.StringComparator
  alias Tasky.Exams
  alias Tasky.Exams.ExamSubmission
  alias Tasky.Repo

  @doc """
  Starts the bulk-correction coordinator under `Tasky.TaskSupervisor`.

  At most one run is active per exam (`Tasky.BulkCorrectionRegistry`).
  Triggering while a run is active queues a full re-run on the active
  process instead of interleaving writes and progress streams. A crash
  anywhere still emits the terminal `:bulk_correction_done` broadcast so
  the UI can never hang on a stale progress bar.

  Options:
    * `:submission_id` — restrict the run to a single submission.

  Returns `{:ok, pid}` with the coordinator Task's pid.
  """
  def start_for_exam(exam, opts \\ []) do
    Task.Supervisor.start_child(
      Tasky.TaskSupervisor,
      fn ->
        case Registry.register(Tasky.BulkCorrectionRegistry, exam.id, nil) do
          {:ok, _} ->
            run_with_guaranteed_done(exam, opts)

          {:error, {:already_registered, pid}} ->
            # The active run's jobs may predate the change that triggered us —
            # ask it to run once more after it finishes.
            send(pid, :rerun)
            :ok
        end
      end,
      restart: :temporary
    )
  end

  defp run_with_guaranteed_done(exam, opts) do
    run(exam, opts)
    rerun_if_requested(exam)
  rescue
    exception ->
      Logger.error("Bulk correction run crashed: #{Exception.message(exception)}")

      Exams.broadcast_bulk_correction(
        exam.id,
        {:bulk_correction_done, %{total: 0, errors: []}}
      )
  end

  # Collapses any number of queued re-run requests into one full run against
  # a freshly loaded exam (the struct captured at start may be stale).
  defp rerun_if_requested(exam) do
    receive do
      :rerun ->
        drain_reruns()
        run(Repo.get!(Tasky.Exams.Exam, exam.id), [])
        rerun_if_requested(exam)
    after
      0 -> :ok
    end
  end

  defp drain_reruns do
    receive do
      :rerun -> drain_reruns()
    after
      0 -> :ok
    end
  end

  defp run(exam, opts) do
    jobs = Exams.list_bulk_correction_jobs(exam, opts)
    total = length(jobs)

    Exams.broadcast_bulk_correction(
      exam.id,
      {:bulk_correction_progress, %{done: 0, total: total, errors: 0}}
    )

    if total == 0 do
      Exams.broadcast_bulk_correction(
        exam.id,
        {:bulk_correction_done, %{total: 0, errors: []}}
      )
    else
      do_run(exam, jobs, total)
    end
  end

  defp do_run(exam, jobs, total) do
    final =
      Enum.reduce(jobs, %{done: 0, errors: []}, fn job, acc ->
        errors =
          case run_job(exam, job) do
            :ok -> acc.errors
            {:error, reason} -> [{job, reason} | acc.errors]
          end

        done = acc.done + 1

        Exams.broadcast_bulk_correction(
          exam.id,
          {:bulk_correction_progress, %{done: done, total: total, errors: length(errors)}}
        )

        %{done: done, errors: errors}
      end)

    Exams.broadcast_bulk_correction(
      exam.id,
      {:bulk_correction_done, %{total: total, errors: Enum.reverse(final.errors)}}
    )
  end

  defp run_job(exam, %{
         submission_id: submission_id,
         part_id: part_id,
         ignore_spelling: ignore_spelling,
         ignore_case: ignore_case
       }) do
    with {:ok, submission} <- fetch_submission(exam.id, submission_id),
         {:ok, submission_nodes} <- fetch_part_nodes(submission, part_id),
         sample_nodes = sample_solution_part_nodes(exam, part_id),
         max_points = Map.get(exam.sample_solution_points || %{}, part_id),
         {annotated_nodes, answer_count} = NodePatcher.annotate(submission_nodes),
         :ok <- ensure_has_answers(answer_count),
         blocks = NodePatcher.list_answer_blocks(submission_nodes),
         block_points = Exams.resolve_block_points(exam, part_id, blocks),
         {:ok, %{verdicts: verdicts, points: points}} <-
           StringComparator.correct_part(
             annotated_nodes,
             sample_nodes,
             max_points,
             %{
               ignore_spelling: ignore_spelling,
               ignore_case: ignore_case,
               block_points: block_points
             }
           ),
         corrected_nodes = NodePatcher.apply_verdicts(annotated_nodes, verdicts),
         {:ok, _updated} <-
           Exams.apply_auto_correction(:system, submission, part_id, corrected_nodes,
             verdicts: verdicts_by_answer_id(verdicts, blocks),
             points: clamp_points(points, max_points)
           ) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, inspect(other)}
    end
  rescue
    exception ->
      Logger.error("Bulk correction job crashed: #{Exception.message(exception)}")
      {:error, Exception.message(exception)}
  end

  defp ensure_has_answers(0), do: {:error, :no_answer_fields}
  defp ensure_has_answers(_), do: :ok

  defp fetch_submission(exam_id, submission_id) do
    case Repo.get_by(ExamSubmission, id: submission_id, exam_id: exam_id) do
      nil -> {:error, "submission not found"}
      submission -> {:ok, submission}
    end
  end

  defp fetch_part_nodes(submission, part_id) do
    parts =
      submission
      |> Exams.correction_content()
      |> Exams.split_content_into_parts()

    case Enum.find(parts, &(&1.id == part_id)) do
      nil -> {:error, "part not found in submission"}
      %{nodes: []} -> {:error, "submission has no content for this part"}
      part -> {:ok, part.nodes}
    end
  end

  defp sample_solution_part_nodes(exam, part_id) do
    exam
    |> Exams.sample_solution_doc()
    |> Exams.split_content_into_parts()
    |> Enum.find(&(&1.id == part_id))
    |> case do
      nil -> []
      p -> p.nodes
    end
  end

  defp clamp_points(points, nil), do: max(points, 0)
  defp clamp_points(points, max_points), do: points |> max(0) |> min(max_points)

  # StringComparator keys verdicts by the annotation id (`__ai_id`, which is
  # block index + 1); grading data is keyed by the block's stable answerId.
  defp verdicts_by_answer_id(verdicts, blocks) do
    by_index = Map.new(blocks, fn b -> {b.index, b.answer_id} end)

    for {id_str, verdict} <- verdicts,
        answer_id = Map.get(by_index, String.to_integer(id_str) - 1),
        is_binary(answer_id),
        into: %{} do
      {answer_id, verdict}
    end
  end
end
