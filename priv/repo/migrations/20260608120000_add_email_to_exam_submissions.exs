defmodule Tasky.Repo.Migrations.AddEmailToExamSubmissions do
  use Ecto.Migration

  def change do
    # Nullable so the column can be added to a table with existing rows;
    # presence is enforced for new enrollments in the changeset.
    alter table(:exam_submissions) do
      add :email, :string
    end
  end
end
