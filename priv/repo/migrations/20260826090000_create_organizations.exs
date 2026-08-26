defmodule Tasky.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    create table(:organizations) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :invite_token, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizations, [:slug])
    create unique_index(:organizations, [:invite_token])

    # Nullable and without a backfill on purpose: the app is in beta, so
    # existing teachers and classes stay unassigned until an admin sorts them
    # into organizations. Every query is fail-closed on NULL.
    alter table(:users) do
      add :organization_id, references(:organizations, on_delete: :nilify_all)
    end

    alter table(:classes) do
      add :organization_id, references(:organizations, on_delete: :nilify_all)
    end

    create index(:users, [:organization_id])
    create index(:classes, [:organization_id])

    # Students never carry the organization themselves — theirs is derived from
    # `classes.organization_id` via `users.class_id`. Enforced here so the
    # single-source-of-truth rule cannot rot into a denormalised copy.
    create constraint(:users, :students_have_no_organization,
             check: "role <> 'student' OR organization_id IS NULL"
           )
  end
end
