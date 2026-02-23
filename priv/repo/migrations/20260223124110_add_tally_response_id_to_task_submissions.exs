defmodule Tasky.Repo.Migrations.AddTallyResponseIdToTaskSubmissions do
  use Ecto.Migration

  def change do
    alter table(:task_submissions) do
      add :tally_response_id, :string
    end

    create index(:task_submissions, [:tally_response_id])
  end
end
