defmodule Tasky.Exams.ExamPrintToken do
  @moduledoc """
  Signs and verifies short-lived tokens that grant Gotenberg's headless Chrome
  read-only access to an exam's **paper version** (`TaskyWeb.ExamLive.Paper`).

  The payload is a 3-tuple: `{teacher_user_id, exam_id, opts}`.

  Its own salt rather than a nil `submission_id` in `Tasky.Exams.PrintToken`:
  one salt, one audience. A paper token can then never be replayed against the
  submission print view, even if the pattern match over there is later
  loosened. `opts` is carried (and currently empty) so a future print option
  needs no change to the token shape.
  """

  @salt "exam-paper-print-view"
  # 15 minutes is plenty for a single render (typically seconds).
  @max_age 15 * 60

  def sign(endpoint, teacher_user_id, exam_id, opts) do
    Phoenix.Token.sign(endpoint, @salt, {teacher_user_id, exam_id, opts})
  end

  def verify(endpoint, token) when is_binary(token) do
    Phoenix.Token.verify(endpoint, @salt, token, max_age: @max_age)
  end

  def verify(_endpoint, _), do: {:error, :missing}
end
