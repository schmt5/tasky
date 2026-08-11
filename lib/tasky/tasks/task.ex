defmodule Tasky.Tasks.Task do
  @moduledoc """
  Schema einer Lerneinheit.

  `content` ist das Tiptap-Dokument der Aufgabe, `sample_solution` die
  Musterlösung dazu — nicht als zweites Dokument, sondern als Map
  `answerId => Payload` über dieselben Antwortfelder (siehe
  `Tasky.Correction.AnswerKey`). Beide sind client-kontrolliertes JSON und
  darum bewusst **nicht** aus `changeset/3` castbar.

  `solution_release_mode` steuert, wann Lernende Musterlösung und Korrektur
  sehen (`never` | `manual` | `on_complete`). Es ist eine Freigabe-Steuerung
  und gehört nicht ins generische Formular — dafür gibt es
  `solution_release_mode_changeset/2`. Ausgewertet wird der Modus an genau
  einer Stelle: `Tasky.Tasks.solution_visible?/2`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :name, :string
    field :position, :integer
    field :status, :string
    field :locked, :boolean, default: false
    # An "erweiterte Lerneinheit" is voluntary: students may do it, but it does
    # not count towards the mandatory progress bar.
    field :extended, :boolean, default: false
    field :content, :map
    field :sample_solution, :map, default: %{}
    field :solution_release_mode, :string, default: "never"
    field :user_id, :id

    belongs_to :course, Tasky.Courses.Course
    has_many :submissions, Tasky.Tasks.TaskSubmission
    has_many :attachments, Tasky.Tasks.TaskAttachment
    has_many :upload_fields, Tasky.Tasks.TaskUploadField
    has_many :solution_files, Tasky.Tasks.TaskSolutionFile

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(draft published archived)
  @release_modes ~w(never manual on_complete)

  @doc "Die gültigen Freigabe-Modi der Musterlösung."
  def release_modes, do: @release_modes

  @doc false
  def changeset(task, attrs, user_scope) do
    task
    |> cast(attrs, [:name, :position, :status, :course_id, :locked, :extended])
    |> validate_required(:name, message: "Name darf nicht leer sein.")
    |> validate_required([:position, :status])
    |> validate_inclusion(:status, @statuses)
    |> put_change(:user_id, user_scope.user.id)
  end

  # Client-controlled JSON must stay within reason.
  @max_content_bytes 5 * 1024 * 1024

  @doc """
  Changeset for saving the learning unit's Tiptap content doc.
  """
  def content_changeset(task, content) when is_map(content) do
    task
    |> change(content: content)
    |> validate_change(:content, fn :content, doc ->
      if :erlang.external_size(doc) > @max_content_bytes,
        do: [content: "Inhalt ist zu gross"],
        else: []
    end)
  end

  @doc """
  Changeset für die Musterlösung (Map `answerId => Payload`).

  Zweite client-kontrollierte JSON-Spalte, darum dieselbe Grössenbremse wie
  bei `content`.
  """
  def sample_solution_changeset(task, answers) when is_map(answers) do
    task
    |> change(sample_solution: answers)
    |> validate_change(:sample_solution, fn :sample_solution, doc ->
      if :erlang.external_size(doc) > @max_content_bytes,
        do: [sample_solution: "Musterlösung ist zu gross"],
        else: []
    end)
  end

  @doc "Changeset für den Freigabe-Modus der Musterlösung."
  def solution_release_mode_changeset(task, mode) do
    task
    |> change(solution_release_mode: mode)
    |> validate_inclusion(:solution_release_mode, @release_modes)
  end
end
