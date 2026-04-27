defmodule TaskyWeb.Guest.SebController do
  @moduledoc """
  Serves Safe Exam Browser (SEB) configuration file downloads and a quit page
  for guest exam sessions.
  """

  use TaskyWeb, :controller

  alias Tasky.Exams
  alias Tasky.Exams.SebConfig

  @doc """
  Serves the `.seb` configuration file as a download.

  Returns 404 if SEB is not enabled for the exam.
  """
  def config(conn, %{"exam_token" => exam_token}) do
    submission = Exams.get_exam_submission_by_token!(exam_token)

    if submission.exam.seb_enabled do
      base_url = TaskyWeb.Endpoint.url()
      start_url = base_url <> "/guest/exam/#{exam_token}"
      quit_url = base_url <> "/guest/exam/#{exam_token}/seb-quit"

      seb_binary =
        SebConfig.generate(
          start_url: start_url,
          quit_url: quit_url,
          quit_password: submission.exam.seb_quit_password
        )

      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("content-disposition", ~s(attachment; filename="exam.seb"))
      |> send_resp(200, seb_binary)
    else
      conn
      |> put_status(:not_found)
      |> text("Not Found")
      |> halt()
    end
  end

  @doc """
  Renders the SEB quit page.

  When SEB navigates to this URL it recognises it as the configured quit link
  and auto-exits. The HTML body is a simple fallback for non-SEB browsers.
  """
  def quit(conn, %{"exam_token" => exam_token}) do
    _submission = Exams.get_exam_submission_by_token!(exam_token)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, """
    <!DOCTYPE html>
    <html>
    <head><title>SEB beenden</title></head>
    <body style="display:flex;align-items:center;justify-content:center;min-height:100vh;font-family:system-ui;color:#44403c;">
      <div style="text-align:center;">
        <h1 style="font-size:1.5rem;margin-bottom:0.5rem;">Safe Exam Browser wird beendet…</h1>
        <p style="color:#78716c;">Du kannst dieses Fenster jetzt schliessen.</p>
      </div>
    </body>
    </html>
    """)
  end
end
