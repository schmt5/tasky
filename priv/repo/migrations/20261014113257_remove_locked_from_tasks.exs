defmodule Tasky.Repo.Migrations.RemoveLockedFromTasks do
  use Ecto.Migration

  # `tasks.status` now carries the whole release state (draft → locked → open),
  # so the separate `locked` flag goes.
  def change do
    alter table(:tasks) do
      remove :locked, :boolean, default: false, null: false
    end
  end
end
