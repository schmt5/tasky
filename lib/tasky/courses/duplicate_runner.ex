defmodule Tasky.Courses.DuplicateRunner do
  @moduledoc """
  Duplicates a course — or copies a single learning unit into existing courses —
  in two phases: the records synchronously in the caller (one short
  transaction), then the file bytes in a supervised Task.

  The split is the point. Object-storage copies must not run inside the
  transaction — see `Tasky.Courses.duplicate_course/3` — and they take long
  enough on a file-heavy course that a LiveView should not sit on them
  either. Doing the records inline keeps authorization and changeset errors
  surfacing as an ordinary `{:error, reason}`, exactly as before.

  The owner LiveView receives plain messages — no PubSub topic involved.
  Duplicating a course (`start/4`, `start_catalog_import/4`) reports:

    * `{:duplicate_progress, %{done: n, total: t}}`
    * `{:duplicate_done, %{course_id: id, failed: n}}`

  Copying a unit (`start_task_copy/4`) reports its own pair, because the caller
  reacts differently — it stays on the course it is already showing instead of
  navigating to the duplicate:

    * `{:copy_progress, %{done: n, total: t}}`
    * `{:copy_done, %{failed: n}}`

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
    run(fn -> Courses.duplicate_course_records(scope, course, name) end, owner_pid, :duplicate)
  end

  @doc """
  Wie `start/4`, aber für den Kurs-Katalog: übernimmt einen von einer *anderen*
  Lehrperson veröffentlichten Kurs.

  Nimmt eine `source_id` statt eines `%Course{}`, weil die Vorschauseite lange
  offen stehen kann — die Veröffentlichung wird beim Import frisch geprüft
  (`Tasky.Courses.import_catalog_course_records/3`). Dieselben Nachrichten an
  `owner_pid`, dieselbe `{:ok, course, total_files}`-Rückgabe.
  """
  def start_catalog_import(scope, source_id, name, owner_pid) do
    run(
      fn -> Courses.import_catalog_course_records(scope, source_id, name) end,
      owner_pid,
      :duplicate
    )
  end

  @doc """
  Kopiert eine Lerneinheit in bestehende Kurse
  (`Tasky.Courses.copy_task_into_courses/3`) und startet die Kopierphase.

  Returns `{:ok, tasks, total_files}`, sobald die Datensätze committed sind —
  `tasks` in der Reihenfolge der übergebenen `course_ids`. `total_files` ist 0,
  wenn die Einheit keine Dateien hat; der Aufrufer kann dann auf jede
  Fortschrittsanzeige verzichten.
  """
  def start_task_copy(scope, source_task, course_ids, owner_pid) do
    run(
      fn -> Courses.copy_task_into_courses(scope, source_task, course_ids) end,
      owner_pid,
      :copy
    )
  end

  defp run(write_records, owner_pid, kind) do
    with {:ok, records, jobs} <- write_records.() do
      jobs = Enum.uniq_by(jobs, & &1.dest)
      total = length(jobs)

      if total > 0, do: start_copy_phase(jobs, records, owner_pid, kind)

      {:ok, records, total}
    end
  end

  # `start_child` rather than `async_nolink`: nobody awaits the result, so the
  # owner should not have to swallow a stray reply and `:DOWN` afterwards.
  defp start_copy_phase(jobs, records, owner_pid, kind) do
    Task.Supervisor.start_child(Tasky.TaskSupervisor, fn ->
      %{failed: failed} =
        Uploads.run_copies(jobs, on_progress: progress_fun(owner_pid, kind))

      send(owner_pid, done_message(kind, records, length(failed)))
    end)
  end

  defp progress_fun(owner_pid, kind) do
    tag = progress_tag(kind)
    fn done, total -> send(owner_pid, {tag, %{done: done, total: total}}) end
  end

  defp progress_tag(:duplicate), do: :duplicate_progress
  defp progress_tag(:copy), do: :copy_progress

  # Der Kurs-Pfad nennt den Zielkurs, weil die aufrufende LiveView dorthin
  # navigiert; beim Kopieren einer Einheit gibt es kein einzelnes Ziel — und
  # die LiveView bleibt ohnehin, wo sie ist.
  defp done_message(:duplicate, course, failed),
    do: {:duplicate_done, %{course_id: course.id, failed: failed}}

  defp done_message(:copy, _tasks, failed), do: {:copy_done, %{failed: failed}}
end
