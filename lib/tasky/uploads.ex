defmodule Tasky.Uploads do
  @moduledoc """
  Stores and locates user-uploaded files: exam content images, teacher
  attachments (Anhänge) and student answer files (Datei-Abgaben).

  Files live under the configured `:uploads_dir` (see `config/runtime.exs`) and
  are served back via `TaskyWeb.UploadController` at `/uploads/...`. The stored
  filename and extension are derived server-side from the validated file type,
  never from the client-supplied name.
  """

  require Logger

  @max_bytes 10 * 1024 * 1024
  @max_file_bytes 25 * 1024 * 1024

  # Allowed image content types mapped to the extension we store them under.
  @allowed_image_types %{
    "image/png" => ".png",
    "image/jpeg" => ".jpg",
    "image/gif" => ".gif",
    "image/webp" => ".webp"
  }

  # File-type registry for attachments and answer uploads. Keys are stored in
  # `exam_upload_fields.allowed_types`; extensions drive both the client-side
  # `accept:` filter and the server-side validation. The first extension of a
  # type is the canonical one a file gets stored under.
  @file_types [
    {"pdf", %{label: "PDF", badge: "PDF", exts: ~w(.pdf)}},
    {"docx", %{label: "Word", badge: "DOCX", exts: ~w(.docx)}},
    {"xlsx", %{label: "Excel", badge: "XLSX", exts: ~w(.xlsx)}},
    {"pptx", %{label: "PowerPoint", badge: "PPTX", exts: ~w(.pptx)}},
    {"image", %{label: "Bild", badge: "IMG", exts: ~w(.jpg .jpeg .png)}},
    {"audio", %{label: "Audio", badge: "MP3", exts: ~w(.mp3 .m4a)}},
    {"zip", %{label: "ZIP", badge: "ZIP", exts: ~w(.zip)}}
  ]

  # Canonical content type per allowed extension.
  @ext_content_types %{
    ".pdf" => "application/pdf",
    ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png" => "image/png",
    ".gif" => "image/gif",
    ".webp" => "image/webp",
    ".mp3" => "audio/mpeg",
    ".m4a" => "audio/mp4",
    ".zip" => "application/zip"
  }

  # Teacher attachments additionally allow animated/other web image formats.
  @attachment_extra_exts ~w(.gif .webp)

  @doc "Absolute base directory for uploads."
  def dir, do: Application.fetch_env!(:tasky, :uploads_dir)

  @doc """
  Saves an uploaded image for the given exam and returns `{:ok, url}` with the
  public `/uploads/...` path, or `{:error, reason}`.
  """
  def save_exam_image(exam_id, %Plug.Upload{} = upload) do
    with {:ok, ext} <- allowed_extension(upload.content_type),
         :ok <- validate_size(upload.path),
         :ok <- validate_image_signature(upload.path, ext),
         filename = Ecto.UUID.generate() <> ext,
         :ok <-
           store_bytes(storage_key(["exams", to_string(exam_id)], filename), upload.path,
             content_type: content_type_for_ext(ext),
             disposition: "inline"
           ) do
      {:ok, "/uploads/exams/#{exam_id}/#{filename}"}
    end
  end

  @doc """
  Resolves a stored image to `{:ok, {absolute_path, content_type}}` for serving,
  guarding against path traversal and unknown extensions.
  """
  def fetch_exam_image(exam_id, filename) do
    ext = filename |> Path.extname() |> String.downcase()

    with {:ok, content_type} <- extension_content_type(ext),
         {:ok, source} <- fetch_stored(["exams", to_string(exam_id)], filename) do
      {:ok, {source, content_type}}
    end
  end

  @doc """
  Saves an uploaded content image for the given learning unit (task) and
  returns `{:ok, url}` with the public `/uploads/...` path, or `{:error, reason}`.
  """
  def save_task_image(task_id, %Plug.Upload{} = upload) do
    with {:ok, ext} <- allowed_extension(upload.content_type),
         :ok <- validate_size(upload.path),
         :ok <- validate_image_signature(upload.path, ext),
         filename = Ecto.UUID.generate() <> ext,
         :ok <-
           store_bytes(storage_key(["tasks", to_string(task_id)], filename), upload.path,
             content_type: content_type_for_ext(ext),
             disposition: "inline"
           ) do
      {:ok, "/uploads/tasks/#{task_id}/#{filename}"}
    end
  end

  @doc """
  Resolves a stored task image to `{:ok, {absolute_path, content_type}}` for
  serving, guarding against path traversal and unknown extensions.
  """
  def fetch_task_image(task_id, filename) do
    ext = filename |> Path.extname() |> String.downcase()

    with {:ok, content_type} <- extension_content_type(ext),
         {:ok, source} <- fetch_stored(["tasks", to_string(task_id)], filename) do
      {:ok, {source, content_type}}
    end
  end

  ## File-type registry (attachments + answer uploads)

  @doc "Ordered type keys selectable for student answer upload fields."
  def answer_type_keys, do: Enum.map(@file_types, fn {key, _} -> key end)

  @doc "Registry entry (`%{label:, badge:, exts:}`) for a type key, or nil."
  def file_type(key) do
    case List.keyfind(@file_types, key, 0) do
      {_key, entry} -> entry
      nil -> nil
    end
  end

  @doc "Max size in bytes for attachments and answer files."
  def max_file_bytes, do: @max_file_bytes

  @doc "Accepted extensions for the given type keys (for `allow_upload` accept)."
  def accept_exts(type_keys) do
    type_keys
    |> Enum.flat_map(fn key ->
      case file_type(key) do
        %{exts: exts} -> exts
        nil -> []
      end
    end)
    |> Enum.uniq()
  end

  @doc "Accepted extensions for teacher attachments (all types + gif/webp)."
  def attachment_accept_exts, do: accept_exts(answer_type_keys()) ++ @attachment_extra_exts

  ## Teacher attachments

  @doc """
  Stores a teacher attachment for an exam. Validates the extension of the
  client-supplied `original_name` against the attachment whitelist, copies the
  file under a UUID name and returns `{:ok, meta}` with `:stored_filename`,
  `:content_type` and `:size`.
  """
  def save_exam_attachment(exam_id, src_path, original_name) do
    save_file(src_path, original_name, attachment_accept_exts(), [
      "exams",
      to_string(exam_id),
      "attachments"
    ])
  end

  @doc "Serveable source of a stored attachment, or an error tuple."
  def fetch_attachment(exam_id, stored_filename, opts \\ []),
    do: fetch_stored(["exams", to_string(exam_id), "attachments"], stored_filename, opts)

  @doc "Removes a stored attachment (idempotent)."
  def delete_exam_attachment_file(exam_id, stored_filename),
    do: delete_stored(["exams", to_string(exam_id), "attachments"], stored_filename)

  @doc """
  Stores a teacher attachment for a learning unit (task). Same validation as
  `save_exam_attachment/3`.
  """
  def save_task_attachment(task_id, src_path, original_name) do
    save_file(src_path, original_name, attachment_accept_exts(), [
      "tasks",
      to_string(task_id),
      "attachments"
    ])
  end

  @doc "Serveable source of a stored task attachment, or an error tuple."
  def fetch_task_attachment(task_id, stored_filename, opts \\ []),
    do: fetch_stored(["tasks", to_string(task_id), "attachments"], stored_filename, opts)

  @doc "Removes a stored task attachment (idempotent)."
  def delete_task_attachment_file(task_id, stored_filename),
    do: delete_stored(["tasks", to_string(task_id), "attachments"], stored_filename)

  ## Musterlösungs-Dateien
  #
  # Liegen unter `tasks/<id>/solution/`, also innerhalb von `tasks/<id>` —
  # damit räumt `delete_task_files/1` sie beim Löschen der Lerneinheit mit auf.
  # Ausgeliefert werden sie nie über die öffentlichen `/uploads/...`-Routen,
  # sondern nur durch die beiden Download-Controller.

  @doc """
  Stores a solution file for a learning unit. Same whitelist and size limit as
  teacher attachments — a correctly formatted Word document is the `docx` case
  the registry already covers.
  """
  def save_task_solution_file(task_id, src_path, original_name) do
    save_file(src_path, original_name, attachment_accept_exts(), [
      "tasks",
      to_string(task_id),
      "solution"
    ])
  end

  @doc "Serveable source of a stored solution file, or an error tuple."
  def fetch_task_solution_file(task_id, stored_filename, opts \\ []),
    do: fetch_stored(["tasks", to_string(task_id), "solution"], stored_filename, opts)

  @doc "Removes a stored solution file (idempotent)."
  def delete_task_solution_file(task_id, stored_filename),
    do: delete_stored(["tasks", to_string(task_id), "solution"], stored_filename)

  ## Copying between learning units (duplication)

  # Eight copies in flight: R2 `CopyObject` is server-side, so the only cost
  # per job is one signed round trip and the concurrency is bounded by the
  # HTTP pool rather than by bandwidth.
  @copy_concurrency 8

  # Per-job ceiling, comfortably above the adapter's own worst case (three
  # attempts at `receive_timeout` plus backoff, see `Tasky.Storage.R2`).
  @copy_timeout 45_000

  @typedoc """
  A file copy a duplication still owes storage: two storage keys, no I/O.
  Planned inside the DB transaction, performed by `run_copies/2` after it
  commits — see `Tasky.Courses.duplicate_course/3` for why the two must not
  be interleaved.
  """
  @type copy_job :: %{src: String.t(), dest: String.t()}

  @typedoc """
  What a set of uploads belongs to. Both kinds own their files under
  `<kind>/<id>/…`, so duplication works the same way on either side.
  """
  @type owner_kind :: :exams | :tasks

  @doc """
  Rewrites every content-image reference in a Tiptap doc from one owner's
  upload prefix to the other's and plans the byte copies. Returns
  `{rewritten_doc, copy_jobs}`.

  Content images live under their own owner's prefix, so a copy has to take its
  own bytes along and point at them — sharing the source's files would blank
  the duplicate out as soon as the original is deleted (`delete_exam_files/1` /
  `delete_task_files/1` wipe the whole `<kind>/<id>` prefix). The new URL is
  deterministic, so it is written now and the bytes follow after the commit.

  A reference that is not a plain filename directly under the prefix is left
  alone, so nothing outside the owner's content images is ever touched.
  """
  @spec plan_content_image_copies(term(), owner_kind(), term(), term()) ::
          {term(), [copy_job()]}
  def plan_content_image_copies(content, kind, from_id, to_id) when kind in [:exams, :tasks] do
    segment = Atom.to_string(kind)

    ctx = %{
      segment: segment,
      from_id: from_id,
      to_id: to_id,
      prefix: "/uploads/#{segment}/#{from_id}/",
      new_prefix: "/uploads/#{segment}/#{to_id}/"
    }

    rewrite_image_refs(content, ctx, [])
  end

  defp rewrite_image_refs(value, ctx, jobs) when is_map(value) do
    Enum.reduce(value, {%{}, jobs}, fn {k, v}, {acc, jobs} ->
      {v, jobs} = rewrite_image_refs(v, ctx, jobs)
      {Map.put(acc, k, v), jobs}
    end)
  end

  defp rewrite_image_refs(value, ctx, jobs) when is_list(value) do
    {list, jobs} =
      Enum.reduce(value, {[], jobs}, fn v, {acc, jobs} ->
        {v, jobs} = rewrite_image_refs(v, ctx, jobs)
        {[v | acc], jobs}
      end)

    {Enum.reverse(list), jobs}
  end

  defp rewrite_image_refs(value, ctx, jobs) when is_binary(value) do
    # Only direct children of the owner's prefix are content images; anything
    # deeper (an attachment path, say) is not ours to rewrite. This guard is the
    # only thing deciding what counts as a content image, since the storage copy
    # no longer votes.
    with true <- String.starts_with?(value, ctx.prefix),
         filename = String.replace_prefix(value, ctx.prefix, ""),
         false <- String.contains?(filename, "/"),
         {:ok, job} <-
           plan_copy(
             {[ctx.segment, to_string(ctx.from_id)], filename},
             {[ctx.segment, to_string(ctx.to_id)], filename}
           ) do
      {ctx.new_prefix <> filename, [job | jobs]}
    else
      _ -> {value, jobs}
    end
  end

  defp rewrite_image_refs(value, _ctx, jobs), do: {value, jobs}

  @doc """
  Plans the copy of a teacher attachment between two owners of the same kind.
  The fresh stored filename is minted here rather than after the copy, so the
  new attachment row can be written before the bytes exist — the column is
  globally unique, not unique per owner, so reusing the source's name would hit
  the constraint.

  Returns `{:ok, new_stored_filename, copy_job}` or `{:error, :invalid}`.
  """
  @spec plan_attachment_copy(owner_kind(), term(), term(), String.t()) ::
          {:ok, String.t(), copy_job()} | {:error, :invalid}
  def plan_attachment_copy(kind, from_id, to_id, stored_filename)
      when kind in [:exams, :tasks] do
    segment = Atom.to_string(kind)
    ext = stored_filename |> Path.extname() |> String.downcase()
    new_stored_filename = Ecto.UUID.generate() <> ext

    with {:ok, job} <-
           plan_copy(
             {[segment, to_string(from_id), "attachments"], stored_filename},
             {[segment, to_string(to_id), "attachments"], new_stored_filename}
           ) do
      {:ok, new_stored_filename, job}
    end
  end

  @doc """
  Plans the copy of a solution file into another learning unit, minting a
  fresh `stored_filename` (the column is globally unique).

  Eigene Funktion statt eines Parameters an `plan_attachment_copy/4`, damit
  dessen bestehende Aufrufstellen unangetastet bleiben.

  Returns `{:ok, new_stored_filename, copy_job}` or `{:error, :invalid}`.
  """
  @spec plan_solution_file_copy(term(), term(), String.t()) ::
          {:ok, String.t(), copy_job()} | {:error, :invalid}
  def plan_solution_file_copy(from_id, to_id, stored_filename) do
    ext = stored_filename |> Path.extname() |> String.downcase()
    new_stored_filename = Ecto.UUID.generate() <> ext

    with {:ok, job} <-
           plan_copy(
             {["tasks", to_string(from_id), "solution"], stored_filename},
             {["tasks", to_string(to_id), "solution"], new_stored_filename}
           ) do
      {:ok, new_stored_filename, job}
    end
  end

  defp plan_copy({src_segments, src_filename}, {dest_segments, dest_filename}) do
    with :ok <- validate_segments(src_segments),
         :ok <- validate_segment(src_filename),
         :ok <- validate_segments(dest_segments),
         :ok <- validate_segment(dest_filename) do
      {:ok,
       %{
         src: storage_key(src_segments, src_filename),
         dest: storage_key(dest_segments, dest_filename)
       }}
    else
      _ -> {:error, :invalid}
    end
  end

  @doc """
  Performs one planned copy. Never call this from inside a
  `Repo.transaction/1` — it is a network round trip on every adapter but the
  local one.
  """
  @spec run_copy(copy_job()) :: :ok | {:error, term()}
  def run_copy(%{src: src, dest: dest}), do: Tasky.Storage.copy(src, dest)

  @doc """
  Runs planned copies in parallel, outside any transaction.

  Never fails as a whole: a job that errors out (or whose adapter raises) is
  logged and counted, so the caller can report a partial result instead of
  discarding a duplicate whose records are already committed.

  Options:

    * `:on_progress` — `fn done, total -> ... end`, called after each job
    * `:max_concurrency` — defaults to #{@copy_concurrency}
  """
  @spec run_copies([copy_job()], keyword()) :: %{copied: non_neg_integer(), failed: list()}
  def run_copies(jobs, opts \\ []) do
    on_progress = Keyword.get(opts, :on_progress, fn _done, _total -> :ok end)
    # The same image can be referenced twice in one Tiptap doc; the second
    # copy would be a wasted round trip onto an identical key.
    jobs = Enum.uniq_by(jobs, & &1.dest)
    total = length(jobs)
    counter = :counters.new(1, [:atomics])

    Tasky.TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      jobs,
      fn job ->
        result = run_copy(job)
        :counters.add(counter, 1, 1)
        on_progress.(:counters.get(counter, 1), total)
        {job, result}
      end,
      max_concurrency: Keyword.get(opts, :max_concurrency, @copy_concurrency),
      timeout: @copy_timeout,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.reduce(%{copied: 0, failed: []}, fn
      {:ok, {_job, :ok}}, acc -> %{acc | copied: acc.copied + 1}
      {:ok, {job, {:error, reason}}}, acc -> %{acc | failed: [{job, reason} | acc.failed]}
      # `_nolink` plus this clause is what keeps a raising adapter
      # (`File.mkdir_p!`, `Application.fetch_env!`) from taking the caller —
      # often a LiveView — down with it.
      {:exit, reason}, acc -> %{acc | failed: [{nil, reason} | acc.failed]}
    end)
    |> tap(fn %{failed: failed} ->
      Enum.each(failed, &Logger.warning("duplicate: copy failed #{inspect(&1)}"))
    end)
  end

  ## Student answer files

  @doc """
  Stores a student's answer file for one upload field. `allowed_type_keys`
  are the field's allowed registry keys.
  """
  def save_submission_file(exam_id, submission_id, src_path, original_name, allowed_type_keys) do
    save_file(src_path, original_name, accept_exts(allowed_type_keys), [
      "exams",
      to_string(exam_id),
      "submissions",
      to_string(submission_id)
    ])
  end

  @doc "Serveable source of a stored submission file, or an error tuple."
  def fetch_submission_file(exam_id, submission_id, stored_filename, opts \\ []) do
    fetch_stored(
      ["exams", to_string(exam_id), "submissions", to_string(submission_id)],
      stored_filename,
      opts
    )
  end

  @doc "Removes a stored submission file (idempotent)."
  def delete_submission_file_from_disk(exam_id, submission_id, stored_filename) do
    delete_stored(
      ["exams", to_string(exam_id), "submissions", to_string(submission_id)],
      stored_filename
    )
  end

  @doc """
  Stores a student's answer file for one upload field of a learning unit
  (task) submission. `allowed_type_keys` are the field's allowed registry keys.
  """
  def save_task_submission_file(
        task_id,
        submission_id,
        src_path,
        original_name,
        allowed_type_keys
      ) do
    save_file(src_path, original_name, accept_exts(allowed_type_keys), [
      "tasks",
      to_string(task_id),
      "submissions",
      to_string(submission_id)
    ])
  end

  @doc "Serveable source of a stored task submission file, or an error tuple."
  def fetch_task_submission_file(task_id, submission_id, stored_filename, opts \\ []) do
    fetch_stored(
      ["tasks", to_string(task_id), "submissions", to_string(submission_id)],
      stored_filename,
      opts
    )
  end

  @doc "Removes a stored task submission file (idempotent)."
  def delete_task_submission_file_from_disk(task_id, submission_id, stored_filename) do
    delete_stored(
      ["tasks", to_string(task_id), "submissions", to_string(submission_id)],
      stored_filename
    )
  end

  @doc """
  Removes every stored file of an exam (content images, attachments,
  submission files). Called when the exam is deleted so no bytes are
  orphaned.
  """
  def delete_exam_files(exam_id), do: delete_owner_files("exams", exam_id)

  @doc "Removes every stored file of a learning unit (task); see `delete_exam_files/1`."
  def delete_task_files(task_id), do: delete_owner_files("tasks", task_id)

  # Best-effort, always `:ok`: the deletion the caller asked for has already
  # happened in the database, and a storage hiccup must not fail it. An id that
  # is not a safe path segment is a caller bug rather than a missing file, so it
  # is logged instead of quietly doing nothing.
  defp delete_owner_files(segment, id) do
    case validate_segment(to_string(id)) do
      :ok ->
        Tasky.Storage.delete_prefix("#{segment}/#{id}")

      {:error, :invalid} ->
        Logger.warning("upload: refusing to clear #{segment} files for invalid id #{inspect(id)}")
    end

    :ok
  end

  @doc """
  Removes the stored files of several learning units at once, in parallel.

  Used when a whole course goes away: the DB cascade takes the task rows with
  it, so `Tasky.Tasks.delete_task/2` — the only other place that clears a
  unit's bytes — never gets a chance to run.

  Best-effort and never raises. Clearing a prefix is a list plus one delete
  per object on a remote adapter, so doing a course's units one after another
  would be slow enough to matter; and a storage hiccup must not fail a delete
  the user already asked for. Like every other storage call, this must not run
  inside a `Repo.transaction/1`.
  """
  @spec delete_task_files_many([term()]) :: :ok
  def delete_task_files_many(task_ids) do
    Tasky.TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      task_ids,
      &delete_task_files/1,
      max_concurrency: @copy_concurrency,
      timeout: @copy_timeout,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.each(fn
      {:ok, _} -> :ok
      {:exit, reason} -> Logger.warning("delete: task file cleanup failed #{inspect(reason)}")
    end)
  end

  @doc """
  Removes the stored answer files of several learning-unit submissions at once.

  Used when a learner's account is deleted: the DB cascade takes the
  `task_submissions` rows (and with them `task_submission_files`), so
  `Tasky.Tasks.delete_submission_file/2` — the only other place that clears a
  submission's bytes — never gets a chance to run. Takes `{task_id,
  submission_id}` pairs because the bytes live under the *task*, not under the
  learner.

  Best-effort and never raises, like `delete_task_files_many/1`, and must not
  run inside a `Repo.transaction/1`.
  """
  @spec delete_task_submission_dirs([{term(), term()}]) :: :ok
  def delete_task_submission_dirs(pairs) do
    Tasky.TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      pairs,
      fn {task_id, submission_id} -> delete_task_submission_dir(task_id, submission_id) end,
      max_concurrency: @copy_concurrency,
      timeout: @copy_timeout,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.each(fn
      {:ok, _} ->
        :ok

      {:exit, reason} ->
        Logger.warning("delete: submission file cleanup failed #{inspect(reason)}")
    end)
  end

  defp delete_task_submission_dir(task_id, submission_id) do
    segments = [to_string(task_id), to_string(submission_id)]

    case validate_segments(segments) do
      :ok ->
        Tasky.Storage.delete_prefix("tasks/#{task_id}/submissions/#{submission_id}")

      {:error, :invalid} ->
        Logger.warning(
          "upload: refusing to clear submission files for invalid ids " <>
            "#{inspect(task_id)}/#{inspect(submission_id)}"
        )
    end

    :ok
  end

  @doc "Canonical content type for an allowed extension, or nil."
  def content_type_for_ext(ext), do: Map.get(@ext_content_types, String.downcase(ext))

  @doc """
  Registry type key for an extension (".gif"/".webp" count as "image"), or nil.
  """
  def type_key_for_ext(ext) do
    ext = String.downcase(ext)

    if ext in @attachment_extra_exts do
      "image"
    else
      case Enum.find(@file_types, fn {_key, %{exts: exts}} -> ext in exts end) do
        {key, _} -> key
        nil -> nil
      end
    end
  end

  @doc """
  Human-readable size, e.g. "2,4 MB" / "88 KB".
  """
  def format_size(bytes) when is_integer(bytes) and bytes >= 1024 * 1024 do
    mb = bytes / (1024 * 1024)

    mb
    |> :erlang.float_to_binary(decimals: 1)
    |> String.replace(".", ",")
    |> String.replace_suffix(",0", "")
    |> Kernel.<>(" MB")
  end

  def format_size(bytes) when is_integer(bytes) and bytes >= 1024,
    do: "#{div(bytes, 1024)} KB"

  def format_size(bytes) when is_integer(bytes), do: "#{bytes} B"
  def format_size(_), do: "—"

  # Validates ext + size, then copies `src_path` under a UUID filename inside
  # `segments` (relative to the uploads dir).
  defp save_file(src_path, original_name, allowed_exts, segments) do
    ext = original_name |> Path.extname() |> String.downcase()

    with :ok <- validate_file_ext(ext, allowed_exts),
         {:ok, size} <- validate_file_size(src_path),
         stored_filename = Ecto.UUID.generate() <> ext,
         content_type = content_type_for_ext(ext) || "application/octet-stream",
         :ok <-
           store_bytes(storage_key(segments, stored_filename), src_path,
             content_type: content_type,
             disposition: {"attachment", original_name}
           ) do
      {:ok,
       %{
         stored_filename: stored_filename,
         content_type: content_type,
         size: size
       }}
    end
  end

  # A failed write must come back as an error tuple, not a raise: every caller
  # already renders one, whereas a MatchError here takes the calling process
  # down — a LiveView, i.e. the student's editor session. Only remote adapters
  # can actually fail (`Tasky.Storage.R2` returns `{:error, _}` for any non-2xx
  # or transport error); the local one always succeeds or raises.
  defp store_bytes(key, src_path, opts) do
    case Tasky.Storage.put(key, src_path, opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("upload: storing #{key} failed: #{inspect(reason)}")
        {:error, :storage_failed}
    end
  end

  defp storage_key(segments, stored_filename), do: Enum.join(segments ++ [stored_filename], "/")

  defp validate_file_ext(ext, allowed_exts) do
    if ext in allowed_exts and Map.has_key?(@ext_content_types, ext),
      do: :ok,
      else: {:error, :unsupported_type}
  end

  defp validate_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_file_bytes -> {:ok, size}
      {:ok, _} -> {:error, :too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  # Resolves a stored file to a serveable source ({:file, path} or
  # {:redirect, url}) after validating every path segment.
  defp fetch_stored(segments, stored_filename, opts \\ []) do
    with :ok <- validate_segments(segments),
         :ok <- validate_segment(stored_filename) do
      Tasky.Storage.fetch(storage_key(segments, stored_filename), opts)
    end
  end

  # Idempotent and always `:ok`, for the same reason as `delete_owner_files/2`.
  defp delete_stored(segments, stored_filename) do
    if validate_segments(segments) == :ok and validate_segment(stored_filename) == :ok do
      Tasky.Storage.delete(storage_key(segments, stored_filename))
    else
      Logger.warning(
        "upload: refusing to delete invalid key #{inspect(segments)}/#{inspect(stored_filename)}"
      )
    end

    :ok
  end

  defp validate_segments(segments) do
    if Enum.all?(segments, &(validate_segment(&1) == :ok)), do: :ok, else: {:error, :invalid}
  end

  # Content images are served world-readable and inline from /uploads, so an
  # upload must actually be the image type its content-type claims — first
  # bytes are checked against the format's signature (interim hardening while
  # files live on the local volume; see ROBUSTNESS_PLAN Phase 1.8/6).
  defp validate_image_signature(path, ext) do
    with {:ok, file} <- File.open(path, [:read, :binary]),
         head when is_binary(head) <- IO.binread(file, 12),
         :ok <- File.close(file),
         true <- image_signature_matches?(ext, head) do
      :ok
    else
      _ -> {:error, :invalid_image}
    end
  end

  defp image_signature_matches?(".png", <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>),
    do: true

  defp image_signature_matches?(".jpg", <<0xFF, 0xD8, 0xFF, _::binary>>), do: true
  defp image_signature_matches?(".gif", <<"GIF87a", _::binary>>), do: true
  defp image_signature_matches?(".gif", <<"GIF89a", _::binary>>), do: true

  defp image_signature_matches?(".webp", <<"RIFF", _::binary-size(4), "WEBP">>), do: true

  defp image_signature_matches?(_ext, _head), do: false

  defp allowed_extension(content_type) do
    case Map.fetch(@allowed_image_types, content_type) do
      {:ok, ext} -> {:ok, ext}
      :error -> {:error, :unsupported_type}
    end
  end

  defp extension_content_type(ext) do
    case Enum.find(@allowed_image_types, fn {_type, e} -> e == ext end) do
      {type, _ext} -> {:ok, type}
      nil -> {:error, :not_found}
    end
  end

  defp validate_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_bytes -> :ok
      {:ok, _} -> {:error, :too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  # Single path segment: no separators or traversal.
  defp validate_segment(seg) do
    if seg != "" and not String.contains?(seg, ["/", "\\", ".."]) and
         Regex.match?(~r/\A[A-Za-z0-9._-]+\z/, seg),
       do: :ok,
       else: {:error, :invalid}
  end
end
