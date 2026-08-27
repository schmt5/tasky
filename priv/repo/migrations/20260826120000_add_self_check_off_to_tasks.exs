defmodule Tasky.Repo.Migrations.AddSelfCheckOffToTasks do
  use Ecto.Migration

  def change do
    # Die answerIds, die von der automatischen Selbstkontrolle ausgenommen sind.
    # Default leer: erfasste Antwortfelder werden geprüft, die Lehrperson nimmt
    # nur offene Formulierungsfragen bewusst heraus.
    alter table(:tasks) do
      add :self_check_off, {:array, :string}, null: false, default: []
    end
  end
end
