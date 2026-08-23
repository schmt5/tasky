defmodule TaskyWeb.ExamComponents do
  @moduledoc """
  Presentational bits shared by the exam surfaces.

  Hier liegt Copy, die an mehr als einer Stelle erscheint: die Beschreibung der
  Durchführungsmodi (Config-Seite und Cockpit) und die Optionen einer
  Submission-Ansicht (PDF-Export und Rückgabe an die Teilnehmenden). Eine
  zweite Kopie würde irgendwann von der ersten abweichen — und bei den
  Ansichtsoptionen sollen Export und Rückgabe konstruktionsbedingt identisch
  aussehen.
  """

  use Phoenix.Component

  import TaskyWeb.CoreComponents, only: [icon: 1]

  @doc """
  Die beiden Durchführungsmodi, in der Reihenfolge, in der sie auf der
  Config-Seite stehen. `assigned` ist die Vorauswahl.

  Vokabular, das über die Prüfungsflächen hinweg gilt: **Lernende** ist der
  Pool, aus dem ausgewählt wird (Konto in LearningLine, gehört zu einer
  Klasse) — **Teilnehmende** sind die Leute in dieser Durchführung, in beiden
  Modi und auch ohne Konto.

  Drei Wörter sind bewusst vermieden:

  * "Angemeldet" — im Prüfungskontext heisst "anmelden" schon das Einschreiben
    ("Melde dich für die Prüfung an").
  * "Anonym" — Teilnehmende geben Vorname, Nachname und E-Mail an; anonym sind
    sie nicht. Der Unterschied ist Benutzerkonto vs. Einschreibelink, und
    genau das sagen die Titel.
  * "Zugewiesen" als Titel — ein Partizip beschreibt einen Zustand, hier ist
    aber eine Entscheidung zu treffen. Die Titel sind deshalb Verben: sie
    sagen, was die Lehrperson als Nächstes tut.
  """
  def participation_mode_options do
    [
      %{
        value: "assigned",
        label: "Lernende zuweisen",
        sublabel: "Teilnahme mit eigenem Benutzerkonto",
        state_label: "Zuweisung an Lernende",
        icon: "hero-user-group",
        summary:
          "Du wählst aus, wer die Prüfung schreibt. Die Lernenden nehmen mit ihrem eigenen Konto teil — kein Einschreibelink nötig.",
        points: [
          "Zugewiesene Lernende sehen die Prüfung auf ihrem Dashboard",
          "Nach der Korrektur kannst du die Prüfung zurückgeben",
          "Nur zugewiesene Lernende können teilnehmen"
        ]
      },
      %{
        value: "anonymous",
        label: "Einschreibelink teilen",
        sublabel: "Teilnahme ohne Benutzerkonto",
        state_label: "Einschreibelink",
        icon: "hero-link",
        summary:
          "Du teilst einen Link. Wer teilnimmt, gibt nur Vorname, Nachname und E-Mail an und braucht kein Konto in LearningLine.",
        points: [
          "Auch für Personen ohne Konto in LearningLine",
          "Die Prüfung erscheint auf keinem Dashboard",
          "Keine Rückgabe möglich — Resultate teilst du z.B. per PDF-Export"
        ]
      }
    ]
  end

  @doc "Die Option zum gegebenen Wert (fällt auf die erste zurück)."
  def participation_mode_option(value) do
    Enum.find(
      participation_mode_options(),
      hd(participation_mode_options()),
      &(&1.value == value)
    )
  end

  @doc """
  Single-Choice-Auswahl des Durchführungsmodus: links die gestapelten
  Optionskarten, rechts die Beschreibung der gewählten Option.

  `label` ist die Handlung und steht nur auf der Optionskarte. Kopfzeile und
  Readonly-Box zeigen `state_label`, die Nominalform: dort ist der Modus eine
  Feststellung, und ein Verb liest sich an diesen Stellen wie ein Button.

  Bewusst **keine** Erweiterung von `CoreComponents.radio_group/1`: der Modus
  ist kein Formularfeld (er ist nicht castable und wird nur von
  `Exams.open_exam_session/3` geschrieben), und das Beschreibungs-Panel ist
  kein Nachfahre des gecheckten `<label>` — der `has-[:checked]:`-Trick reicht
  nicht dorthin.
  """
  attr :value, :string, required: true
  attr :event, :string, default: "select_mode"
  attr :readonly, :boolean, default: false
  attr :options, :list, default: nil

  def participation_mode_picker(assigns) do
    # `assign_new/3` would not fire here: the attr default already put nil in.
    assigns =
      assigns
      |> assign(:options, assigns.options || participation_mode_options())
      |> assign(:selected, participation_mode_option(assigns.value))

    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-5 gap-5">
      <div class="md:col-span-2 space-y-2.5">
        <%= if @readonly do %>
          <div class="rounded-lg border border-stone-200 bg-stone-50 px-3.5 py-3">
            <p class="text-sm font-medium text-stone-700">{@selected.state_label}</p>
            <p class="text-xs text-stone-500 mt-0.5">{@selected.sublabel}</p>
          </div>
          <div
            class="tooltip tooltip-right tooltip-delayed"
            data-tip="Der Modus wird beim Eröffnen der Durchführung festgelegt."
          >
            <p class="inline-flex items-center gap-1.5 text-xs text-stone-400">
              <.icon name="hero-lock-closed-mini" class="w-3.5 h-3.5" />
              Nach dem Eröffnen nicht mehr änderbar
            </p>
          </div>
        <% else %>
          <label
            :for={option <- @options}
            class="flex items-start gap-3 cursor-pointer rounded-lg border border-stone-200 px-3.5 py-3 transition-colors duration-150 hover:bg-stone-50/60 has-[:checked]:border-sky-300 has-[:checked]:bg-sky-50/60"
          >
            <input
              type="radio"
              name="participation_mode"
              id={"participation-mode-#{option.value}"}
              value={option.value}
              checked={@value == option.value}
              phx-click={@event}
              phx-value-mode={option.value}
              class="mt-0.5 w-[18px] h-[18px] border-stone-300 text-sky-500 focus:ring-sky-500/30 focus:ring-offset-0 cursor-pointer shrink-0"
            />
            <span class="min-w-0">
              <span class="block text-sm font-medium text-stone-700">{option.label}</span>
              <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                {option.sublabel}
              </span>
            </span>
          </label>
        <% end %>
      </div>

      <div class="md:col-span-3 rounded-xl bg-stone-50 border border-stone-100 p-5">
        <div class="flex items-center gap-2.5 mb-3">
          <div class="w-8 h-8 rounded-lg bg-white border border-stone-200 flex items-center justify-center shrink-0">
            <.icon name={@selected.icon} class="w-4 h-4 text-sky-500" />
          </div>
          <p class="text-sm font-semibold text-stone-800">{@selected.state_label}</p>
        </div>
        <p class="text-sm text-stone-600 leading-relaxed">{@selected.summary}</p>
        <ul class="mt-4 space-y-2">
          <li :for={point <- @selected.points} class="flex items-start gap-2">
            <.icon name="hero-check-circle-mini" class="w-4 h-4 text-sky-400 shrink-0 mt-0.5" />
            <span class="text-[13px] text-stone-600 leading-relaxed">{point}</span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  @doc """
  Die vier Optionen einer Submission-Ansicht — was ein PDF-Export bzw. eine
  Rückgabe an die Teilnehmenden zeigt. Eine Quelle für beide Modals.
  """
  def submission_view_options do
    [
      %{
        key: :show_points_and_mark,
        label: "Punkte und Note anzeigen",
        description: "Zeigt die erreichte Punktzahl und die berechnete Note.",
        requires: nil
      },
      %{
        key: :show_content,
        label: "Inhalt anzeigen",
        description: "Die Antworten der Teilnehmer:in werden vollständig abgebildet.",
        requires: nil
      },
      %{
        key: :show_correction,
        label: "Korrektur anzeigen",
        description:
          "Markiert jeden Antwortblock mit einem 🟢 (richtig), 🟡 (halb richtig) oder 🔴 (falsch) Emoji. Nur verfügbar, wenn Inhalt angezeigt wird.",
        requires: :show_content
      },
      %{
        key: :show_sample_solution,
        label: "Musterlösung anzeigen",
        description: "Hängt die vollständige Musterlösung im Anschluss an.",
        requires: nil
      }
    ]
  end

  @doc """
  Eine Checkbox-Zeile eines Optionen-Modals. `event` unterscheidet Export von
  Rückgabe; das Markup ist identisch.
  """
  attr :option, :map, required: true
  attr :checked, :boolean, required: true
  attr :disabled, :boolean, default: false
  attr :event, :string, required: true

  def submission_view_option_checkbox(assigns) do
    ~H"""
    <label class={[
      "flex items-start gap-3 p-3 rounded-lg border transition-colors duration-150",
      if(@disabled,
        do: "border-stone-100 bg-stone-50/50 cursor-not-allowed opacity-60",
        else: "border-stone-200 hover:bg-stone-50/60 cursor-pointer"
      )
    ]}>
      <input
        type="checkbox"
        checked={@checked}
        disabled={@disabled}
        phx-click={@event}
        phx-value-option={@option.key}
        class="w-[18px] h-[18px] mt-0.5 rounded-md border-stone-300 text-sky-500 focus:ring-sky-500/30 focus:ring-offset-0 cursor-pointer disabled:cursor-not-allowed"
      />
      <div class="flex-1 min-w-0">
        <p class="text-sm font-semibold text-stone-800">{@option.label}</p>
        <p class="text-xs text-stone-500 mt-0.5 leading-relaxed">{@option.description}</p>
      </div>
    </label>
    """
  end
end
