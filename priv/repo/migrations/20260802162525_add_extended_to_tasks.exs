defmodule Tasky.Repo.Migrations.AddExtendedToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :extended, :boolean, default: false, null: false
    end
  end
end
