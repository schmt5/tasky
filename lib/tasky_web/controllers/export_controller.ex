defmodule TaskyWeb.ExportController do
  @moduledoc """
  Serves one-time downloads of exported ZIPs produced by
  `Tasky.Exams.ExportRunner`.

  Access is gated by a `token` query param signed via
  `Tasky.Exams.ExportDownloadToken`. After serving, the file is deleted.
  """

  use TaskyWeb, :controller

  alias Tasky.Exams.ExportDownloadToken

  def download(conn, %{"token" => token}) do
    case ExportDownloadToken.verify(conn.private.phoenix_endpoint, token) do
      {:ok, {path, filename}} ->
        if File.exists?(path) do
          # Don't delete the file here — register_before_send fires before the
          # body is streamed, which would corrupt the download. The ExportRunner
          # schedules a fallback cleanup after 10 minutes.
          conn
          |> put_resp_header("content-type", "application/zip")
          |> put_resp_header(
            "content-disposition",
            ~s(attachment; filename="#{filename}")
          )
          |> send_file(200, path)
        else
          conn
          |> put_status(:not_found)
          |> text("Datei nicht mehr verfügbar.")
        end

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
