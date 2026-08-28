defmodule TaskyWeb.Guest.SebController do
  @moduledoc """
  Serves Safe Exam Browser (SEB) configuration file downloads and a quit page
  for guest exam sessions.
  """

  use TaskyWeb, :controller

  alias Tasky.Exams
  alias Tasky.Exams.SebConfig
  alias TaskyWeb.SebGuard

  @doc """
  Serves the `.seb` configuration file as a download.

  Returns 404 if SEB is not enabled for the exam.
  """
  def config(conn, %{"exam_token" => exam_token}) do
    submission = Exams.get_exam_submission_by_token!(exam_token)

    if submission.exam.seb_enabled do
      # One place assembles the options, so the file handed out and the Config
      # Key the guard checks are derived from identical input.
      seb_binary =
        submission.exam
        |> SebGuard.config_opts(submission)
        |> SebConfig.generate()

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
  The SEB gate as its own page.

  `TaskyWeb.SebGuardHook` redirects here when it halts a LiveView mount: a
  halted mount cannot render the gate itself, and the participant still needs
  the download link. Renders the same component as the LiveView's own gate.
  """
  def required(conn, %{"exam_token" => exam_token}) do
    submission = Exams.get_exam_submission_by_token!(exam_token)

    conn
    |> put_status(:forbidden)
    |> put_view(html: TaskyWeb.Guest.SebHTML)
    |> put_layout(false)
    |> render(:required,
      page_title: "Safe Exam Browser erforderlich",
      exam_token: submission.exam_token,
      reason: :no_header
    )
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
