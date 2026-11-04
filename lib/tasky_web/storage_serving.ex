defmodule TaskyWeb.StorageServing do
  @moduledoc """
  Serves `Tasky.Storage` sources: local files via `send_file`/`send_download`,
  remote objects (presigned URLs) via a 302 redirect. The one place the
  local-vs-R2 difference is visible to controllers.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, send_download: 3]

  @doc "Serves a source as a download with the given user-facing filename."
  # Paths come from Tasky.Storage keys built out of validated segments and
  # server-generated stored filenames — no user-controlled path components.
  # sobelow_skip ["Traversal.SendDownload"]
  def serve_download(conn, {:file, path}, filename, content_type) do
    send_download(conn, {:file, path}, filename: filename, content_type: content_type)
  end

  def serve_download(conn, {:redirect, url}, _filename, _content_type) do
    redirect(conn, external: url)
  end

  @doc """
  Serves a source inline (images, PDFs) with the given content type.

  `:cache_control` defaults to the immutable public caching that suits the
  world-readable `/uploads/...` content images. Anything served behind
  authentication has to pass a private value instead, so a shared cache never
  holds one student's file.
  """
  # Same provenance as above — no user-controlled path components.
  # sobelow_skip ["Traversal.SendFile"]
  def serve_inline(conn, source, content_type, opts \\ [])

  def serve_inline(conn, {:file, path}, content_type, opts) do
    cache_control = Keyword.get(opts, :cache_control, "public, max-age=31536000, immutable")

    conn
    |> put_resp_header("content-type", content_type)
    |> put_resp_header("cache-control", cache_control)
    |> send_file(200, path)
  end

  def serve_inline(conn, {:redirect, url}, _content_type, _opts) do
    redirect(conn, external: url)
  end

  @doc """
  Serves audio for an `<audio>` element. Never cached: whether the file may be
  loaded at all depends on the learner's plays, so a cached copy would outlive
  the check.

  Local files honour a single `Range: bytes=…` — without it Safari refuses to
  play and no browser can resume mid-file. R2's presigned URLs answer ranges
  themselves.
  """
  # Same provenance as above — no user-controlled path components.
  # sobelow_skip ["Traversal.SendFile"]
  def serve_media(conn, {:file, path}, content_type) do
    %{size: size} = File.stat!(path)

    conn =
      conn
      |> put_resp_header("content-type", content_type)
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("accept-ranges", "bytes")

    case byte_range(get_req_header(conn, "range"), size) do
      {first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      :unsatisfiable ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")

      :full ->
        send_file(conn, 200, path)
    end
  end

  def serve_media(conn, {:redirect, url}, _content_type) do
    conn |> put_resp_header("cache-control", "private, no-store") |> redirect(external: url)
  end

  defp byte_range(["bytes=" <> spec], size) do
    case String.split(spec, "-", parts: 2) do
      ["", suffix] -> suffix_range(Integer.parse(suffix), size)
      [first, ""] -> open_range(Integer.parse(first), size)
      [first, last] -> closed_range(Integer.parse(first), Integer.parse(last), size)
      _ -> :full
    end
  end

  defp byte_range(_header, _size), do: :full

  defp suffix_range({n, ""}, size) when n > 0 and size > 0, do: {max(size - n, 0), size - 1}
  defp suffix_range({_n, ""}, _size), do: :unsatisfiable
  defp suffix_range(_n, _size), do: :full

  defp open_range({first, ""}, size) when first >= 0 and first < size, do: {first, size - 1}
  defp open_range({_first, ""}, _size), do: :unsatisfiable
  defp open_range(_first, _size), do: :full

  defp closed_range({first, ""}, {last, ""}, size)
       when first >= 0 and first <= last and first < size,
       do: {first, min(last, size - 1)}

  # first > last is no valid range at all: the header is ignored (RFC 9110).
  defp closed_range({first, ""}, {last, ""}, _size) when first > last, do: :full
  defp closed_range({_, ""}, {_, ""}, _size), do: :unsatisfiable
  defp closed_range(_first, _last, _size), do: :full
end
