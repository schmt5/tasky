defmodule Tasky.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    # `citext` gives case-insensitive email comparison at the column level.
    # Accounts looks users up with a plain `Repo.get_by(User, email: email)` and
    # nothing downcases the address, so without this a user who registered with
    # a capital letter could not log in.
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users) do
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
