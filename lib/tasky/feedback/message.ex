defmodule Tasky.Feedback.Message do
  @moduledoc """
  Eine Nachricht aus dem anonymen Feedback-Briefkasten eines Kurses.

  Freitext von Lernenden an ihre Lehrperson, ohne Bezug zu einer Lerneinheit.
  Die Lehrperson sieht Text, Datum und Lesestatus — nie den Absender.

  Die Anonymität ist pseudonym, nicht absolut: `student_id` steht in der
  Datenbank (sonst gäbe es keine Missbrauchsbremse), wird aber nie an die
  Web-Schicht herausgegeben. Texte gegenüber Lernenden müssen das so benennen —
  "die Lehrperson sieht deinen Namen nicht", nicht "niemand kann das
  zurückverfolgen".
  """
  use Ecto.Schema
  import Ecto.Changeset

  # Freitext von Lernenden — grosszügig, aber nicht unbegrenzt (gleiche
  # Grössenordnung wie das Lehrpersonen-Feedback an einer Abgabe).
  @max_body_chars 5_000

  schema "course_feedback_messages" do
    field :body, :string
    field :read_at, :utc_datetime

    belongs_to :course, Tasky.Courses.Course

    # Wird nie aus User-Input gecastet und nie an die Web-Schicht
    # herausgegeben — `Tasky.Feedback.list_messages/2` selektiert das Feld
    # bewusst nicht. Nur die Missbrauchsbremse liest es.
    belongs_to :student, Tasky.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Maximale Länge einer Nachricht."
  def max_body_chars, do: @max_body_chars

  @doc """
  Changeset für das Formular der Lernenden. Castet ausschliesslich den Text —
  Kurs- und Absenderzuordnung setzt `create_changeset/3` aus dem Scope.
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &normalize_body/1)
    |> validate_required([:body], message: "Bitte schreibe zuerst etwas.")
    |> validate_length(:body,
      max: @max_body_chars,
      message: "Die Nachricht ist zu lang (maximal #{@max_body_chars} Zeichen)."
    )
  end

  @doc false
  def create_changeset(message, attrs, course_id, student_id) do
    message
    |> changeset(attrs)
    |> put_change(:course_id, course_id)
    |> put_change(:student_id, student_id)
    |> foreign_key_constraint(:course_id)
    |> foreign_key_constraint(:student_id)
  end

  # Reiner Whitespace ist keine Nachricht — `nil` lässt validate_required greifen.
  defp normalize_body(nil), do: nil

  defp normalize_body(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
