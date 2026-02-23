defmodule Tasky.Repo.Migrations.RemovePasswordAuthentication do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :hashed_password
    end
  end
end
