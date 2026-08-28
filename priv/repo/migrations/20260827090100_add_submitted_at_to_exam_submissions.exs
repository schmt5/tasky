defmodule Tasky.Repo.Migrations.AddSubmittedAtToExamSubmissions do
  use Ecto.Migration

  @moduledoc """
  The moment the participant handed in. `updated_at` is not that moment — it
  moves on every autosave, and auto-correction during a running exam can push
  it past the hand-in — so a dispute about when someone submitted had nothing
  to stand on. Written in the same transaction that flips `submitted`.
  """

  def change do
    alter table(:exam_submissions) do
      add :submitted_at, :utc_datetime
    end
  end
end
