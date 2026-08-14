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
  def changeset(exam_submission, attrs) do
    exam_submission
    |> cast(attrs, [:firstname, :lastname, :email])
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
    |> unique_constraint([:exam_id, :email],
      name: :exam_submissions_exam_id_email_index,
      message: "ist für diese Prüfung bereits eingeschrieben"
    )
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
