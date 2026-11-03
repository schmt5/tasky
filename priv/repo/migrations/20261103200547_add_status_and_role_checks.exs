defmodule Tasky.Repo.Migrations.AddStatusAndRoleChecks do
  use Ecto.Migration

  # The changesets validate these values, but the columns took anything —
  # 20261014143251 had to clean up task statuses that were NULL or unknown, and
  # `users.role` decides what Tasky.Policy lets someone do.
  #
  # NOT VALID: the checks apply to every row written from now on, but the rows
  # already there are not scanned, so this cannot fail on live data or hold a
  # long lock during the deploy. Validating them is a second step, in a later
  # deploy, once a query has shown there is nothing left to clean up:
  #
  #   ALTER TABLE users VALIDATE CONSTRAINT users_role_check;
  #   (and the same for the three others)
  #
  # The value lists mirror User.valid_roles/0, Task.statuses/0,
  # TaskSubmission.valid_statuses/0 and the exam lifecycle in Tasky.Exams.
  def change do
    create constraint(:users, :users_role_check,
             check: "role IN ('admin','teacher','student')",
             validate: false
           )

    create constraint(:tasks, :tasks_status_check,
             check: "status IN ('draft','locked','open')",
             validate: false
           )

    create constraint(:task_submissions, :task_submissions_status_check,
             check:
               "status IN ('not_started','in_progress','in_revision','completed','review_approved','review_denied')",
             validate: false
           )

    create constraint(:exams, :exams_status_check,
             check: "status IN ('draft','open','running','finished')",
             validate: false
           )
  end
end
