defmodule Tasky.Repo.Migrations.AddSebEnforcementToExams do
  use Ecto.Migration

  @moduledoc """
  Turns the Safe Exam Browser requirement from an advisory hint into something
  the server can actually check.

  `seb_enforcement` is three-valued rather than a boolean on purpose:

    * `"off"`      — no check at all.
    * `"observe"`  — check, never block, record what real SEB clients send.
      This is the default, and it is the whole de-risking strategy: the Config
      Key derivation has to be confirmed against a real SEB client before it
      may be allowed to lock anyone out.
    * `"enforce"`  — no valid SEB request hash, no exam.

  `seb_accepted_config_keys` is the operator override: a hash observed from a
  real client can be accepted explicitly, so a config change mid-session (or a
  derivation we get subtly wrong) does not end the exam for the whole class.

  `seb_bypass_until` is the kill switch — while it lies in the future,
  `enforce` degrades to `observe`.

  `seb_allow_files` freezes, at the moment the session is opened, whether the
  exam hands out or takes in files. It is deliberately a stored decision rather
  than a live `exam_has_files?/1` query: the Config Key is a function of the
  settings, so deriving this per request would mean an attachment uploaded
  mid-exam silently invalidates every `.seb` file already downloaded — and it
  would put two `EXISTS` queries on the autosave path, which is the hottest
  write in the app.
  """

  def change do
    alter table(:exams) do
      add :seb_enforcement, :string, null: false, default: "observe"
      add :seb_admin_password, :string
      add :seb_bypass_until, :utc_datetime
      add :seb_accepted_config_keys, {:array, :string}, null: false, default: []
      add :seb_allow_files, :boolean, null: false, default: false
    end

    create constraint(:exams, :exams_seb_enforcement_check,
             check: "seb_enforcement in ('off','observe','enforce')"
           )
  end
end
