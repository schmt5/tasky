defmodule Tasky.Repo.Migrations.DropSebEnforcementOff do
  use Ecto.Migration

  @moduledoc """
  Drops the `"off"` SEB enforcement mode, leaving `"observe"` and `"enforce"`.

  `"off"` meant "SEB is required, but do not check whether it is really SEB".
  Once the guard stopped mistaking a merely *tolerated* request for a verified
  one, that became a strictly worse `"observe"`: exactly the same people reach
  the exam (only the spoofable user-agent hint gates the page), minus the
  cockpit diagnosis that makes exam day debuggable.

  It was also a second control for one decision, and the failure it invited was
  the bad direction: a teacher picking "Aus" to mean "no Safe Exam Browser"
  while every participant still faced the download gate. Not wanting SEB is
  said by clearing `seb_enabled` — which `TaskyWeb.SebGuard.mode/1` already
  reports as `:off`, so nothing downstream had to change.
  """

  def up do
    execute "UPDATE exams SET seb_enforcement = 'observe' WHERE seb_enforcement = 'off'"

    drop constraint(:exams, :exams_seb_enforcement_check)

    create constraint(:exams, :exams_seb_enforcement_check,
             check: "seb_enforcement in ('observe','enforce')"
           )
  end

  def down do
    drop constraint(:exams, :exams_seb_enforcement_check)

    create constraint(:exams, :exams_seb_enforcement_check,
             check: "seb_enforcement in ('off','observe','enforce')"
           )
  end
end
