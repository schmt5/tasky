defmodule Tasky.Repo.Migrations.AddPasswordToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :hashed_password, :string, null: false, default: ""
    end
  end
end
