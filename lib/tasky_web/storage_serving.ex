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
end
