defmodule TaskyWeb.Guest.SebHTML do
  @moduledoc """
  The non-LiveView rendering of the SEB gate.

  Exists because `TaskyWeb.Plugs.SebGuard` rejects plain HTTP requests — the
  exam page's dead render and the answer-file download — and those have no
  LiveView to fall back on. It renders the same
  `TaskyWeb.ExamComponents.seb_gate/1` the LiveView `cond` renders, so the two
  cannot drift apart.
  """
  use TaskyWeb, :html

  import TaskyWeb.ExamComponents, only: [seb_gate: 1]

  attr :exam_token, :string, required: true
  attr :reason, :atom, required: true

  def required(assigns) do
    ~H"""
    <Layouts.guest flash={%{}}>
      <.seb_gate exam_token={@exam_token} reason={@reason} />
    </Layouts.guest>
    """
  end
end
