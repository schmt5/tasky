defmodule Tasky.Repo.Migrations.AddDraftToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :locked, :boolean, default: false, null: false
    end
  end
end
