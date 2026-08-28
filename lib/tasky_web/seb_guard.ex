defmodule TaskyWeb.SebGuard do
  @moduledoc """
  Decides whether a request for an exam actually came from Safe Exam Browser.

  Before this existed, the only check was `String.contains?(user_agent, "SEB")`,
  and it gated nothing but the rendered page: the autosave API, the uploads and
  the hand-in accepted anything. One string in a user-agent switcher took the
  whole exam in a normal browser with the internet open, and the cockpit
  reported that participant as green.

  ## What it checks

  With `sendBrowserExamKey` on, SEB sends `X-SafeExamBrowser-ConfigKeyHash` on
  its requests. The expected value is derived from the very config we handed
  out (`Tasky.Exams.SebConfig.config_key/1`), plus any hash the teacher has
  explicitly accepted in the cockpit. See `Tasky.Exams.SebConfigKey` for what
  this does and does not prove — it is a wrong-browser guard, not a
  cryptographic boundary.

  ## Modes

  Read off `exam.seb_enforcement`, and `:enforce` degrades to `:observe` while
  `exam.seb_bypass_until` lies in the future:

    * `:off` — no check.
    * `:observe` — check and report, never block. **The default**, because the
      Config Key derivation has to be confirmed against the SEB build actually
      installed in the exam room before it may lock anyone out.
    * `:enforce` — no valid hash, no exam.

  ## Why the logic lives here and not in `call/2`

  Same reason as `TaskyWeb.Plugs.RateLimit`: a plug only sees HTTP requests,
  and the guest LiveViews share one `live_session`, so a client can
  `live_redirect` between exam tokens over the open websocket without touching
  a pipeline again. `TaskyWeb.Plugs.SebGuard` and `TaskyWeb.SebGuardHook` both
  call into this module.
  """

  alias Tasky.Exams.Exam
  alias Tasky.Exams.ExamSubmission
  alias Tasky.Exams.SebConfig
  alias Tasky.Exams.SebConfigKey

  @type mode :: :off | :observe | :enforce
  @type result :: :ok | {:error, :no_header} | {:error, :mismatch}

  @header "x-safeexambrowser-configkeyhash"

  @doc "The request header SEB sends the Config Key hash in."
  @spec header_name() :: String.t()
  def header_name, do: @header

  @doc """
  The effective mode for this exam.

  An exam without SEB enabled is never guarded, whatever `seb_enforcement`
  says — the two settings are independent columns and only the pair means
  anything.
  """
  @spec mode(Exam.t()) :: mode()
  def mode(%Exam{seb_enabled: false}), do: :off

  def mode(%Exam{} = exam) do
    case exam.seb_enforcement do
      "enforce" -> if bypassed?(exam), do: :observe, else: :enforce
      "observe" -> :observe
      _ -> :off
    end
  end

  @doc "True while the teacher's kill switch is still running."
  @spec bypassed?(Exam.t()) :: boolean()
  def bypassed?(%Exam{seb_bypass_until: nil}), do: false

  def bypassed?(%Exam{seb_bypass_until: until}),
    do: DateTime.compare(until, DateTime.utc_now()) == :gt

  @doc """
  Hashes this exam's config would produce, plus the ones the teacher accepted.

  `url` is the fully-qualified request URL for a build that salts the hash with
  it; pass `nil` to compare against the bare Config Key. Both are returned, so
  a build that turns out not to salt still matches without a config change.
  """
  @spec expected_hashes(Exam.t(), ExamSubmission.t(), String.t() | nil) :: [String.t()]
  def expected_hashes(%Exam{} = exam, %ExamSubmission{} = submission, url) do
    keys = [
      SebConfig.config_key(config_opts(exam, submission)) | exam.seb_accepted_config_keys || []
    ]

    keys
    |> Enum.flat_map(fn key ->
      [SebConfigKey.request_hash(nil, key), SebConfigKey.request_hash(url, key)]
    end)
    |> Enum.uniq()
  end

  @doc """
  The options `SebConfig` needs for this exam — the single place they are
  assembled, so the file we hand out and the key we check are derived from
  identical input.
  """
  @spec config_opts(Exam.t(), ExamSubmission.t()) :: keyword()
  def config_opts(%Exam{} = exam, %ExamSubmission{} = submission) do
    base = TaskyWeb.Endpoint.url()

    [
      start_url: base <> "/guest/exam/#{submission.exam_token}",
      quit_url: base <> "/guest/exam/#{submission.exam_token}/seb-quit",
      quit_password: exam.seb_quit_password,
      admin_password: exam.seb_admin_password,
      allow_files?: exam.seb_allow_files,
      allowed_origins: TaskyWeb.ContentSecurityPolicy.storage_origins()
    ]
  end

  @doc """
  Checks one request's headers.

  Returns `:ok` unconditionally in `:off` and `:observe` — the caller decides
  what to do with the result, and in `:observe` it only reports.
  """
  @spec check(Exam.t(), ExamSubmission.t(), [{String.t(), String.t()}], String.t() | nil) ::
          result()
  def check(%Exam{} = exam, %ExamSubmission{} = submission, headers, url) do
    observed = observed_hash(headers)
    result = verdict(exam, submission, observed, url)

    report(exam, submission, observed, result)

    case mode(exam) do
      :enforce -> result
      _ -> :ok
    end
  end

  @doc """
  The unfiltered verdict, ignoring the mode. Used for the cockpit's honest
  per-participant state and by `check/4`.
  """
  @spec verdict(Exam.t(), ExamSubmission.t(), String.t() | nil, String.t() | nil) :: result()
  def verdict(_exam, _submission, nil, _url), do: {:error, :no_header}

  def verdict(exam, submission, observed, url) do
    if SebConfigKey.matches?(observed, expected_hashes(exam, submission, url)),
      do: :ok,
      else: {:error, :mismatch}
  end

  @doc "The Config Key hash a request carried, or `nil`."
  @spec observed_hash([{String.t(), String.t()}]) :: String.t() | nil
  def observed_hash(headers) when is_list(headers) do
    Enum.find_value(headers, fn {name, value} ->
      if String.downcase(name) == @header and is_binary(value) and value != "", do: value
    end)
  end

  @doc """
  The topic the cockpit subscribes to for observed hashes.
  """
  @spec topic(Exam.t() | integer()) :: String.t()
  def topic(%Exam{id: id}), do: topic(id)
  def topic(exam_id), do: "exam_seb:#{exam_id}"

  # Only mismatches are worth reporting. A verified class autosaves roughly once
  # per second per participant, and broadcasting those would be pure noise on
  # the cockpit's topic — "who is verified" is already answered by the presence
  # meta. What the teacher cannot get anywhere else is the hash a client sent
  # that we did *not* expect, because that is the value they may need to accept.
  #
  # Broadcast rather than stored: exam-day diagnostics, not an audit trail.
  defp report(exam, submission, observed, {:error, :mismatch}) when is_binary(observed) do
    if mode(exam) != :off do
      Phoenix.PubSub.broadcast(
        Tasky.PubSub,
        topic(exam),
        {:seb_observation, %{exam_token: submission.exam_token, observed: observed}}
      )
    end

    :ok
  end

  defp report(_exam, _submission, _observed, _result), do: :ok
end
