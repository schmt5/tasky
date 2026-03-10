defmodule Tasky.Repo.Migrations.AddClassIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :class_id, references(:classes, on_delete: :nilify_all)
    end

    create index(:users, [:class_id])
  end
end
