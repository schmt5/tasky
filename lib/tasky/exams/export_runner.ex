defmodule Tasky.Exams.ExportRunner do
  @moduledoc """
  Spawns a supervised Task that:

    1. Renders each submission to PDF (`web.render_pdf`, Typst in-process)
    2. Packages the PDFs into a ZIP on disk
    3. Notifies the originating LiveView (`owner_pid`) of progress and completion

  The owner LiveView receives plain messages — no PubSub topic involved:

    * `{:export_progress, %{done: n, total: t}}`
    * `{:export_done, %{download_token: t, filename: f, failed: n}}`
    * `{:export_failed, reason}`

  A partially failed run still delivers the ZIP: failed renders are listed
  in a `FEHLER.txt` manifest inside the archive instead of discarding the
  successful PDFs. ZIPs are written under `export_dir/0` and cleaned up by
  `Tasky.Exams.ExportJanitor` (files older than its TTL), which also
  survives restarts — no sleeping cleanup tasks.
  """

  # Typst runs on a dirty CPU scheduler and needs some memory per render; two
  # at a time keeps a small (1 GB, shared-CPU) machine responsive.
  @max_concurrency 2
  # One student's PDF is a few hundred milliseconds; a render still running
  # after this is stuck, and it lands in FEHLER.txt instead of blocking the ZIP.
  @render_timeout 60_000

  @doc "Directory the export ZIPs are written to (scanned by the janitor)."
  def export_dir, do: Path.join(System.tmp_dir!(), "tasky_exports")

  @doc """
  Resolves an export id (as signed into the download token) to its ZIP path,
  rejecting anything that isn't a plain id.
  """
  def export_path(export_id) when is_binary(export_id) do
    if export_id =~ ~r/^[A-Za-z0-9_-]+$/ do
      {:ok, Path.join(export_dir(), export_id <> ".zip")}
    else
      {:error, :invalid_id}
    end
  end

  @doc """
  Starts the export Task. Returns `{:ok, pid}` or `{:error, reason}`.

  `web` injects the web-layer concerns (this module stays free of routing
  and token signing):

    * `web.render_pdf.(submission)` — `{:ok, pdf}` or `{:error, reason}`
    * `web.sign_download.(export_id, filename)` — the signed download token
  """
  def start(_exam, [], _owner_pid, _web), do: {:error, :no_submissions}

  def start(exam, submissions, owner_pid, web) when is_map(web) do
    task =
      Task.Supervisor.async_nolink(Tasky.TaskSupervisor, fn ->
        run(exam, submissions, owner_pid, web)
      end)

    {:ok, task.pid}
  end

  defp run(exam, submissions, owner_pid, web) do
    total = length(submissions)
    counter = :counters.new(1, [:atomics])
    notify(owner_pid, {:export_progress, %{done: 0, total: total}})

    results =
      submissions
      |> Task.async_stream(
        fn submission ->
          result = render(web.render_pdf, submission)
          :counters.add(counter, 1, 1)

          notify(
            owner_pid,
            {:export_progress, %{done: :counters.get(counter, 1), total: total}}
          )

          {submission, result}
        end,
        max_concurrency: @max_concurrency,
        timeout: @render_timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    case partition_results(Enum.zip(submissions, results)) do
      {:ok, pdfs, failures} ->
        case build_zip(exam, pdfs, failures) do
          {:ok, export_id, filename} ->
            token = web.sign_download.(export_id, filename)

            notify(
              owner_pid,
              {:export_done,
               %{download_token: token, filename: filename, failed: length(failures)}}
            )

          {:error, reason} ->
            notify(owner_pid, {:export_failed, {:zip_error, reason}})
        end

      {:error, reason} ->
        notify(owner_pid, {:export_failed, reason})
    end
  end

  # The stream's tasks are linked to this one, so a render that raises (a
  # submission deleted mid-export, a NIF error) would take the whole export
  # down with it. Caught here, it is one more line in FEHLER.txt.
  defp render(render_pdf, submission) do
    render_pdf.(submission)
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  # One failed render must not throw away the other N-1 good PDFs: split
  # into successes and failures; only a run with zero PDFs fails outright.
  #
  # Takes `{submission, result}` pairs rather than bare results: `Task.async_stream`
  # yields in input order but a crashed or timed-out task yields `{:exit, reason}`
  # with no payload, so the submission has to be carried in from the outside.
  # Without it the manifest said "Unbekannte Abgabe" — and the whole point of the
  # manifest is telling the teacher which student to re-export.
  defp partition_results(pairs) do
    {oks, errors} =
      Enum.split_with(pairs, fn
        {_submission, {:ok, {_sub, {:ok, _pdf}}}} -> true
        _ -> false
      end)

    pdfs = Enum.map(oks, fn {_submission, {:ok, {sub, {:ok, pdf}}}} -> {sub, pdf} end)

    failures =
      Enum.map(errors, fn
        {_submission, {:ok, {sub, {:error, reason}}}} -> {sub, {:render_error, reason}}
        {submission, {:exit, reason}} -> {submission, {:render_crashed, reason}}
        {submission, other} -> {submission, {:unknown_error, other}}
      end)

    case pdfs do
      [] when failures != [] -> {:error, elem(List.first(failures), 1)}
      _ -> {:ok, pdfs, failures}
    end
  end

  defp build_zip(exam, pdfs, failures) do
    dir = export_dir()
    File.mkdir_p!(dir)

    export_id = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    zip_filename = "#{sanitize(exam.name)}-Export.zip"
    zip_path = Path.join(dir, "#{export_id}.zip")

    entries =
      Enum.map(pdfs, fn {sub, pdf_binary} ->
        name = "#{sanitize(sub.firstname)}-#{sanitize(sub.lastname)}-#{sanitize(exam.name)}.pdf"
        {String.to_charlist(name), pdf_binary}
      end) ++ failure_manifest(failures)

    case :zip.create(String.to_charlist(zip_path), entries) do
      {:ok, _path_charlist} -> {:ok, export_id, zip_filename}
      {:error, reason} -> {:error, reason}
    end
  end

  defp failure_manifest([]), do: []

  defp failure_manifest(failures) do
    lines =
      Enum.map(failures, fn
        {%{firstname: f, lastname: l}, {kind, _reason}} ->
          "#{f} #{l}: PDF konnte nicht erstellt werden (#{kind})"

        {nil, {kind, _reason}} ->
          "Unbekannte Abgabe: PDF konnte nicht erstellt werden (#{kind})"
      end)

    body = """
    Die folgenden Abgaben fehlen in diesem Export:

    #{Enum.join(lines, "\n")}

    Bitte den Export für die betroffenen Abgaben erneut starten.
    """

    [{~c"FEHLER.txt", body}]
  end

  defp notify(pid, message) when is_pid(pid) do
    send(pid, message)
  end

  defp notify(_, _), do: :ok

  @doc """
  Turns a name into a filename component: umlauts transliterated, everything
  outside `[A-Za-z0-9._-]` collapsed to a dash.

  Public because the paper-version download needs the same rule, and this is
  the one place it lives.
  """
  def sanitize_filename(s), do: sanitize(s)

  # Replace umlauts and non-ASCII with ASCII-safe equivalents, then sub spaces
  # and other non-filename characters for hyphens.
  defp sanitize(s) when is_binary(s) do
    s
    |> String.replace(["ä", "Ä"], "ae")
    |> String.replace(["ö", "Ö"], "oe")
    |> String.replace(["ü", "Ü"], "ue")
    |> String.replace(["ß"], "ss")
    |> String.replace(~r/[^A-Za-z0-9._-]+/u, "-")
    |> String.trim("-")
  end

  defp sanitize(_), do: "datei"
end
