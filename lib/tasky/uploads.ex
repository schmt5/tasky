defmodule Tasky.Uploads do
  @moduledoc """
  Stores and locates user-uploaded files (currently exam content images).

  Files live under the configured `:uploads_dir` (see `config/runtime.exs`) and
  are served back via `TaskyWeb.UploadController` at `/uploads/...`. The stored
  filename and extension are derived server-side from the validated content
  type, never from the client-supplied name.
  """

  @max_bytes 10 * 1024 * 1024

  # Allowed image content types mapped to the extension we store them under.
  @allowed_image_types %{
    "image/png" => ".png",
    "image/jpeg" => ".jpg",
    "image/gif" => ".gif",
    "image/webp" => ".webp"
  }

  @doc "Absolute base directory for uploads."
  def dir, do: Application.fetch_env!(:tasky, :uploads_dir)

  @doc """
  Saves an uploaded image for the given exam and returns `{:ok, url}` with the
  public `/uploads/...` path, or `{:error, reason}`.
  """
  def save_exam_image(exam_id, %Plug.Upload{} = upload) do
    with {:ok, ext} <- allowed_extension(upload.content_type),
         :ok <- validate_size(upload.path) do
      filename = Ecto.UUID.generate() <> ext
      dest_dir = Path.join([dir(), "exams", to_string(exam_id)])
      File.mkdir_p!(dest_dir)
      File.cp!(upload.path, Path.join(dest_dir, filename))
      {:ok, "/uploads/exams/#{exam_id}/#{filename}"}
    end
  end

  @doc """
  Resolves a stored image to `{:ok, {absolute_path, content_type}}` for serving,
  guarding against path traversal and unknown extensions.
  """
  def fetch_exam_image(exam_id, filename) do
    ext = filename |> Path.extname() |> String.downcase()

    with :ok <- validate_segment(to_string(exam_id)),
         :ok <- validate_segment(filename),
         {:ok, content_type} <- extension_content_type(ext) do
      path = Path.join([dir(), "exams", to_string(exam_id), filename])

      if File.regular?(path) do
        {:ok, {path, content_type}}
      else
        {:error, :not_found}
      end
    end
  end

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
