defmodule Tasky.Repo.Migrations.RemoveTallyFields do
  use Ecto.Migration

  def up do
    drop_if_exists index(:tasks, [:tally_form_id])
    drop_if_exists index(:task_submissions, [:tally_response_id])

    alter table(:tasks) do
      remove :tally_form_id
      remove :link
    end

    alter table(:task_submissions) do
      remove :tally_response_id
    end

    alter table(:users) do
      remove :tally_api_key
    end
  end

  def down do
    alter table(:tasks) do
      add :tally_form_id, :string
      add :link, :string
    end

    alter table(:task_submissions) do
      add :tally_response_id, :string
    end

    alter table(:users) do
      add :tally_api_key, :string
    end

    create index(:tasks, [:tally_form_id])

    create unique_index(:task_submissions, [:tally_response_id],
             where: "tally_response_id IS NOT NULL"
           )
  end
end
