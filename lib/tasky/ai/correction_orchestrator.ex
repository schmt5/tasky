defmodule Tasky.AI.CorrectionOrchestrator do
  @moduledoc """
  The orchestration point between the exam domain and auto-correction:
  subscribes to the `"exam_events"` PubSub topic and starts
  `Tasky.AI.BulkCorrectionRunner` runs in response.

  `Tasky.Exams` only broadcasts domain events and never calls the runner
  (which itself calls back into `Exams`) — this process sits above both, so
  neither module depends on the other.

  Events:

    * `{:submission_submitted, exam, submission_id}` — correct that submission
    * `{:exam_answers_changed, exam}` — re-correct all submitted submissions
  """

  use GenServer

  @topic "exam_events"

  def topic, do: @topic

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ok = Phoenix.PubSub.subscribe(Tasky.PubSub, @topic)
    {:ok, %{}}
  end

  @impl true
  def handle_info({:submission_submitted, exam, submission_id}, state) do
    Tasky.AI.BulkCorrectionRunner.start_for_exam(exam, submission_id: submission_id)
    {:noreply, state}
  end

  def handle_info({:exam_answers_changed, exam}, state) do
    Tasky.AI.BulkCorrectionRunner.start_for_exam(exam)
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}
end
