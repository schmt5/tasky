defmodule Tasky.Courses.DuplicateRunner do
  @moduledoc """
  Duplicates a course in two phases: the records synchronously in the caller
  (one short transaction), then the file bytes in a supervised Task.

  The split is the point. Object-storage copies must not run inside the
  transaction — see `Tasky.Courses.duplicate_course/3` — and they take long
  enough on a file-heavy course that a LiveView should not sit on them
  either. Doing the records inline keeps authorization and changeset errors
  surfacing as an ordinary `{:error, reason}`, exactly as before.

  The owner LiveView receives plain messages — no PubSub topic involved:

    * `{:duplicate_progress, %{done: n, total: t}}`
    * `{:duplicate_done, %{course_id: id, failed: n}}`

  The Task is unlinked from the caller, so a LiveView that navigates away or
  disconnects neither kills the copy phase nor is killed by it. There is no
  retry across an app restart: the recovery is to delete the incomplete copy
  and duplicate again.
  """

  alias Tasky.Courses
  alias Tasky.Uploads

  @doc """
  Writes the duplicate's records and starts the copy phase.

  Returns `{:ok, course, total_files}` once the records are committed.
  `total_files` is 0 when there is nothing to copy — the caller can then skip
  any progress UI and treat the duplication as finished.
  """
  def start(scope, course, name, owner_pid) do
    with {:ok, new_course, jobs} <- Courses.duplicate_course_records(scope, course, name) do
      jobs = Enum.uniq_by(jobs, & &1.dest)
      total = length(jobs)

      if total > 0, do: start_copy_phase(jobs, new_course.id, owner_pid)

      {:ok, new_course, total}
    end
  end

  # `start_child` rather than `async_nolink`: nobody awaits the result, so the
  # owner should not have to swallow a stray reply and `:DOWN` afterwards.
  defp start_copy_phase(jobs, course_id, owner_pid) do
    Task.Supervisor.start_child(Tasky.TaskSupervisor, fn ->
      %{failed: failed} = Uploads.run_copies(jobs, on_progress: progress_fun(owner_pid))
      send(owner_pid, {:duplicate_done, %{course_id: course_id, failed: length(failed)}})
    end)
  end

  defp progress_fun(owner_pid) do
    fn done, total -> send(owner_pid, {:duplicate_progress, %{done: done, total: total}}) end
  end
end
