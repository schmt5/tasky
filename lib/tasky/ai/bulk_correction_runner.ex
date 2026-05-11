defmodule Tasky.AI.BulkCorrectionRunner do
  @moduledoc """
  Runs AI auto-correction for every eligible (submission, part) pair of an
  exam, sequentially, under `Tasky.TaskSupervisor`. Broadcasts progress to
  the `exam_correction:<exam_id>` PubSub topic so the LiveView can react.

  The coordinator runs as a Task. It accepts a cooperative `:cancel` message
  between jobs. In-flight Anthropic calls are not interrupted; cancel takes
  effect once the current job finishes (or times out via Req).
  """

  require Logger

  alias Tasky.Exams
  alias Tasky.Exams.ExamSubmission
  alias Tasky.AI.CorrectionClient
  alias Tasky.Repo

  @doc """
  Starts the bulk-correction coordinator under `Tasky.TaskSupervisor`.
  Returns `{:ok, pid}` with the coordinator Task's pid (used for cancel).
  """
  def start(exam, scope) do
    Task.Supervisor.start_child(
      Tasky.TaskSupervisor,
      fn -> run(exam, scope) end,
      restart: :temporary
    )
  end

  @doc """
  Sends a cooperative cancel signal to a running coordinator pid.
  Takes effect between jobs; the current job (if any) finishes first.
  """
  def cancel(pid) when is_pid(pid) do
    if Process.alive?(pid), do: send(pid, :cancel), else: :noop
    :ok
  end

  defp run(exam, _scope) do
    jobs = Exams.list_bulk_correction_jobs(exam)
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
      Enum.reduce_while(jobs, %{done: 0, errors: [], total: total}, fn job, acc ->
        receive do
          :cancel ->
            {:halt, Map.put(acc, :cancelled, true)}
        after
          0 ->
            errors =
              case run_job(exam, job) do
                :ok -> acc.errors
                {:error, reason} -> [{job, reason} | acc.errors]
              end

            done = acc.done + 1
            new_acc = %{acc | done: done, errors: errors}

            Exams.broadcast_bulk_correction(
              exam.id,
              {:bulk_correction_progress,
               %{done: done, total: total, errors: length(errors)}}
            )

            {:cont, new_acc}
        end
      end)

    if Map.get(final, :cancelled, false) do
      Exams.broadcast_bulk_correction(
        exam.id,
        {:bulk_correction_cancelled,
         %{done: final.done, total: total, errors: Enum.reverse(final.errors)}}
      )
    else
      Exams.broadcast_bulk_correction(
        exam.id,
        {:bulk_correction_done, %{total: total, errors: Enum.reverse(final.errors)}}
      )
    end
  end

  defp run_job(exam, %{submission_id: submission_id, part_id: part_id, ignore_spelling: ignore_spelling}) do
    with {:ok, submission} <- fetch_submission(exam.id, submission_id),
         {:ok, submission_nodes} <- fetch_part_nodes(submission, part_id),
         sample_nodes = sample_solution_part_nodes(exam, part_id),
         max_points = Map.get(exam.sample_solution_points || %{}, part_id),
         {:ok, %{corrected_nodes: nodes, points: points}} <-
           CorrectionClient.correct_part(
             submission_nodes,
             sample_nodes,
             max_points,
             %{ignore_spelling: ignore_spelling}
           ),
         clamped = clamp_points(points, max_points),
         {:ok, updated_submission} <-
           Exams.update_corrected_part_content(submission, part_id, nodes),
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
    exam.sample_solution
    |> Kernel.||(%{})
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
