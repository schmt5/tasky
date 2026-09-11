defmodule Tasky.Tasks.TaskSubmission do
  @moduledoc """
  Schema for tracking a student's work on one learning unit.

  Der Ablauf: `not_started` → `in_progress` → `completed` (eingereicht) →
  `review_approved` oder `review_denied` (zurückgegeben). Nimmt der Lernende
  eine zurückgegebene Einheit wieder auf, geht sie nach `in_revision` und von
  dort erneut nach `completed`.

  Lerneinheiten werden nicht bewertet: es gibt nur einen Feedbacktext, und
  `feedback_at`/`feedback_by_id` sind ausschliesslich gesetzt, wenn dieser Text
  auch Inhalt hat — daran hängt der Feedback-Hinweis für Lernende.

  `corrected_content` ist das von der Lehrperson annotierte Antwortdokument
  (Rot-Text, `teacherComment`). Es gehört zur eingereichten Runde und wird
  beim Wiedereinreichen geleert — gleiche Begründung wie beim Feedback, es
  gibt keinen Korrektur-Verlauf.

  `solution_released_at` ist die manuelle Freigabe von Musterlösung *und*
  Korrektur für genau diesen Lernenden. Sie wird nie zurückgenommen, auch
  nicht bei einer Rückgabe — den Not-Aus für alle liefert der Modus `never`
  auf der Lerneinheit. Ausgewertet wird sie ausschliesslich in
  `Tasky.Tasks.solution_visible?/2`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @typedoc "A persisted TaskSubmission row."
  @type t :: %__MODULE__{}

  @valid_statuses ~w(not_started in_progress in_revision completed review_approved review_denied)

  # Freitext einer Lehrperson — grosszügig, aber nicht unbegrenzt.
  @max_feedback_chars 5_000

  schema "task_submissions" do
    field :status, :string, default: "not_started"
    field :completed_at, :utc_datetime
    field :feedback, :string

    field :feedback_at, :utc_datetime
    field :content, :map
    field :corrected_content, :map, default: %{}
    field :solution_released_at, :utc_datetime

    belongs_to :task, Tasky.Tasks.Task
    belongs_to :student, Tasky.Accounts.User
    belongs_to :feedback_by, Tasky.Accounts.User

    has_many :files, Tasky.Tasks.TaskSubmissionFile, foreign_key: :task_submission_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid statuses.
  """
  def valid_statuses, do: @valid_statuses

  @doc "Maximale Länge des Feedbacktexts."
  def max_feedback_chars, do: @max_feedback_chars

  @doc """
  Changeset for creating a new submission.
  Only sets the task_id and student_id.
  """
  def create_changeset(submission, attrs) do
    submission
    |> cast(attrs, [:task_id, :student_id])
    |> validate_required([:task_id, :student_id])
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:student_id)
    |> unique_constraint([:task_id, :student_id],
      name: :task_submissions_task_id_student_id_index,
      message: "submission already exists for this student and task"
    )
  end

  @doc """
  Changeset for updating submission status by a student.
  """
  def status_changeset(submission, attrs) do
    submission
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @valid_statuses)
    |> maybe_set_completed_at()
  end

  @doc """
  Changeset for completing a task.

  Sets status to "completed", sets completed_at and drops the feedback of the
  previous round: die Begründung einer Rückgabe darf nicht am neu eingereichten
  Stand kleben (es gibt keinen Feedback-Verlauf). Aus demselben Grund fällt
  auch die Korrektur weg — sie annotiert einen Antwortstand, den es nicht mehr
  gibt.

  `solution_released_at` wird bewusst NICHT angefasst: eine erteilte Freigabe
  bleibt bestehen, auch über eine Rückgabe und ein erneutes Einreichen hinweg.
  """
  def complete_changeset(submission) do
    submission
    |> change(
      status: "completed",
      completed_at: DateTime.utc_now(:second),
      feedback: nil,
      feedback_at: nil,
      feedback_by_id: nil,
      corrected_content: %{}
    )
  end

  # Client-controlled JSON must stay within reason.
  @max_content_bytes 5 * 1024 * 1024

  @doc """
  Changeset for saving the student's answer doc (Tiptap JSON).
  """
  def answers_changeset(submission, content) when is_map(content) do
    submission
    |> change(content: content)
    |> validate_change(:content, fn :content, doc ->
      if :erlang.external_size(doc) > @max_content_bytes,
        do: [content: "Inhalt ist zu gross"],
        else: []
    end)
  end

  @doc """
  Changeset für das von der Lehrperson annotierte Antwortdokument.
  """
  def correction_changeset(submission, content) when is_map(content) do
    submission
    |> change(corrected_content: content)
    |> validate_change(:corrected_content, fn :corrected_content, doc ->
      if :erlang.external_size(doc) > @max_content_bytes,
        do: [corrected_content: "Inhalt ist zu gross"],
        else: []
    end)
  end

  @doc """
  Changeset für den Feedbacktext einer Lehrperson.

  `feedback_at`/`feedback_by_id` werden nur gesetzt, wenn wirklich Text da ist —
  ein leeres Feld räumt beide wieder auf, damit der Hinweis "es gibt Feedback"
  nie ohne Inhalt erscheint.
  """
  def feedback_changeset(submission, attrs, author_id) do
    submission
    |> cast(attrs, [:feedback])
    |> update_change(:feedback, &normalize_feedback/1)
    |> validate_length(:feedback, max: @max_feedback_chars)
    |> put_feedback_author(author_id)
  end

  # Private Functions

  defp normalize_feedback(nil), do: nil

  defp normalize_feedback(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp put_feedback_author(changeset, author_id) do
    case fetch_field!(changeset, :feedback) do
      nil ->
        changeset
        |> put_change(:feedback_at, nil)
        |> put_change(:feedback_by_id, nil)

      _text ->
        changeset
        |> put_change(:feedback_at, DateTime.utc_now(:second))
        |> put_change(:feedback_by_id, author_id)
    end
  end

  defp maybe_set_completed_at(changeset) do
    case get_change(changeset, :status) do
      "completed" ->
        put_change(changeset, :completed_at, DateTime.utc_now(:second))

      _ ->
        changeset
    end
  end
end
