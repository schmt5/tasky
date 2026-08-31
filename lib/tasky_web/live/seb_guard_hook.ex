defmodule TaskyWeb.SebGuardHook do
  @moduledoc """
  `on_mount` hook that enforces the Safe Exam Browser requirement on LiveView
  mounts.

  The `:seb_guard_html` pipeline only runs on HTTP requests. Both guest
  LiveViews share one `live_session`, so after one legitimate page load a client
  can `live_redirect` to arbitrary `/guest/exam/:token` URLs over the open
  websocket without passing a pipeline again — exactly the hole
  `TaskyWeb.GuestRateLimit` exists to close for rate limiting.

  ## Two ways to be satisfied, and why both are needed

  1. **The header.** `connect_info: [:x_headers, ...]` on the endpoint exposes
     every `x-`-prefixed request header of the websocket upgrade, and SEB's is
     `x-`-prefixed. When it is there, it is checked.

  2. **The session stamp** written by `TaskyWeb.Plugs.SebGuard` on a verified
     HTTP request. Whether SEB injects its headers into a WebSocket *handshake*
     is not something to assume — request interception in an embedded browser
     does not always cover it. Without the stamp, an SEB that skips the upgrade
     headers would be locked out of its own exam.

  It also assigns `:seb_state`, which is what the exam view and the cockpit's
  presence indicator read. The old user-agent sniff stays only as a cosmetic
  hint, never as a gate.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2, get_connect_info: 2]

  alias Tasky.Exams
  alias TaskyWeb.Plugs.SebGuard, as: GuardPlug
  alias TaskyWeb.SebGuard

  @doc """
  `:verified` — a valid Config Key hash on this very mount.
  `:stamped` — no header here, but a verified HTTP request earlier in this
  session (the normal case for a websocket).
  `:unverified` — neither. Reaching the exam in this state means SEB is not
  required for it, the mode is `observe`, or the check could not be made.
  """
  @type seb_state :: :verified | :stamped | :unverified

  def on_mount(:default, params, session, socket) do
    token = params["exam_token"]

    with token when is_binary(token) <- token,
         submission when not is_nil(submission) <-
           Exams.get_exam_submission_by_token(token),
         exam = submission.exam,
         mode when mode != :off <- SebGuard.mode(exam) do
      case resolve(exam, submission, session, socket, token) do
        # The Config Key could not be derived at all. That is our bug, not this
        # participant's, so it must never be the reason a graded exam ends —
        # same call as `TaskyWeb.SebGuard.check/4` makes for HTTP. Still counted
        # as unverified, so the cockpit stays honest.
        :undecidable ->
          {:cont, assign(socket, :seb_state, :unverified)}

        :unverified when mode == :enforce ->
          {:halt, redirect(socket, to: "/guest/exam/#{token}/seb-required")}

        state ->
          {:cont, assign(socket, :seb_state, state)}
      end
    else
      # Not an exam mount, an unknown token (the LiveView gives its own "Link
      # ungültig"), or SEB not in play.
      _ -> {:cont, assign(socket, :seb_state, :unverified)}
    end
  end

  defp resolve(exam, submission, session, socket, token) do
    case header_verdict(exam, submission, socket) do
      :ok -> :verified
      {:error, :undecidable} -> :undecidable
      _ -> if GuardPlug.stamped?(session, token), do: :stamped, else: :unverified
    end
  end

  defp header_verdict(exam, submission, socket) do
    case SebGuard.observed_hash(x_headers(socket)) do
      nil ->
        {:error, :no_header}

      observed ->
        # The upgrade URL is not the page URL, and in tests `connect_info` is
        # derived from the dead-render conn — so a URL-salted comparison cannot
        # be trusted here. `expected_hashes/3` includes the unsalted hash, which
        # is what actually matches.
        SebGuard.verdict(exam, submission, observed, uri(socket))
    end
  end

  defp x_headers(socket) do
    case get_connect_info(socket, :x_headers) do
      headers when is_list(headers) -> headers
      _ -> []
    end
  end

  defp uri(socket) do
    case get_connect_info(socket, :uri) do
      %URI{} = uri -> URI.to_string(uri)
      _ -> nil
    end
  end
end
