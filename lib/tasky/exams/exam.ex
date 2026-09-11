defmodule Tasky.Exams.Exam do
  use Ecto.Schema
  import Ecto.Changeset

  @typedoc "A persisted Exam row."
  @type t :: %__MODULE__{}

  schema "exams" do
    field :name, :string
    field :content, :map, default: %{}
    field :sample_solution, :map, default: %{}
    field :sample_solution_points, :map, default: %{}
    # %{part_id => %{answer_id => points}} — a part uses custom (unequal)
    # point distribution iff its inner map is non-empty; otherwise the part's
    # sample_solution_points value is split equally across its answer blocks.
    field :sample_solution_block_points, :map, default: %{}
    field :enrollment_token, :string
    field :status, :string, default: "draft"
    field :seb_enabled, :boolean, default: false
    field :seb_quit_password, :string
    field :seb_admin_password, :string
    field :seb_enforcement, :string, default: "observe"
    field :seb_bypass_until, :utc_datetime
    field :seb_accepted_config_keys, {:array, :string}, default: []
    field :seb_allow_files, :boolean, default: false
    field :ai_correction_config, :map, default: %{}
    field :grading_max_points, :float
    field :participation_mode, :string, default: "anonymous"
    field :answer_mode, :string, default: "answer_fields"
    field :returned_at, :utc_datetime
    field :return_show_points_and_mark, :boolean, default: true
    field :return_show_content, :boolean, default: true
    field :return_show_correction, :boolean, default: false
    field :return_show_sample_solution, :boolean, default: false
    # %{answer_id => lines} — how many writing lines each answer field gets on
    # the printed paper version. Not part of :content, which is the document
    # the learners sit: the paper version grows a box by putting empty
    # paragraphs inside it, and those have no business in the digital exam.
    # Written only by Exams.update_paper_layout/3 and the duplication path
    # (see the migration).
    field :paper_layout, :map

    belongs_to :teacher, Tasky.Accounts.User, foreign_key: :teacher_id
    has_many :exam_submissions, Tasky.Exams.ExamSubmission

    timestamps(type: :utc_datetime)
  end

  @participation_modes ~w(assigned anonymous)

  @doc "The two ways a session can be run. See `open_changeset/3`."
  def participation_modes, do: @participation_modes

  @answer_modes ~w(answer_fields free_document)

  @doc """
  The two kinds of exam. See `new_changeset/2` and the migration.

    * `"answer_fields"` — questions (h3) plus answer fields; the learner
      may only type into those fields.
    * `"free_document"` — no answer fields; the learner edits the whole
      document. Graded as one part (`ExamDoc.free_document_part_id/0`).
  """
  def answer_modes, do: @answer_modes

  @doc false
  # :status, :enrollment_token and :participation_mode are deliberately not
  # castable — the exam lifecycle goes through Exams.update_exam_status/3 /
  # open_exam_session/3. Same for :returned_at and the :return_show_* flags,
  # which only Exams.return_exam/3 writes, and for the SEB enforcement fields
  # (:seb_enforcement, :seb_bypass_until, :seb_accepted_config_keys), which
  # only Exams.set_seb_enforcement/3, bypass_seb/3 and
  # accept_seb_config_key/3 write. :paper_layout is the same: only
  # Exams.update_paper_layout/3 and the duplication path write it (both via
  # change/2), so the exam form cannot reach the print geometry at all. :seb_admin_password rides along with
  # :seb_quit_password: both are minted server-side in
  # CockpitConfig.maybe_generate_seb_passwords/2 and only ever reach cast/3
  # from there. :answer_mode is castable in new_changeset/2 only — see there.
  def changeset(exam, attrs) do
    exam
    |> cast(attrs, [
      :name,
      :content,
      :sample_solution,
      :sample_solution_points,
      :sample_solution_block_points,
      :seb_enabled,
      :seb_quit_password,
      :seb_admin_password,
      :ai_correction_config,
      :grading_max_points
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 3, max: 255)
  end

  @doc false
  def create_changeset(exam, attrs, scope) do
    exam
    |> new_changeset(attrs)
    |> put_change(:teacher_id, scope.user.id)
  end

  @doc """
  Changeset for the create form. Identical to `changeset/2` except that it is
  the **only** place `:answer_mode` is castable.

  The mode is a one-time decision: part ids, answer ids, block verdicts and the
  sample solution all hang off it, so switching later would strand data rather
  than convert it. Keeping the cast out of `changeset/2` makes that structural
  instead of a rule someone has to remember — `update_exam/3` cannot write the
  column at all.
  """
  def new_changeset(exam, attrs) do
    exam
    |> changeset(attrs)
    |> cast(attrs, [:answer_mode])
    |> validate_required([:answer_mode])
    |> validate_inclusion(:answer_mode, @answer_modes)
    |> check_constraint(:answer_mode, name: :exams_answer_mode_check)
  end

  @doc """
  Opens the session: sets the status and the participation mode, plus the
  enrollment token for anonymous sessions (`nil` for assigned ones).

  The mode arrives from a client-side radio, so it goes through `cast/3` and
  `validate_inclusion/3` rather than `Ecto.Changeset.change/2` — the latter
  would write whatever it was handed.
  """
  def open_changeset(exam, mode, enrollment_token, allow_files?) do
    exam
    |> cast(%{participation_mode: mode}, [:participation_mode])
    |> validate_required([:participation_mode])
    |> validate_inclusion(:participation_mode, @participation_modes)
    |> check_constraint(:participation_mode, name: :exams_participation_mode_check)
    |> put_change(:status, "open")
    |> put_change(:enrollment_token, enrollment_token)
    # Frozen here, not derived per request: the SEB Config Key is a function of
    # the settings, so a file appearing mid-exam would invalidate every `.seb`
    # already downloaded. See the migration for the full reasoning.
    |> put_change(:seb_allow_files, allow_files?)
  end

  # No "off": an exam that requires SEB always gets checked. Not wanting SEB is
  # said by clearing :seb_enabled. See the DropSebEnforcementOff migration.
  @enforcement_modes ~w(observe enforce)

  @doc "The SEB enforcement modes. See the migration for what each one means."
  def seb_enforcement_modes, do: @enforcement_modes

  @doc """
  Sets the SEB enforcement mode. Goes through `cast/3` + `validate_inclusion/3`
  because the value arrives from a client-side control, and `change/2` would
  write whatever it was handed.
  """
  def seb_enforcement_changeset(exam, mode) do
    exam
    |> cast(%{seb_enforcement: mode}, [:seb_enforcement])
    |> validate_required([:seb_enforcement])
    |> validate_inclusion(:seb_enforcement, @enforcement_modes)
    |> check_constraint(:seb_enforcement, name: :exams_seb_enforcement_check)
  end

  @doc """
  Hands a corrected exam back to the assigned participants (or withdraws it,
  when `returned_at` is nil). The four flags decide what the participants see
  and mirror the PDF export options.
  """
  def return_changeset(exam, attrs) do
    exam
    |> cast(attrs, [
      :returned_at,
      :return_show_points_and_mark,
      :return_show_content,
      :return_show_correction,
      :return_show_sample_solution
    ])
  end
end
