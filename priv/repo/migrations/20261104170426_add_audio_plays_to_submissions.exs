defmodule Tasky.Repo.Migrations.AddAudioPlaysToSubmissions do
  use Ecto.Migration

  # How often a learner has played each audio block (see Tasky.AudioPlays).
  # Kept apart from `content`: in a free-document exam the client writes that
  # doc as it pleases, and a counter living there could be reset from the
  # browser. A constant default fills existing rows without rewriting them.
  def change do
    alter table(:exam_submissions) do
      add :audio_plays, :map, null: false, default: %{}
    end

    alter table(:task_submissions) do
      add :audio_plays, :map, null: false, default: %{}
    end
  end
end
