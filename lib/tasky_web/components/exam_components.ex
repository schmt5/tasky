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

      <.mode_description option={@selected} />
    </div>
    """
  end

  # Das Beschreibungs-Panel neben einer Modus-Auswahl: Icon, Nominal-Titel, ein
  # Absatz und die Stichpunkte der gewählten Option.
  #
  # Erwartet eine Option in der Form von `participation_mode_options/0` bzw.
  # `answer_mode_options/0` — die beiden Listen sind deshalb gleich geformt.
  #
  # Die Spaltenbreite steckt bewusst in der Komponente: beide Picker spannen
  # dasselbe Fünfer-Grid auf, und so bleibt das Panel ein Einzeiler an der
  # Aufrufstelle.
  attr :option, :map, required: true

  defp mode_description(assigns) do
    ~H"""
    <div class="md:col-span-3 rounded-xl bg-stone-50 border border-stone-100 p-5">
      <div class="flex items-center gap-2.5 mb-3">
        <div class="w-8 h-8 rounded-lg bg-white border border-stone-200 flex items-center justify-center shrink-0">
          <.icon name={@option.icon} class="w-4 h-4 text-sky-500" />
        </div>
        <p class="text-sm font-semibold text-stone-800">{@option.state_label}</p>
      </div>
      <p class="text-sm text-stone-600 leading-relaxed">{@option.summary}</p>
      <ul class="mt-4 space-y-2">
        <li :for={point <- @option.points} class="flex items-start gap-2">
          <.icon name="hero-check-circle-mini" class="w-4 h-4 text-sky-400 shrink-0 mt-0.5" />
          <span class="text-[13px] text-stone-600 leading-relaxed">{point}</span>
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  Die beiden Prüfungsarten, in der Reihenfolge, in der sie im Erstellen-Formular
  stehen. `answer_fields` ist die Vorauswahl und bleibt der Normalfall.

  Die Titel benennen, **wohin** die lernende Person schreiben darf — das ist der
  eine Unterschied, aus dem alle anderen folgen (Werkzeugleiste, Sperre des
  Prüfungstexts, Bewertung pro Antwortfeld vs. pro Dokument).

  Bewusst nicht "Aufsatz": der freie Modus taugt auch für Protokolle, Berichte
  oder Rechnungswege. "Freies Dokument" sagt, was die Prüfung ist, statt eine
  Textsorte zu versprechen, die sie nicht erzwingt.

  Anders als der Durchführungsmodus ist das hier ein echtes Formularfeld
  (castable in `Exam.new_changeset/2`) — die Liste ist trotzdem gleich geformt
  wie `participation_mode_options/0`, damit `mode_description/1` beide
  schluckt: `sublabel` ist die kurze Zeile auf der Optionskarte, `summary` und
  `points` füllen das Panel daneben.
  """
  def answer_mode_options do
    [
      %{
        value: "answer_fields",
        label: "Antwortfelder",
        sublabel: "Lernende schreiben nur in die Antwortfelder",
        state_label: "Prüfung mit Antwortfeldern",
        icon: "hero-rectangle-group",
        summary:
          "Du stellst Fragen und setzt Antwortfelder. Lernende schreiben ausschliesslich in diese Felder — der Prüfungstext selbst ist gesperrt.",
        points: [
          "Jedes Antwortfeld wird einzeln bewertet",
          "Der Prüfungstext bleibt für Lernende gesperrt",
          "Musterlösung pro Antwortfeld möglich"
        ]
      },
      %{
        value: "free_document",
        label: "Freies Dokument",
        sublabel: "Lernende bearbeiten das ganze Dokument",
        state_label: "Freies Dokument",
        icon: "hero-document-text",
        summary:
          "Du gibst eine Aufgabenstellung vor, Lernende bearbeiten das ganze Dokument — für Aufsätze und offene Arbeiten. Keine Antwortfelder; bewertet wird das Dokument als Ganzes.",
        points: [
          "Für Aufsätze, Berichte, Protokolle oder Rechnungswege",
          "Bewertet wird das Dokument als Ganzes",
          "Keine Musterlösung — die gibt es nur mit Antwortfeldern"
        ]
      }
    ]
  end

  @doc "Die Option zum gegebenen Wert (fällt auf die erste zurück)."
  def answer_mode_option(value) do
    Enum.find(answer_mode_options(), hd(answer_mode_options()), &(&1.value == value))
  end

  @doc """
  Single-Choice-Auswahl der Prüfungsart, im selben Aufbau wie
  `participation_mode_picker/1`: links die Optionskarten, rechts die
  Beschreibung der gewählten Option.

  Anders als der Durchführungsmodus braucht die Prüfungsart kein eigenes
  Event. Sie ist ein Formularfeld, das Formular hat `phx-change`, und der neu
  gebaute Changeset trägt die Auswahl über `@field.value` zurück ins Panel.

  Die Optionskarten sind absichtlich Zeichen für Zeichen die von
  `CoreComponents.radio_group/1`, `id` und `name` eingeschlossen. Was
  `radio_group/1` nicht leisten kann, ist das Panel: es ist kein Nachfahre des
  gecheckten `<label>`, dorthin reicht `has-[:checked]:` nicht.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :legend, :string, default: nil

  def answer_mode_picker(assigns) do
    assigns = assign(assigns, :selected, answer_mode_option(assigns.field.value))

    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-5 gap-5">
      <fieldset class="md:col-span-2">
        <legend :if={@legend} class="text-sm font-medium text-stone-700 mb-2">{@legend}</legend>
        <div class="space-y-2.5">
          <label
            :for={option <- answer_mode_options()}
            class="flex items-start gap-3 cursor-pointer rounded-lg border border-stone-200 px-3.5 py-3 transition-colors duration-150 hover:bg-stone-50/60 has-[:checked]:border-sky-300 has-[:checked]:bg-sky-50/60"
          >
            <input
              type="radio"
              id={"#{@field.id}-#{option.value}"}
              name={@field.name}
              value={option.value}
              checked={to_string(@field.value) == option.value}
              class="mt-0.5 w-[18px] h-[18px] border-stone-300 text-sky-500 focus:ring-sky-500/30 focus:ring-offset-0 cursor-pointer shrink-0"
            />
            <span class="min-w-0">
              <span class="block text-sm font-medium text-stone-700">{option.label}</span>
              <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                {option.sublabel}
              </span>
            </span>
          </label>
        </div>
        <div
          class="tooltip tooltip-right tooltip-delayed mt-2.5"
          data-tip="Die Prüfungsart wird beim Erstellen festgelegt."
        >
          <p class="inline-flex items-center gap-1.5 text-xs text-stone-400">
            <.icon name="hero-lock-closed-mini" class="w-3.5 h-3.5" />
            Nach dem Erstellen nicht mehr änderbar
          </p>
        </div>
      </fieldset>

      <.mode_description option={@selected} />
    </div>
    """
  end

  @doc "True für eine Prüfung, in der Lernende das ganze Dokument bearbeiten."
  def free_document?(%{answer_mode: "free_document"}), do: true
  def free_document?(_), do: false

  @doc """
  Der Editor-Preset (`EDITOR_MODES` in `assets/js/react/editor/modes.ts`) für
  die Autoren-Fläche dieser Prüfung.

  Im freien Modus teilen sich Lehrperson und Lernende denselben Preset — den
  Unterschied macht allein `uploadImage`, das nur der Autoren-Hook mitgibt.
  """
  def author_editor_mode(exam), do: if(free_document?(exam), do: "freeDocument", else: "author")

  @doc "Der Editor-Preset für die Schreibfläche der lernenden Person."
  def student_editor_mode(exam), do: if(free_document?(exam), do: "freeDocument", else: "student")

  @doc """
  Die Optionen einer Submission-Ansicht — was ein PDF-Export bzw. eine Rückgabe
  an die Teilnehmenden zeigt. Eine Quelle für beide Modals.

  Im freien Modus fällt „Musterlösung anzeigen“ weg: eine Musterlösung wird über
  Antwortfelder erfasst, und die gibt es dort nicht — die Option hätte immer
  eine leere Seite angehängt. „Korrektur anzeigen“ bleibt, beschreibt dort aber
  die Anmerkungen der Lehrperson statt der Antwortblock-Emoji.
  """
  def submission_view_options(exam) do
    free? = free_document?(exam)

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
          if(free?,
            do:
              "Zeigt die korrigierte Fassung mit den Anmerkungen der Lehrperson. Nur verfügbar, wenn Inhalt angezeigt wird.",
            else:
              "Markiert jeden Antwortblock mit einem 🟢 (richtig), 🟡 (halb richtig) oder 🔴 (falsch) Emoji. Nur verfügbar, wenn Inhalt angezeigt wird."
          ),
        requires: :show_content
      }
    ] ++
      if free? do
        []
      else
        [
          %{
            key: :show_sample_solution,
            label: "Musterlösung anzeigen",
            description:
              "Zeigt die Musterlösung direkt unter jedem Antwortfeld. Ohne angezeigten Inhalt hängt sie als eigenes Dokument an.",
            requires: nil
          }
        ]
      end
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

  @doc """
  Exam-day alarm: the SEB Config Key cannot be derived, so nobody is being
  verified — and, deliberately, nobody is being blocked either.

  `TaskyWeb.SebGuard.mode/1` degrades `enforce` to `observe` in this state,
  because a bug of ours must not end a graded exam for a whole class. That
  trade is only defensible if the teacher knows it happened, which is what this
  is for.
  """
  attr :message, :string, required: true

  def seb_derivation_alert(assigns) do
    ~H"""
    <div id="seb-derivation-error" class="bg-red-50 rounded-[14px] border border-red-200 p-5 mb-6">
      <div class="flex items-start gap-3">
        <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-500 shrink-0" />
        <div class="min-w-0">
          <h2 class="text-base font-semibold text-red-800 mb-1">
            Die SEB-Prüfung ist ausgefallen
          </h2>
          <p class="text-sm text-red-700 leading-relaxed">
            Der erwartete SEB-Schlüssel kann auf diesem Server nicht berechnet werden.
            Die Prüfung läuft <span class="font-semibold">normal weiter</span> — aber es wird
            niemand verifiziert und niemand blockiert, auch unter «Erzwingen» nicht.
            Die Aufsicht im Raum ist damit die einzige Kontrolle. Bitte diese Meldung
            weitergeben.
          </p>
          <p class="mt-2 font-mono text-xs text-red-600 break-all select-all">{@message}</p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Das SEB-Gate: die Seite, die statt der Prüfung erscheint, solange der Safe
  Exam Browser nicht nachgewiesen ist.

  Eine Komponente und nicht zwei Kopien, weil sie an zwei strukturell
  verschiedenen Stellen gerendert wird: als `cond`-Zweig in
  `TaskyWeb.Guest.ExamLive` (Teilnehmer:in ist noch im normalen Browser und
  soll die Konfiguration herunterladen) und als 403 aus
  `TaskyWeb.Plugs.SebGuard` heraus (ein Request, der die Prüfung ohne gültigen
  SEB-Nachweis anfassen wollte). Beide müssen dasselbe sagen, sonst wird der
  Probelauf unlesbar.

  `reason` unterscheidet die beiden Fälle, die im Betrieb ganz verschiedene
  Ursachen haben:

  * `:no_header` — SEB läuft (noch) nicht. Normalfall vor dem Start.
  * `:mismatch` — SEB läuft, meldet aber eine andere Konfiguration. Praktisch
    immer eine veraltete `.seb`-Datei, weil die Konfiguration nach dem
    Herunterladen geändert wurde.
  """
  attr :exam_token, :string, required: true
  attr :reason, :atom, default: :no_header

  def seb_gate(assigns) do
    ~H"""
    <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
      <div class="w-full max-w-lg">
        <div class="text-center mb-8">
          <div class="w-16 h-16 rounded-2xl bg-sky-50 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-shield-check" class="w-8 h-8 text-sky-500" />
          </div>
          <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
            Safe Exam Browser erforderlich
          </h1>
          <p class="text-stone-500 text-sm">
            Diese Prüfung erfordert den Safe Exam Browser (SEB).
          </p>
        </div>

        <div class="bg-white rounded-2xl border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-6 space-y-4">
          <div :if={@reason == :mismatch} class="bg-amber-50 rounded-xl p-4 border border-amber-100">
            <div class="flex items-start gap-3">
              <.icon
                name="hero-exclamation-triangle"
                class="w-5 h-5 text-amber-500 shrink-0 mt-0.5"
              />
              <div class="text-sm text-amber-800 leading-relaxed">
                <p class="font-semibold mb-1">Die Konfiguration passt nicht.</p>
                <p>
                  Der Safe Exam Browser läuft, meldet aber eine andere Konfiguration
                  als diese Prüfung erwartet. Lade die Konfigurationsdatei unten neu
                  herunter und starte den Safe Exam Browser damit erneut. Wenn das
                  nicht hilft, melde dich bei deiner Lehrperson.
                </p>
              </div>
            </div>
          </div>

          <div :if={@reason != :mismatch} class="bg-sky-50 rounded-xl p-4 border border-sky-100">
            <div class="flex items-start gap-3">
              <.icon name="hero-information-circle" class="w-5 h-5 text-sky-500 shrink-0 mt-0.5" />
              <div class="text-sm text-sky-800 leading-relaxed">
                <p class="mb-1">
                  Der Safe Exam Browser sperrt deinen Computer während der Prüfung
                  in einen sicheren Kiosk-Modus.
                </p>
                <p>
                  Der Safe Exam Browser muss bereits installiert sein. Falls nicht,
                  installiere ihn zuerst.
                </p>
              </div>
            </div>
          </div>

          <ol class="space-y-3">
            <li class="flex items-start gap-3">
              <span class="shrink-0 w-6 h-6 rounded-full bg-sky-100 text-sky-700 text-xs font-semibold flex items-center justify-center mt-0.5">
                1
              </span>
              <p class="text-sm text-stone-600 leading-relaxed">
                Klicke auf den Button <span class="font-semibold text-stone-800">«Im Safe Exam Browser öffnen»</span>.
              </p>
            </li>
            <li class="flex items-start gap-3">
              <span class="shrink-0 w-6 h-6 rounded-full bg-sky-100 text-sky-700 text-xs font-semibold flex items-center justify-center mt-0.5">
                2
              </span>
              <p class="text-sm text-stone-600 leading-relaxed">
                Es wird eine Konfigurationsdatei
                (<span class="font-semibold text-stone-800">exam.seb</span>) heruntergeladen.
              </p>
            </li>
            <li class="flex items-start gap-3">
              <span class="shrink-0 w-6 h-6 rounded-full bg-sky-100 text-sky-700 text-xs font-semibold flex items-center justify-center mt-0.5">
                3
              </span>
              <p class="text-sm text-stone-600 leading-relaxed">
                Öffne die heruntergeladene Datei mit einem Klick und warte einige Sekunden –
                der Safe Exam Browser startet automatisch.
              </p>
            </li>
          </ol>

          <a
            href={"/guest/exam/#{@exam_token}/seb-config"}
            id="open-in-seb-btn"
            class="w-full inline-flex items-center justify-center gap-2.5 bg-sky-500 text-white text-sm font-semibold px-6 py-3.5 rounded-xl shadow-[0_2px_12px_rgba(14,165,233,0.3)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
          >
            <.icon name="hero-shield-check" class="w-5 h-5" /> Im Safe Exam Browser öffnen
          </a>
        </div>
      </div>
    </div>
    """
  end
end
