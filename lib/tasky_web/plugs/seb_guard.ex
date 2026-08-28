defmodule TaskyWeb.Plugs.SebGuard do
  @moduledoc """
  Enforces the Safe Exam Browser requirement on HTTP requests for a guest exam.

  Covers the exam page's dead render, the answer-file download and the guest
  autosave API. The websocket that carries the LiveView (and the LiveView
  uploads, which ride the same socket) is covered by `TaskyWeb.SebGuardHook`
  plus the session stamp this plug writes.

  Deliberately **not** applied to `/guest/exam/:token/seb-config` or
  `/seb-quit`: downloading the configuration is how a participant gets into
  SEB in the first place, so guarding it would make the exam unreachable.

  ## The session stamp

  On a verified request this writes `{token, at}` into the session. SEB keeps
  cookies within a session, so the stamp set on the dead render comes back on
  the websocket upgrade — which matters because whether SEB injects its headers
  into a WebSocket handshake is not something we can assume. The stamp is what
  binds the socket, the LiveView uploads and the JSON API to a verified HTTP
  entry.

  ## Options

    * `:on_reject` — `:html` renders the German "Safe Exam Browser erforderlich"
      page with a 403; `:json` answers
      `%{"error" => "seb_required", "code" => "seb_required"}`. The `code` is
      load-bearing: `assets/js/react/api.js` turns a bare 403 into a permanent
      "Sitzung abgelaufen" and stops autosaving, so the client needs to tell
      this case apart.
  """

  import Plug.Conn

  alias Tasky.Exams
  alias TaskyWeb.SebGuard

  # A stamp older than this stops counting. Long enough that no plausible exam
  # outlives it, short enough that a shared machine does not carry it into the
  # next lesson.
  @stamp_max_age_seconds 12 * 60 * 60

  def init(opts), do: %{on_reject: Keyword.get(opts, :on_reject, :html)}

  def call(conn, %{on_reject: on_reject}) do
    with {:ok, submission} <- fetch_submission(conn),
         exam = submission.exam,
         mode when mode != :off <- SebGuard.mode(exam) do
      case SebGuard.check(exam, submission, conn.req_headers, canonical_request_url(conn)) do
        :ok ->
          conn
          |> assign(:seb_submission, submission)
          |> stamp(submission)

        {:error, reason} ->
          reject(conn, on_reject, reason, submission)
      end
    else
      # No token in the path, an unknown token, or SEB not in play: nothing to
      # guard. An unknown token is the LiveView's and the controllers' own
      # 404 to give, not ours.
      _ -> conn
    end
  end

  @doc """
  True when this session carries a verified SEB stamp for `token`.

  Read by `TaskyWeb.SebGuardHook` for the websocket, where the headers may not
  be available.
  """
  @spec stamped?(map() | nil, String.t()) :: boolean()
  def stamped?(%{"seb" => %{"token" => token, "at" => at}}, token)
      when is_integer(at) do
    System.system_time(:second) - at <= @stamp_max_age_seconds
  end

  def stamped?(_session, _token), do: false

  defp stamp(conn, submission) do
    put_session(conn, "seb", %{
      "token" => submission.exam_token,
      "at" => System.system_time(:second)
    })
  end

  defp fetch_submission(conn) do
    case conn.path_params["exam_token"] || conn.path_params["token"] do
      token when is_binary(token) ->
        case Exams.get_exam_submission_by_token(token) do
          nil -> :error
          submission -> {:ok, submission}
        end

      _ ->
        :error
    end
  end

  # Built from the configured host, never from `conn.host`/`conn.scheme`: behind
  # a proxy those describe the hop, not what the browser asked for, and the hash
  # would never match. The configured host is both correct and unspoofable.
  defp canonical_request_url(conn) do
    base = TaskyWeb.Endpoint.url() <> conn.request_path

    case conn.query_string do
      "" -> base
      query -> base <> "?" <> query
    end
  end

  defp reject(conn, :json, reason, _submission) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      403,
      Jason.encode!(%{
        "error" => "seb_required",
        "code" => "seb_required",
        "reason" => to_string(reason)
      })
    )
    |> halt()
  end

  # Keeps the root layout, so the page gets the stylesheet and looks like the
  # LiveView gate rather than a bare error.
  defp reject(conn, :html, reason, submission) do
    conn
    |> put_status(:forbidden)
    |> Phoenix.Controller.put_view(html: TaskyWeb.Guest.SebHTML)
    |> Phoenix.Controller.put_layout(false)
    |> Phoenix.Controller.render(:required,
      page_title: "Safe Exam Browser erforderlich",
      exam_token: submission.exam_token,
      reason: reason
    )
    |> halt()
  end
end
