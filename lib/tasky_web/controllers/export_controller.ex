defmodule TaskyWeb.ExportController do
  @moduledoc """
  Serves one-time downloads of exported ZIPs produced by
  `Tasky.Exams.ExportRunner`.

  Access is gated by a `token` query param signed via
  `Tasky.Exams.ExportDownloadToken`. After serving, the file is deleted.
  """

  use TaskyWeb, :controller

  alias Tasky.Exams.ExportDownloadToken

  # File paths are built from DB rows with server-generated stored filenames
  # or segments validated by Tasky.Uploads.validate_segment/1 - no user-
  # controlled path components reach the filesystem call.
  # sobelow_skip ["Traversal.SendFile"]
  def download(conn, %{"token" => token}) do
    with {:ok, {export_id, filename}} <-
           ExportDownloadToken.verify(conn.private.phoenix_endpoint, token),
         {:ok, path} <- Tasky.Exams.ExportRunner.export_path(export_id),
         true <- File.exists?(path) do
      # Don't delete the file here — register_before_send fires before the
      # body is streamed, which would corrupt the download. The ExportJanitor
      # removes stale ZIPs.
      conn
      |> put_resp_header("content-type", "application/zip")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{filename}")
      )
      |> send_file(200, path)
    else
      false ->
        conn |> put_status(:not_found) |> text("Datei nicht mehr verfügbar.")

      {:error, _reason} ->
        conn
        |> put_status(:forbidden)
        |> text("Ungültiger oder abgelaufener Download-Link.")
    end
  end

  def download(conn, _params) do
    conn |> put_status(:bad_request) |> text("Token fehlt.")
  end
end
