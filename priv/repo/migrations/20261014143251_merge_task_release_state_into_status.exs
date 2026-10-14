defmodule Tasky.Repo.Migrations.MergeTaskReleaseStateIntoStatus do
  use Ecto.Migration

  # `tasks.status` now carries the whole release state, draft → locked → open,
  # instead of `status` (draft/published/archived) plus the `locked` flag.
  #
  #   published + locked     → locked  (visible, not startable)
  #   published + not locked → open
  #   draft, archived        → draft   (both were invisible to students)
  #
  # The `locked` column stays for now: migrations run when a new machine boots,
  # while the old release still serves requests and still selects `locked`.
  # Dropping it belongs in a later release, once no running code reads it.
  def up do
    execute "UPDATE tasks SET status = 'locked' WHERE status = 'published' AND locked"
    execute "UPDATE tasks SET status = 'open' WHERE status = 'published'"

    execute "UPDATE tasks SET status = 'draft' WHERE status IS NULL OR status NOT IN ('locked', 'open')"
  end

  def down do
    execute "UPDATE tasks SET locked = (status = 'locked')"
    execute "UPDATE tasks SET status = 'published' WHERE status IN ('locked', 'open')"
  end
end
