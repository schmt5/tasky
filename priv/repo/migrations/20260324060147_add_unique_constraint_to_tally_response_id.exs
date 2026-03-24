defmodule Tasky.Repo.Migrations.AddUniqueConstraintToTallyResponseId do
  use Ecto.Migration

  def change do
    drop index(:task_submissions, [:tally_response_id])

    create unique_index(:task_submissions, [:tally_response_id],
             where: "tally_response_id IS NOT NULL"
           )
  end
end
