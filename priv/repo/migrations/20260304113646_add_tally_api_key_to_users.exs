defmodule Tasky.Repo.Migrations.AddTallyApiKeyToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :tally_api_key, :string
    end
  end
end
