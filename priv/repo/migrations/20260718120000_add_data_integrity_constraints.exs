defmodule Tasky.Repo.Migrations.AddDataIntegrityConstraints do
  use Ecto.Migration

  def up do
    # Beta rule (docs/ROBUSTNESS_PLAN.md): conflicting rows may simply be
    # deleted — keep the oldest submission per (exam_id, email).
    execute """
    DELETE FROM exam_submissions
    WHERE id NOT IN (
      SELECT MIN(id) FROM exam_submissions GROUP BY exam_id, email
    )
    """

    create unique_index(:exam_submissions, [:exam_id, :email],
             name: :exam_submissions_exam_id_email_index
           )
  end

  def down do
    drop index(:exam_submissions, [:exam_id, :email], name: :exam_submissions_exam_id_email_index)
  end
end
