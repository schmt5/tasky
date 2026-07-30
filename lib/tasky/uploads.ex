defmodule Tasky.Uploads do
  @moduledoc """
  Stores and locates user-uploaded files: exam content images, teacher
  attachments (Anhänge) and student answer files (Datei-Abgaben).

  Files live under the configured `:uploads_dir` (see `config/runtime.exs`) and
  are served back via `TaskyWeb.UploadController` at `/uploads/...`. The stored
  filename and extension are derived server-side from the validated file type,
  never from the client-supplied name.
  """

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
         :ok <- validate_image_signature(upload.path, ext) do
      filename = Ecto.UUID.generate() <> ext

      :ok =
        Tasky.Storage.put(storage_key(["exams", to_string(exam_id)], filename), upload.path,
          content_type: content_type_for_ext(ext),
          disposition: "inline"
        )

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
         :ok <- validate_image_signature(upload.path, ext) do
      filename = Ecto.UUID.generate() <> ext

      :ok =
        Tasky.Storage.put(storage_key(["tasks", to_string(task_id)], filename), upload.path,
          content_type: content_type_for_ext(ext),
          disposition: "inline"
        )

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
  def file_type(key), do: :proplists.get_value(key, @file_types, nil)

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
  def delete_exam_files(exam_id) do
    with :ok <- validate_segment(to_string(exam_id)) do
      Tasky.Storage.delete_prefix("exams/#{exam_id}")
    end

    :ok
  end

  @doc "Removes every stored file of a learning unit (task); see `delete_exam_files/1`."
  def delete_task_files(task_id) do
    with :ok <- validate_segment(to_string(task_id)) do
      Tasky.Storage.delete_prefix("tasks/#{task_id}")
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
         {:ok, size} <- validate_file_size(src_path) do
      stored_filename = Ecto.UUID.generate() <> ext
      content_type = content_type_for_ext(ext) || "application/octet-stream"

      :ok =
        Tasky.Storage.put(storage_key(segments, stored_filename), src_path,
          content_type: content_type,
          disposition: {"attachment", original_name}
        )

      {:ok,
       %{
         stored_filename: stored_filename,
         content_type: content_type,
         size: size
       }}
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

  defp delete_stored(segments, stored_filename) do
    with :ok <- validate_segments(segments),
         :ok <- validate_segment(stored_filename) do
      Tasky.Storage.delete(storage_key(segments, stored_filename))
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
