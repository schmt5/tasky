defmodule Tasky.AI.BulkCorrectionRunner do
  @moduledoc """
  Runs auto-correction for every eligible (submission, part) pair of an
  exam, sequentially, under `Tasky.TaskSupervisor`. Broadcasts progress to
  the `exam_correction:<exam_id>` PubSub topic so the LiveView can react.

  Triggered automatically by `Exams.submit_exam_submission/1` (per-submission)
  and `Exams.save_exam_structure/2` / `Exams.save_sample_solution_part/3`
  (across all submitted submissions of the exam, when the teacher edits the
  exam structure or the model answers).

  Each job currently delegates to `Tasky.Correction.StringComparator` for
  deterministic, AI-free comparison. The original AI-backed client
  (`Tasky.AI.CorrectionClient`) is preserved for future reuse.
  """

  require Logger

  alias Tasky.Exams
  alias Tasky.Exams.ExamSubmission
  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.StringComparator
  alias Tasky.Repo

  @doc """
  Starts the bulk-correction coordinator under `Tasky.TaskSupervisor`.

  Options:
    * `:submission_id` — restrict the run to a single submission.

  Returns `{:ok, pid}` with the coordinator Task's pid.
  """
  def start_for_exam(exam, opts \\ []) do
    Task.Supervisor.start_child(
      Tasky.TaskSupervisor,
      fn -> run(exam, opts) end,
      restart: :temporary
    )
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
         {:ok, %{verdicts: verdicts, points: points}} <-
           StringComparator.correct_part(
             annotated_nodes,
             sample_nodes,
             max_points,
             %{ignore_spelling: ignore_spelling, ignore_case: ignore_case}
           ),
         corrected_nodes = NodePatcher.apply_verdicts(annotated_nodes, verdicts),
         clamped = clamp_points(points, max_points),
         {:ok, updated_submission} <-
           Exams.update_corrected_part_content(submission, part_id, corrected_nodes),
         {:ok, updated_submission} <-
           Exams.set_part_points(updated_submission, part_id, clamped),
         {:ok, _} <- Exams.mark_part_auto_corrected(updated_submission, part_id) do
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

  defp ensure_has_answers(0), do: {:error, "Aufgabe enthält keine Antwortfelder"}
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
end
