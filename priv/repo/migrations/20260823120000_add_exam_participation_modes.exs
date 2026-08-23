defmodule Tasky.Repo.Migrations.AddExamParticipationModes do
  use Ecto.Migration

  def change do
    alter table(:exams) do
      # Written only by `Exams.open_exam_session/3`, never mass-assigned. The
      # DB default is "anonymous" so exams opened before this migration keep
      # their enrollment link; the UI pre-selects "assigned" for new sessions.
      add :participation_mode, :string, null: false, default: "anonymous"

      # Release flag for handing a corrected exam back to assigned
      # participants. Nil means "not returned" — undo is a single nil.
      add :returned_at, :utc_datetime

      # What a returned exam shows. Four booleans rather than one :map because
      # `ExamLive.Print` reads these options with atom keys (from PrintToken)
      # while a :map column comes back from Postgres with string keys — the
      # mismatch would silently render an empty page.
      add :return_show_points_and_mark, :boolean, null: false, default: true
      add :return_show_content, :boolean, null: false, default: true
      add :return_show_correction, :boolean, null: false, default: false
      add :return_show_sample_solution, :boolean, null: false, default: false
    end

    create constraint(:exams, :exams_participation_mode_check,
             check: "participation_mode IN ('assigned','anonymous')"
           )

    alter table(:exam_submissions) do
      # Nilify rather than cascade: a graded submission must survive an account
      # deletion, which is exactly what the copied firstname/lastname/email are
      # for.
      add :user_id, references(:users, on_delete: :nilify_all)
    end

    # NULLs are distinct in Postgres, so anonymous rows (user_id IS NULL) are
    # unaffected by this index and stay unlimited.
    create unique_index(:exam_submissions, [:exam_id, :user_id])
    create index(:exam_submissions, [:user_id])
  end
end
