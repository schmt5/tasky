defmodule Tasky.Repo.Migrations.AddSebFieldsToExams do
  use Ecto.Migration

  def change do
    alter table(:exams) do
      add :seb_enabled, :boolean, default: false, null: false
      add :seb_quit_password, :string
    end
  end
end
