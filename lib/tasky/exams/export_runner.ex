defmodule Tasky.Exams.ExportRunner do
  @moduledoc """
  Spawns a supervised Task that:

    1. Asks Gotenberg to render the print-view of each submission to PDF
    2. Packages the PDFs into a ZIP on disk
    3. Notifies the originating LiveView (`owner_pid`) of progress and completion

  The owner LiveView receives plain messages — no PubSub topic involved:

    * `{:export_progress, %{done: n, total: t}}`
    * `{:export_done, %{download_token: t, filename: f}}`
    * `{:export_failed, reason}`

  ZIPs are written under the system temp directory and cleaned up by the
  download controller after they are served (with a 10-minute fallback
  cleanup scheduled here).
  """

  alias Tasky.PDF.Gotenberg
  alias Tasky.Exams.PrintToken

  @max_concurrency 4
  @gotenberg_timeout 120_000
  # Best-effort fallback cleanup if the file is never downloaded.
  @cleanup_after_ms 10 * 60 * 1000

  @doc """
  Starts the export Task. Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def start(exam, submissions, opts, owner_pid, teacher_user_id, endpoint) do
    cond do
      not Gotenberg.enabled?() ->
        {:error, :gotenberg_not_configured}

      is_nil(callback_base_url()) ->
        {:error, :callback_url_not_configured}

      submissions == [] ->
        {:error, :no_submissions}

      true ->
        task =
          Task.Supervisor.async_nolink(Tasky.TaskSupervisor, fn ->
            run(exam, submissions, opts, owner_pid, teacher_user_id, endpoint)
          end)

        {:ok, task.pid}
    end
  end

  defp run(exam, submissions, opts, owner_pid, teacher_user_id, endpoint) do
    total = length(submissions)
    counter = :counters.new(1, [:atomics])
    notify(owner_pid, {:export_progress, %{done: 0, total: total}})

    results =
      submissions
      |> Task.async_stream(
        fn submission ->
          result = render_one(exam, submission, opts, teacher_user_id, endpoint)
          :counters.add(counter, 1, 1)

          notify(
            owner_pid,
            {:export_progress, %{done: :counters.get(counter, 1), total: total}}
          )

          {submission, result}
        end,
        max_concurrency: @max_concurrency,
        timeout: @gotenberg_timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    case partition_results(results) do
      {:ok, pdfs} ->
        case build_zip(exam, pdfs) do
          {:ok, path, filename} ->
            schedule_cleanup(path)
            token = Tasky.Exams.ExportDownloadToken.sign(endpoint, path, filename)
            notify(owner_pid, {:export_done, %{download_token: token, filename: filename}})

          {:error, reason} ->
            notify(owner_pid, {:export_failed, {:zip_error, reason}})
        end

      {:error, reason} ->
        notify(owner_pid, {:export_failed, reason})
    end
  end

  defp render_one(exam, submission, opts, teacher_user_id, endpoint) do
    token =
      PrintToken.sign(
        endpoint,
        teacher_user_id,
        to_string(exam.id),
        to_string(submission.id),
        Map.take(opts, [:show_content, :show_correction, :show_sample_solution])
      )

    url =
      "#{callback_base_url()}/print/exam-submission/#{exam.id}/#{submission.id}?token=#{URI.encode(token)}"

    Gotenberg.url_to_pdf(url)
  end

  defp partition_results(results) do
    {oks, errors} =
      Enum.split_with(results, fn
        {:ok, {_sub, {:ok, _pdf}}} -> true
        _ -> false
      end)

    case errors do
      [] ->
        pdfs = Enum.map(oks, fn {:ok, {sub, {:ok, pdf}}} -> {sub, pdf} end)
        {:ok, pdfs}

      _ ->
        # Return the first error so the LV can show a useful message.
        first =
          case List.first(errors) do
            {:ok, {_sub, {:error, reason}}} -> {:render_error, reason}
            {:exit, reason} -> {:render_crashed, reason}
            other -> {:unknown_error, other}
          end

        {:error, first}
    end
  end

  defp build_zip(exam, pdfs) do
    dir = Path.join(System.tmp_dir!(), "tasky_exports")
    File.mkdir_p!(dir)

    uuid = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    zip_filename = "#{sanitize(exam.name)}-Export.zip"
    zip_path = Path.join(dir, "#{uuid}.zip")

    entries =
      Enum.map(pdfs, fn {sub, pdf_binary} ->
        name = "#{sanitize(sub.firstname)}-#{sanitize(sub.lastname)}-#{sanitize(exam.name)}.pdf"
        {String.to_charlist(name), pdf_binary}
      end)

    case :zip.create(String.to_charlist(zip_path), entries) do
      {:ok, _path_charlist} -> {:ok, zip_path, zip_filename}
      {:error, reason} -> {:error, reason}
    end
  end

  # Best-effort delete; the download controller deletes immediately on serve.
  defp schedule_cleanup(path) do
    Task.Supervisor.start_child(Tasky.TaskSupervisor, fn ->
      :timer.sleep(@cleanup_after_ms)
      _ = File.rm(path)
    end)
  end

  defp notify(pid, message) when is_pid(pid) do
    send(pid, message)
  end

  defp notify(_, _), do: :ok

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

  defp callback_base_url, do: Application.get_env(:tasky, :gotenberg_callback_url)
end
