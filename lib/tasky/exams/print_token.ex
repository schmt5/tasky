defmodule Tasky.Exams.PrintToken do
  @moduledoc """
  Signs and verifies short-lived tokens that grant Gotenberg's headless
  Chrome read-only access to a single submission's print-view.

  The payload is a 4-tuple: `{teacher_user_id, exam_id, submission_id, opts}`.
  `opts` is a map of `%{show_content: bool, show_correction: bool,
  show_sample_solution: bool}`.
  """

  @salt "exam-submission-print-view"
  # 15 minutes is plenty for a single export job (typical job is seconds).
  @max_age 15 * 60

  def sign(endpoint, teacher_user_id, exam_id, submission_id, opts) do
    payload = {teacher_user_id, exam_id, submission_id, opts}
    Phoenix.Token.sign(endpoint, @salt, payload)
  end

  def verify(endpoint, token) when is_binary(token) do
    Phoenix.Token.verify(endpoint, @salt, token, max_age: @max_age)
  end

  def verify(_endpoint, _), do: {:error, :missing}
end
