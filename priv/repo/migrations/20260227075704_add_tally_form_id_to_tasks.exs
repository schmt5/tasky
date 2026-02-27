defmodule Tasky.Repo.Migrations.AddTallyFormIdToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :tally_form_id, :string
    end

    create index(:tasks, [:tally_form_id])
  end
end
