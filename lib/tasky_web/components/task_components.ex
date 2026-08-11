defmodule TaskyWeb.TaskComponents do
  @moduledoc """
  Presentational bits shared by the learning-unit surfaces that are not part of
  the content editor itself.

  Zurzeit nur die Beschriftung der Freigabe-Modi: sie erscheint im
  Erstellen-Formular und im Bearbeiten-Modal, und eine zweite Kopie würde
  irgendwann von der ersten abweichen.
  """

  @doc """
  Die Optionen für `<.radio_group field={f[:solution_release_mode]}>`.

  Die Reihenfolge steigt von "gar nicht" nach "am meisten sichtbar", damit die
  vorsichtigste Wahl oben steht — sie ist auch der Standard.
  """
  def solution_release_options do
    [
      %{
        value: "never",
        label: "Nie anzeigen",
        description: "Lernende sehen weder Musterlösung noch Korrektur."
      },
      %{
        value: "manual",
        label: "Nach manueller Freigabe",
        description: "Du gibst im Fortschritt einzeln oder für alle frei – auch als Sammelaktion."
      },
      %{
        value: "on_complete",
        label: "Automatisch nach der Abgabe",
        description: "Sichtbar, sobald die Lernenden die Lerneinheit als erledigt markiert haben."
      }
    ]
  end
end
