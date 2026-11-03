defmodule Tasky.Repo.Migrations.AddInviteTokenToClasses do
  use Ecto.Migration

  # The class registration link used the slug, which is derived from the class
  # name ("Klasse 5a" -> "klasse-5a") and therefore guessable. The new
  # invite_token is the credential; the slug stays for display only.
  #
  # The column default is volatile, so Postgres draws a fresh value for every
  # existing row while adding the column — that is the backfill. It stays in
  # place afterwards because the migration runs on boot while the previous
  # release still serves requests and inserts classes without a token.
  # The app itself sets a token on insert (see Tasky.Classes).
  #
  # Links already handed out (?class=<slug>) stop working with this deploy:
  # keeping them alive would keep the guessable credential alive.
  def change do
    alter table(:classes) do
      add :invite_token, :string,
        null: false,
        default: fragment("replace(gen_random_uuid()::text, '-', '')")
    end

    create unique_index(:classes, [:invite_token])
  end
end
