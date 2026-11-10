defmodule Tasky.Tasks.Task do
  @moduledoc """
  Schema einer Lerneinheit.

  `content` ist das Tiptap-Dokument der Aufgabe, `sample_solution` die
  Musterlösung dazu — nicht als zweites Dokument, sondern als Map
  `answerId => Payload` über dieselben Antwortfelder (siehe
  `Tasky.Correction.AnswerKey`). Beide sind client-kontrolliertes JSON und
  darum bewusst **nicht** aus `changeset/2` castbar.

  `solution_release_mode` steuert, wann Lernende Musterlösung und Korrektur
  sehen (`never` | `manual` | `on_complete`). Er wird beim Erstellen und
  Bearbeiten der Lerneinheit gesetzt und ist darum — anders als die beiden
  JSON-Spalten — regulär castbar. Ausgewertet wird der Modus an genau einer
  Stelle: `Tasky.Tasks.solution_visible?/2`.

  `correction_config` hält die Korrekturoptionen pro Frage (`partId =>
  Optionen`), in derselben Form wie `ai_correction_config` einer Prüfung
  (siehe `Tasky.Correction.PartConfig`). Geschrieben wird sie ausschliesslich
  über `Tasky.Tasks.apply_part_options/4`, nicht über ein Formular.

  `self_check_off` wird nicht mehr gelesen — die Migration
  `AddCorrectionConfigToTasks` hat es in `correction_config` übertragen. Die
  Spalte fällt in einem späteren Deploy weg.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @typedoc "A persisted Task row."
  @type t :: %__MODULE__{}

  schema "tasks" do
    field :name, :string
    field :position, :integer
    # Release state for students, passed through in this order:
    # "draft" (invisible) → "locked" (visible as "Bald verfügbar", not
    # startable) → "open" (workable). Going back is allowed.
    field :status, :string
    # An "erweiterte Lerneinheit" is voluntary: students may do it, but it does
    # not count towards the mandatory progress bar.
    field :extended, :boolean, default: false
    field :content, :map
    field :sample_solution, :map, default: %{}
    field :correction_config, :map, default: %{}
    # Deprecated: read by no one since `correction_config`; dropped in a
    # later deploy (live data, boot-time migrator).
    field :self_check_off, {:array, :string}, default: []
    field :solution_release_mode, :string, default: "never"
    field :user_id, :id

    belongs_to :course, Tasky.Courses.Course
    has_many :submissions, Tasky.Tasks.TaskSubmission
    has_many :attachments, Tasky.Tasks.TaskAttachment
    has_many :upload_fields, Tasky.Tasks.TaskUploadField
    has_many :solution_files, Tasky.Tasks.TaskSolutionFile

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(draft locked open)
  @student_visible_statuses ~w(locked open)
  @release_modes ~w(never manual on_complete)

  @doc "Die gültigen Freigabe-Zustände, in der Reihenfolge, in der sie durchlaufen werden."
  def statuses, do: @statuses

  @doc "Die Zustände, in denen Lernende die Einheit sehen (gesperrt oder offen)."
  def student_visible_statuses, do: @student_visible_statuses

  @doc "True, wenn Lernende die Einheit sehen, aber noch nicht starten können."
  def locked?(%__MODULE__{status: status}), do: status == "locked"

  @doc "Die gültigen Freigabe-Modi der Musterlösung."
  def release_modes, do: @release_modes

  # Owner and course are set once, in create_changeset/3. Writing the owner on
  # every update handed a unit to whichever admin last renamed it, locking the
  # teacher out; a castable course_id let an update move a unit into a course
  # its owner does not manage.
  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :name,
      :position,
      :status,
      :extended,
      :solution_release_mode
    ])
    |> validate_required(:name, message: "Name darf nicht leer sein.")
    |> validate_required([:position, :status, :solution_release_mode])
    |> validate_inclusion(:status, @statuses)
    # `validate_inclusion` alone is not enough: Ecto skips `validate_change` for
    # a nil change, so a form that omits the field (or a crafted submit) sent
    # NULL into a `null: false` column and raised a Postgrex error past the
    # caller's `case`.
    |> validate_inclusion(:solution_release_mode, @release_modes)
  end

  @doc false
  def create_changeset(task, attrs, user_scope) do
    task
    |> changeset(attrs)
    |> cast(attrs, [:course_id])
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

  @doc """
  Changeset für die Korrekturoptionen pro Frage.

  Eigenes Changeset statt `changeset/2`: die Map kommt nie aus einem
  Formular, sondern immer aus `Tasky.Tasks.apply_part_options/4`, das sie über
  `Tasky.Correction.PartConfig` baut.
  """
  def correction_config_changeset(task, config) when is_map(config) do
    change(task, correction_config: config)
  end
end
