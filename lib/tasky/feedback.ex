defmodule Tasky.Feedback do
  @moduledoc """
  Der anonyme Feedback-Briefkasten eines Kurses.

  Lernende schreiben Freitext an ihre Lehrperson; die Lehrperson liest Text,
  Datum und Lesestatus — nie den Absender. Der Briefkasten ist pro Kurs
  zuschaltbar (`Course.feedback_box_enabled`) und startet geschlossen.

  Die Anonymität wird hier durchgesetzt, nicht in der Web-Schicht:
  `list_messages/2` selektiert `student_id` gar nicht erst, die zurückgegebenen
  Structs können die Identität also auch versehentlich nicht durchreichen.
  Gespeichert bleibt sie trotzdem — sie trägt die Missbrauchsbremse in
  `create_message/3` und ist der Grund, warum die UI von "die Lehrperson sieht
  deinen Namen nicht" spricht und nicht von "vollständig anonym".

  Anders als die älteren Enrollment-Funktionen in `Tasky.Courses` autorisiert
  hier **jede** Funktion selbst; kein Aufrufer muss vorher etwas geprüft haben.
  """

  import Ecto.Query, warn: false

  alias Tasky.Accounts.Scope
  alias Tasky.Courses
  alias Tasky.Courses.Course
  alias Tasky.Feedback.Message
  alias Tasky.Repo

  # Missbrauchsbremse: grosszügig genug, dass normales Schreiben nie anschlägt.
  @rate_limit_count 5
  @rate_limit_window_seconds 15 * 60

  @doc """
  Legt eine Nachricht im Briefkasten eines Kurses an.

  Nur eingeschriebene Lernende, nur bei offenem Briefkasten, höchstens
  #{@rate_limit_count} Nachrichten pro #{div(@rate_limit_window_seconds, 60)}
  Minuten und Kurs.

  Gibt `{:ok, message}`, `{:error, :not_found}` (Kurs weg oder nicht
  eingeschrieben), `{:error, :disabled}`, `{:error, :rate_limited}` oder
  `{:error, changeset}` zurück.
  """
  def create_message(%Scope{user: %{role: "student", id: student_id}}, course_id, attrs) do
    with %Course{} = course <- Courses.get_enrolled_course(student_id, course_id),
         :ok <- check_box_open(course),
         :ok <- check_rate_limit(course.id, student_id) do
      %Message{}
      |> Message.create_changeset(attrs, course.id, student_id)
      |> Repo.insert()
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_message(_scope, _course_id, _attrs), do: {:error, :not_found}

  @doc """
  Die Nachrichten eines Kurses, neueste zuerst — **ohne Absenderangabe**.

  Das `select` ist der Anonymitätsschutz: die zurückgegebenen `%Message{}`
  tragen `student_id: nil`, egal was in der Datenbank steht.
  """
  def list_messages(scope, %Course{} = course) do
    with :ok <- Tasky.Policy.authorize(scope, course.teacher_id) do
      {:ok,
       Repo.all(
         from m in Message,
           where: m.course_id == ^course.id,
           order_by: [desc: m.inserted_at, desc: m.id],
           select: struct(m, [:id, :course_id, :body, :read_at, :inserted_at])
       )}
    end
  end

  @doc "Markiert eine Nachricht als gelesen."
  def mark_read(scope, message_id), do: set_read_at(scope, message_id, DateTime.utc_now(:second))

  @doc "Macht eine Nachricht wieder ungelesen."
  def mark_unread(scope, message_id), do: set_read_at(scope, message_id, nil)

  @doc """
  Dreht den Lesestatus um.

  Der aktuelle Wert wird hier gelesen, nicht vom Client mitgeschickt — sonst
  hinge das Ergebnis an einem Zustand, den die Oberfläche nur glaubt zu kennen.
  """
  def toggle_read(scope, message_id) do
    with {:ok, message} <- fetch_manageable_message(scope, message_id) do
      new_value = if message.read_at, do: nil, else: DateTime.utc_now(:second)
      write_read_at(message, new_value)
    end
  end

  @doc """
  Löscht eine Nachricht. Gibt die gelöschte (anonymisierte) Nachricht zurück —
  die Oberfläche braucht deren Lesestatus, um ihren Zähler zu korrigieren.
  """
  def delete_message(scope, message_id) do
    with {:ok, message} <- fetch_manageable_message(scope, message_id),
         {:ok, deleted} <- Repo.delete(message) do
      {:ok, anonymize(deleted)}
    end
  end

  @doc "Changeset für das Formular der Lernenden."
  def change_message(%Message{} = message \\ %Message{}, attrs \\ %{}) do
    Message.changeset(message, attrs)
  end

  # Private

  defp set_read_at(scope, message_id, value) do
    with {:ok, message} <- fetch_manageable_message(scope, message_id) do
      write_read_at(message, value)
    end
  end

  defp write_read_at(%Message{} = message, value) do
    message
    |> Ecto.Changeset.change(read_at: value)
    |> Repo.update()
    |> case do
      # Nie die volle Zeile zurückgeben: sie trägt die student_id.
      {:ok, updated} -> {:ok, anonymize(updated)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # Lädt die Nachricht samt Kurs und prüft die Besitzverhältnisse selbst — sich
  # auf ein LiveView-Assign zu verlassen, wäre eine Vertrauensgrenze zu weit.
  defp fetch_manageable_message(scope, message_id) do
    result =
      Repo.one(
        from m in Message,
          join: c in Course,
          on: c.id == m.course_id,
          where: m.id == ^message_id,
          select: {m, c.teacher_id}
      )

    case result do
      nil ->
        {:error, :not_found}

      {message, teacher_id} ->
        with :ok <- Tasky.Policy.authorize(scope, teacher_id), do: {:ok, message}
    end
  end

  defp anonymize(%Message{} = message), do: %{message | student_id: nil}

  defp check_box_open(%Course{feedback_box_enabled: true}), do: :ok
  defp check_box_open(%Course{}), do: {:error, :disabled}

  defp check_rate_limit(course_id, student_id) do
    since = DateTime.add(DateTime.utc_now(:second), -@rate_limit_window_seconds, :second)

    count =
      Repo.aggregate(
        from(m in Message,
          where:
            m.course_id == ^course_id and m.student_id == ^student_id and m.inserted_at >= ^since
        ),
        :count
      )

    if count < @rate_limit_count, do: :ok, else: {:error, :rate_limited}
  end
end
