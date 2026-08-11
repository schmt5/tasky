defmodule Tasky.Repo.Migrations.AddSampleSolutionToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      # Musterlösung als answerId => Payload-Map, wie bei Prüfungen. Nicht
      # nullable, damit kein Leser `|| %{}` braucht.
      add :sample_solution, :map, null: false, default: %{}
      add :solution_release_mode, :string, null: false, default: "never"
    end

    alter table(:task_submissions) do
      add :corrected_content, :map, null: false, default: %{}
      # Nur manuelle Freigaben. `on_complete` wird zur Lesezeit über
      # `completed_at` ausgewertet, siehe `Tasky.Tasks.solution_visible?/2`.
      add :solution_released_at, :utc_datetime
    end

    create constraint(:tasks, :tasks_solution_release_mode_check,
             check: "solution_release_mode IN ('never','manual','on_complete')"
           )
  end
end
