defmodule Tasky.Repo.Migrations.CreateCourseFeedbackMessages do
  use Ecto.Migration

  def change do
    create table(:course_feedback_messages) do
      add :course_id, references(:courses, on_delete: :delete_all), null: false

      # Bewusst nullable mit `nilify_all`: wird ein Konto gelöscht, verschwindet
      # die Zuordnung, die Rückmeldung bleibt der Lehrperson erhalten. Die Spalte
      # dient nur der Missbrauchsbremse (`Tasky.Feedback` zählt darauf) — sie wird
      # nie an die Web-Schicht herausgegeben.
      add :student_id, references(:users, on_delete: :nilify_all)

      add :body, :text, null: false
      add :read_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Liste der Lehrperson (neueste zuerst).
    create index(:course_feedback_messages, [:course_id, :inserted_at])

    # Rate-Limit-Abfrage: Nachrichten dieser Person in diesem Kurs seit X.
    create index(:course_feedback_messages, [:student_id, :inserted_at])
  end
end
