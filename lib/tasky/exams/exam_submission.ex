defmodule Tasky.Exams.ExamSubmission do
  use Ecto.Schema
  import Ecto.Changeset

  schema "exam_submissions" do
    field :firstname, :string
    field :lastname, :string
    field :email, :string
    field :exam_token, :string
    field :submitted, :boolean, default: false
    field :content, :map, default: %{}
    field :corrected_parts, {:array, :string}, default: []
    field :auto_corrected_parts, {:array, :string}, default: []
    field :corrected_content, :map, default: %{}
    field :points_per_part, :map, default: %{}
    field :block_verdicts, :map, default: %{}
    # What the auto-corrector last wrote into `block_verdicts`. A block whose
    # current verdict still equals this one is the machine's own and may be
    # refreshed; anything else is the teacher's and must survive a re-run.
    field :auto_block_verdicts, :map, default: %{}
    field :mark, :float

    belongs_to :exam, Tasky.Exams.Exam
    # Set for assigned participants, nil for anonymous ones. Also nil again
    # once the account behind it is deleted — the copied name and email are
    # what keep such a submission gradable.
    belongs_to :user, Tasky.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for updating only the submission content (used by the student editor).
  """
  # Client-controlled JSON must stay within reason — a runaway (or malicious)
  # editor payload otherwise bloats the row unbounded.
  @max_content_bytes 5 * 1024 * 1024

  def content_changeset(exam_submission, attrs) do
    exam_submission
    |> cast(attrs, [:content])
    |> validate_required([:content])
    |> validate_content_size()
  end

  defp validate_content_size(changeset) do
    validate_change(changeset, :content, fn :content, content ->
      if :erlang.external_size(content) > @max_content_bytes do
        [content: "Inhalt ist zu gross"]
      else
        []
      end
    end)
  end

  @doc false
  # The anonymous self-enrolment changeset, fed straight from EnrollLive params.
  # :user_id is deliberately absent — a user_id in that payload would be a
  # privilege escalation. Assignments go through assignment_changeset/2.
  def changeset(exam_submission, attrs) do
    exam_submission
    |> cast(attrs, [:firstname, :lastname, :email])
    |> validate_participant()
    |> unique_constraint([:exam_id, :email],
      name: :exam_submissions_exam_id_email_index,
      message: "ist für diese Prüfung bereits eingeschrieben"
    )
  end

  @doc """
  Assigns a logged-in participant. Name and email are copied from the account
  so the submission stays gradable after an account deletion nilifies
  `user_id`.
  """
  def assignment_changeset(exam_submission, attrs) do
    exam_submission
    |> cast(attrs, [:user_id, :firstname, :lastname, :email])
    |> validate_required([:user_id], message: "darf nicht leer sein")
    |> validate_participant()
    |> unique_constraint([:exam_id, :user_id],
      name: :exam_submissions_exam_id_user_id_index,
      message: "ist dieser Prüfung bereits zugewiesen"
    )
    |> unique_constraint([:exam_id, :email],
      name: :exam_submissions_exam_id_email_index,
      message: "ist dieser Prüfung bereits zugewiesen"
    )
    |> foreign_key_constraint(:user_id)
  end

  defp validate_participant(changeset) do
    changeset
    |> validate_required([:firstname, :lastname, :email],
      message: "darf nicht leer sein"
    )
    |> validate_length(:firstname,
      max: 100,
      message: "darf höchstens 100 Zeichen lang sein"
    )
    |> validate_length(:lastname,
      max: 100,
      message: "darf höchstens 100 Zeichen lang sein"
    )
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/,
      message: "muss eine gültige E-Mail-Adresse sein"
    )
    |> validate_length(:email,
      max: 160,
      message: "darf höchstens 160 Zeichen lang sein"
    )
    |> put_exam_token()
    |> unique_constraint(:exam_token)
  end

  defp put_exam_token(changeset) do
    if get_change(changeset, :exam_token) do
      changeset
    else
      put_change(changeset, :exam_token, generate_exam_token())
    end
  end

  defp generate_exam_token do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
