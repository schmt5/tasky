defmodule Tasky.Repo.Migrations.AddShareSlugToCourses do
  use Ecto.Migration

  # Nullable and not backfilled: existing courses get their slug lazily, the
  # first time a teacher asks for the share link.
  def change do
    alter table(:courses) do
      add :share_slug, :string
    end

    create unique_index(:courses, [:share_slug])
  end
end
