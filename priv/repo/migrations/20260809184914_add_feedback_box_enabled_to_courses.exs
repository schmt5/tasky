defmodule Tasky.Repo.Migrations.AddFeedbackBoxEnabledToCourses do
  use Ecto.Migration

  # Der anonyme Feedback-Briefkasten ist pro Kurs zuschaltbar und startet
  # geschlossen: Bestandskurse sollen nicht plötzlich einen neuen Kanal öffnen,
  # den die Lehrperson nie bewusst aktiviert hat.
  def change do
    alter table(:courses) do
      add :feedback_box_enabled, :boolean, default: false, null: false
    end
  end
end
