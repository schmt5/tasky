defmodule Tasky.Repo.Migrations.AddCatalogPublishedAtToCourses do
  use Ecto.Migration

  # Kurs-Katalog: Zeitpunkt, an dem die Lehrperson den Kurs bewusst für alle
  # anderen Lehrpersonen freigegeben hat — NULL heisst "nicht im Katalog".
  # Zeitstempel statt Boolean, weil die Katalogliste das Veröffentlichungsdatum
  # anzeigt und danach sortiert; `updated_at` wäre dafür falsch, jede
  # Textkorrektur würde die Liste umsortieren.
  def change do
    alter table(:courses) do
      add :catalog_published_at, :utc_datetime
    end

    # Einziger Leser ist die Katalogliste: nur veröffentlichte Kurse, nach
    # Datum absteigend. Partieller Index, weil der Normalfall NULL ist.
    create index(:courses, [:catalog_published_at],
             where: "catalog_published_at IS NOT NULL",
             name: :courses_catalog_published_at_index
           )
  end
end
