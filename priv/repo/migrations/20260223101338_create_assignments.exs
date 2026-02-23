defmodule Tasky.Repo.Migrations.CreateAssignments do
  use Ecto.Migration

  def change do
    create table(:assignments) do
      add :name, :string
      add :link, :string
      add :status, :string

      timestamps(type: :utc_datetime)
    end
  end
end
