defmodule TaskyWeb.SampleSolutionComponents do
  @moduledoc """
  The «Musterlösung» tab of an exam and of a learning unit, built from the same
  parts so both look and behave alike: one editor per question (h3) under a
  shared toolbar, a sticky card beside it, and the «Korrekturoptionen» dialog.

  `kind` tells the two apart where they must differ: an exam question has
  points and is corrected by the teacher, a learning-unit question has neither
  and checks itself (`Tasky.Tasks.SelfCheck`). The options themselves are the
  same (`Tasky.Correction.PartConfig`).

  The LiveViews keep their own draft handling; `merge_option_flags/2` and
  `options_config/1` are the parts of it that must not differ.
  """
  use TaskyWeb, :html

  @doc "The question view's fields the card and the dialog read, from its answer blocks."
  def block_flags(blocks) do
    %{
      has_text_answers: Enum.any?(blocks, &(&1.type in ["answerBlock", "lueckentext"])),
      has_checkboxes: Enum.any?(blocks, &(&1.type == "taskItem")),
      has_pin_image: Enum.any?(blocks, &(&1.type == "imagePin"))
    }
  end

  @doc """
  The audio blocks of a question, as the card names them. Read from the
  content: title and limit are set there, the sample solution only shows them.
  """
  def audio_summaries(nodes) do
    for node <- Tasky.AudioPlays.list(%{"content" => nodes}) do
      title =
        case node["attrs"]["title"] do
          title when is_binary(title) and title != "" -> title
          _ -> "Audio"
        end

      limit =
        case Tasky.AudioPlays.max_plays(node) do
          nil -> "beliebig oft abspielbar"
          max -> "höchstens #{max}× abspielbar"
        end

      %{id: node["attrs"]["audioId"], title: title, limit: limit}
    end
  end

  @doc """
  Folds the dialog's flag params into the draft: the text options go with
  auto-correction, as `Tasky.Correction.PartConfig.put/4` stores them.
  """
  def merge_option_flags(draft, params) do
    auto? = flag_param(params, "auto_correct", draft.auto_correct)

    %{
      draft
      | auto_correct: auto?,
        ignore_case: auto? and flag_param(params, "ignore_case", draft.ignore_case),
        ignore_spelling: auto? and flag_param(params, "ignore_spelling", draft.ignore_spelling),
        ignore_punctuation:
          auto? and flag_param(params, "ignore_punctuation", draft.ignore_punctuation),
        checkbox_rule: Map.get(params, "checkbox_rule", draft.checkbox_rule)
    }
  end

  defp flag_param(params, key, default) do
    case Map.fetch(params, key) do
      {:ok, value} -> value == "true"
      :error -> default
    end
  end

  @doc """
  The config the dialog saves. A question of only ticks shows no
  auto-correction switch, so its stored flag stays as it is — a text field
  added later falls back to it.
  """
  def options_config(draft) do
    config = %{
      "auto_correct" => draft.auto_correct,
      "ignore_case" => draft.ignore_case,
      "ignore_spelling" => draft.ignore_spelling,
      "ignore_punctuation" => draft.ignore_punctuation,
      "checkbox_scoring" => draft.checkbox_rule
    }

    if draft.choice_only, do: Map.delete(config, "auto_correct"), else: config
  end

  @doc """
  The text comparison options of a question, in display order. Keys match the
  question view and the stored config (see
  `Tasky.Correction.StringComparator.match_opts/1`).
  """
  def text_options do
    [
      {:ignore_case, "Gross-/Kleinschreibung ignorieren",
       "Beim Vergleich mit der Musterlösung wird Gross-/Kleinschreibung nicht bewertet."},
      {:ignore_punctuation, "Satzzeichen ignorieren",
       "Punkt, Komma, Ausrufe- und Fragezeichen usw. werden beim Vergleich nicht beachtet."},
      {:ignore_spelling, "Rechtschreibung ignorieren",
       "Rechtschreibfehler werden beim Vergleich nicht streng bewertet (Fuzzy-Matching ab Jaro-Ähnlichkeit ≥ 0,85)."}
    ]
  end

  @doc """
  What the card lists under «Korrekturoptionen»: the active settings by name,
  without their descriptions.
  """
  def active_option_labels(pv) do
    text =
      if pv.has_text_answers,
        do: for({key, label, _hint} <- text_options(), Map.fetch!(pv, key), do: label),
        else: []

    Enum.reject(
      [
        Map.get(pv, :custom_points) && "Punkte pro Antwortfeld",
        pv.auto_correct && "Auto-Korrektur"
      ],
      &(&1 in [nil, false])
    ) ++ text ++ checkbox_rule_summary(pv)
  end

  defp checkbox_rule_summary(%{has_checkboxes: false}), do: []

  defp checkbox_rule_summary(%{checkbox_rule: "all_or_nothing"}),
    do: ["Multiple-Choice: alles oder nichts"]

  defp checkbox_rule_summary(_pv), do: ["Multiple-Choice: pro Checkbox"]

  attr :id, :string, required: true

  @doc "The one toolbar bound to whichever question editor has focus."
  def solution_toolbar(assigns) do
    ~H"""
    <div id={@id} phx-hook="SolutionToolbar" phx-update="ignore" class="sticky top-[54px] z-30"></div>
    """
  end

  attr :id, :string, required: true
  attr :part, :map, required: true, doc: "the question view: `id`, `doc_json`"
  attr :save_url, :string, required: true
  slot :card, required: true

  @doc "One question: its sample-solution editor, and the sticky card beside it."
  def part_row(assigns) do
    ~H"""
    <div class="grid grid-cols-4 gap-6 items-stretch mb-10">
      <div class="col-span-3 min-w-0">
        <div
          id={@id}
          phx-hook="SampleSolutionPartEditor"
          phx-update="ignore"
          data-part-id={@part.id}
          data-save-url={@save_url}
          data-content={@part.doc_json}
          class="h-full"
        >
        </div>
      </div>

      <%!-- top offset: 54px header + shared toolbar height --%>
      <aside class="col-span-1 self-start sticky top-[180px]">
        <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-5 border-b border-stone-100">
            <h2 class="text-base font-semibold text-stone-800 truncate">{@part.label}</h2>
            <p class="text-xs text-stone-500 mt-1">Musterlösung</p>
            <button
              type="button"
              phx-click="open_alternatives_help"
              class="block w-full text-left mt-2 text-xs font-medium text-stone-500 hover:text-stone-700 hover:underline underline-offset-2 cursor-pointer transition-colors duration-150"
            >
              Mehrere Musterlösungen pro Antwortfeld
            </button>
          </div>
          {render_slot(@card)}
        </div>
      </aside>
    </div>
    """
  end

  attr :part, :map, required: true
  attr :class, :string, default: "p-5 border-t border-stone-100"

  @doc "The «Korrekturoptionen» button of a question card, with its active options."
  def options_summary(assigns) do
    assigns = assign(assigns, :labels, active_option_labels(assigns.part))

    ~H"""
    <div class={@class}>
      <button
        type="button"
        id={"correction-options-btn-#{@part.id}"}
        phx-click="open_correction_options"
        phx-value-part-id={@part.id}
        class="w-full inline-flex items-center justify-center gap-2 text-sm font-semibold text-stone-700 bg-white border border-stone-200 hover:bg-stone-50 hover:border-stone-300 px-4 py-2.5 rounded-lg transition-colors duration-150 active:scale-[0.98]"
      >
        <.icon name="hero-adjustments-horizontal" class="w-4 h-4" /> Korrekturoptionen
      </button>

      <ul id={"correction-options-summary-#{@part.id}"} class="mt-4 space-y-1.5">
        <li :for={label <- @labels} class="flex items-center gap-2 text-xs text-stone-600">
          <.icon name="hero-check-circle" class="w-4 h-4 text-stone-400 shrink-0" />
          <span class="min-w-0">{label}</span>
        </li>
        <li :if={@labels == []} class="text-xs text-stone-400">
          Keine Korrekturoptionen aktiv
        </li>
      </ul>
    </div>
    """
  end

  attr :part, :map, required: true
  attr :content_path, :string, required: true, doc: "the «Inhalt» tab, where audio is set"

  @doc """
  The audio blocks of a question: what learners get, set in «Inhalt» (the
  sample solution cannot change the text).
  """
  def audio_summary(assigns) do
    ~H"""
    <div
      :if={@part.audios != []}
      id={"audio-summary-#{@part.id}"}
      class="p-5 border-t border-stone-100"
    >
      <h3 class="text-xs font-semibold text-stone-500 uppercase tracking-wide mb-2">
        Audio
      </h3>
      <ul class="space-y-1.5">
        <li :for={audio <- @part.audios} class="flex items-start gap-2 text-xs text-stone-600">
          <.icon name="hero-speaker-wave" class="w-4 h-4 text-stone-400 shrink-0" />
          <span class="min-w-0">
            <span class="font-medium text-stone-700">{audio.title}</span> · {audio.limit}
          </span>
        </li>
      </ul>
      <.link
        patch={@content_path}
        class="inline-block mt-2 text-xs font-medium text-sky-700 hover:text-sky-800 hover:underline underline-offset-2 transition-colors duration-150"
      >
        Im Inhalt ändern
      </.link>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :part, :map, required: true

  @doc """
  The pins of the question's pin image: a React island bound to the part
  editor beside it (assets/js/react/PinPanel.jsx).
  """
  def pin_panel(assigns) do
    ~H"""
    <div
      :if={@part.has_pin_image}
      id={@id}
      phx-hook="PinPanel"
      phx-update="ignore"
      data-part-id={@part.id}
      class="p-5 border-t border-stone-100"
    >
    </div>
    """
  end

  attr :kind, :atom, values: [:exam, :task], required: true
  attr :draft, :map, required: true
  attr :form, Phoenix.HTML.Form, required: true
  slot :points, doc: "the exam's points section, above the auto-correction"

  @doc """
  The «Korrekturoptionen» dialog for whichever question it was opened for. It
  edits a draft; nothing is saved before «Übernehmen».
  """
  def correction_options_dialog(assigns) do
    ~H"""
    <dialog
      id="correction-options-modal"
      class="modal modal-open"
      phx-window-keydown="close_correction_options"
      phx-key="escape"
    >
      <div class="modal-backdrop bg-stone-900/50" phx-click="close_correction_options"></div>
      <div class="modal-box max-w-2xl p-0 bg-white rounded-[16px] shadow-2xl">
        <div class="px-6 py-5 border-b border-stone-100 flex items-center justify-between gap-4">
          <div class="flex items-center gap-3 min-w-0">
            <div class="w-9 h-9 rounded-xl bg-violet-50 flex items-center justify-center text-violet-600 shrink-0">
              <.icon name="hero-adjustments-horizontal" class="w-5 h-5" />
            </div>
            <div class="min-w-0">
              <h3 class="text-lg font-semibold text-stone-900">Korrekturoptionen</h3>
              <p class="text-xs text-stone-500 truncate">{@draft.label}</p>
            </div>
          </div>
          <button
            type="button"
            phx-click="close_correction_options"
            aria-label="Schliessen"
            class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-400 hover:bg-stone-100 hover:text-stone-600 transition-colors duration-150"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <.form
          for={@form}
          id={"correction-options-form-#{@draft.part_id}"}
          phx-change="change_correction_options"
          phx-submit="apply_correction_options"
        >
          <div class="px-6 py-5 space-y-6 max-h-[65vh] overflow-y-auto">
            {render_slot(@points)}

            <section class={["space-y-3", @points != [] && "pt-5 border-t border-stone-100"]}>
              <h4 class="text-xs font-semibold text-stone-500 uppercase tracking-wide">
                Auto-Korrektur
              </h4>
              <p
                :if={@draft.choice_only}
                id="auto-correct-always-note"
                class="flex items-start gap-2 text-sm text-stone-600 leading-relaxed"
              >
                <.icon
                  name="hero-check-circle"
                  class="w-[18px] h-[18px] text-violet-500 shrink-0 mt-0.5"
                />
                <span>
                  {choice_kinds(@draft)} werden immer automatisch korrigiert.
                  <%= if @kind == :exam do %>
                    Du kannst jede Bewertung weiterhin von Hand ändern.
                  <% end %>
                </span>
              </p>
              <.option_toggle
                :if={!@draft.choice_only}
                field={@form[:auto_correct]}
                label="Auto-Korrektur"
                hint={auto_correct_hint(@kind)}
              />
              <%= if @draft.has_text_answers do %>
                <p
                  :if={@draft.has_checkboxes}
                  id="text-options-note"
                  class="text-xs text-stone-500 leading-relaxed pl-7"
                >
                  Die folgenden Optionen gelten nur für Textantworten, nicht für Multiple-Choice.
                </p>
                <div class="pl-7 space-y-3">
                  <.option_toggle
                    :for={{key, label, hint} <- text_options()}
                    field={@form[key]}
                    label={label}
                    hint={hint}
                    disabled={!@draft.auto_correct}
                  />
                </div>
              <% end %>
            </section>

            <section
              :if={@draft.has_checkboxes}
              id="checkbox-scoring"
              class="space-y-3 pt-5 border-t border-stone-100"
            >
              <div>
                <h4 class="text-xs font-semibold text-stone-500 uppercase tracking-wide">
                  {if @kind == :exam, do: "Punkte bei Multiple-Choice", else: "Multiple-Choice"}
                </h4>
                <p class="text-xs text-stone-500 mt-1 leading-relaxed">
                  {checkbox_scoring_hint(@kind)}
                </p>
              </div>
              <.input type="hidden" field={@form[:checkbox_rule]} />
              <div class="grid grid-cols-2 gap-2" role="radiogroup">
                <button
                  :for={{rule, label, hint} <- checkbox_rule_options(@kind)}
                  type="button"
                  id={"checkbox-scoring-#{rule}"}
                  role="radio"
                  aria-checked={to_string(@draft.checkbox_rule == rule)}
                  phx-click="draft_checkbox_rule"
                  phx-value-rule={rule}
                  class={[
                    "flex flex-col gap-1 rounded-lg border px-3 py-2.5 text-left transition-colors duration-150",
                    if(@draft.checkbox_rule == rule,
                      do: "border-violet-400 bg-violet-50/60",
                      else: "border-stone-200 bg-white hover:bg-stone-50 hover:border-stone-300"
                    )
                  ]}
                >
                  <span class="text-sm font-medium text-stone-700">{label}</span>
                  <span class="text-xs text-stone-500 leading-relaxed">{hint}</span>
                </button>
              </div>
            </section>
          </div>

          <div class="px-6 py-4 border-t border-stone-100 flex items-center justify-end gap-3">
            <button
              type="button"
              phx-click="close_correction_options"
              class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
            >
              Abbrechen
            </button>
            <button
              type="submit"
              id="apply-correction-options-btn"
              class="inline-flex items-center gap-2 bg-violet-600 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(124,58,237,0.25)] transition-all duration-150 hover:bg-violet-700 active:scale-[0.98]"
            >
              <.icon name="hero-check" class="w-4 h-4" /> Übernehmen
            </button>
          </div>
        </.form>
      </div>
    </dialog>
    """
  end

  defp auto_correct_hint(:exam),
    do: "Diese Aufgabe wird beim Start der Auto-Korrektur automatisch bewertet."

  defp auto_correct_hint(:task),
    do:
      "Die Textantworten dieser Aufgabe werden nach der Freigabe mit der Musterlösung verglichen."

  defp checkbox_scoring_hint(:exam),
    do:
      "Gilt für die Auto-Korrektur und die Korrektur von Hand. Manuelle Punkte bleiben immer möglich."

  defp checkbox_scoring_hint(:task),
    do: "Bestimmt, wie Checkbox-Listen in der Selbstkontrolle zählen."

  defp checkbox_rule_options(:exam) do
    [
      {"per_checkbox", "Pro Checkbox",
       "Jede richtig angekreuzte oder richtig leer gelassene Checkbox gibt ihren Anteil der Punkte."},
      {"all_or_nothing", "Alles oder nichts",
       "Volle Punkte nur, wenn alle Checkboxen stimmen, sonst 0."}
    ]
  end

  defp checkbox_rule_options(:task) do
    [
      {"per_checkbox", "Pro Checkbox", "Jede Checkbox zählt für sich als richtig oder falsch."},
      {"all_or_nothing", "Alles oder nichts",
       "Eine Liste zählt nur als richtig, wenn alle ihre Checkboxen stimmen."}
    ]
  end

  # The kinds of tick questions in a question of only ticks, as the note names them.
  defp choice_kinds(draft) do
    types = MapSet.new(draft.blocks, & &1.type)

    case {"taskItem" in types, "choice" in types} do
      {true, true} -> "Multiple-Choice- und Single-Choice-Aufgaben"
      {true, false} -> "Multiple-Choice-Aufgaben"
      {false, true} -> "Single-Choice-Aufgaben"
      _ -> "Ankreuzaufgaben"
    end
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :hint, :string, required: true
  attr :disabled, :boolean, default: false

  @doc "A checkbox with its description underneath, for the options dialog."
  def option_toggle(assigns) do
    ~H"""
    <div class={["flex items-start gap-3", @disabled && "opacity-40"]}>
      <div class="pt-0.5">
        <.input
          field={@field}
          type="checkbox"
          disabled={@disabled}
          class="w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150 shrink-0 disabled:cursor-not-allowed"
        />
      </div>
      <label
        for={@field.id}
        class={["min-w-0", if(@disabled, do: "cursor-not-allowed", else: "cursor-pointer")]}
      >
        <span class="block text-sm font-medium text-stone-700">{@label}</span>
        <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">{@hint}</span>
      </label>
    </div>
    """
  end

  attr :kind, :atom, values: [:exam, :task], required: true

  @doc """
  The explanation of `;` between alternative answers. Rendered once outside
  the question loop, so the cards share one `<dialog>`.
  """
  def alternatives_help_dialog(assigns) do
    ~H"""
    <dialog
      id="alternatives-help-modal"
      class="modal modal-open"
      phx-window-keydown="close_alternatives_help"
      phx-key="escape"
    >
      <div class="modal-backdrop bg-stone-900/50" phx-click="close_alternatives_help"></div>
      <div class="modal-box max-w-lg p-0 bg-white rounded-[16px] shadow-2xl">
        <div class="px-6 py-5 border-b border-stone-100 flex items-center justify-between gap-4">
          <div class="flex items-center gap-3 min-w-0">
            <div class="w-9 h-9 rounded-xl bg-sky-50 flex items-center justify-center text-sky-600 shrink-0">
              <.icon name="hero-information-circle" class="w-5 h-5" />
            </div>
            <h3 class="text-lg font-semibold text-stone-900">
              Mehrere Musterlösungen pro Antwortfeld
            </h3>
          </div>
          <button
            type="button"
            phx-click="close_alternatives_help"
            aria-label="Schliessen"
            class="inline-flex items-center justify-center w-8 h-8 rounded-lg text-stone-400 hover:text-stone-600 hover:bg-stone-100 transition-colors duration-150 cursor-pointer shrink-0"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <div class="px-6 py-5 space-y-4">
          <p class="text-sm text-stone-600 leading-relaxed">
            Ein Antwortfeld kann mehrere gültige Antworten haben. Trenne sie in der
            Musterlösung mit einem Semikolon.
          </p>

          <div class="rounded-xl border border-stone-200 bg-stone-50/70 px-4 py-3.5 space-y-2">
            <div>
              <p class="text-xs font-semibold text-stone-500 uppercase tracking-wide">Frage</p>
              <p class="text-sm text-stone-700 mt-0.5">
                Nenne ein Synonym für „schnell“.
              </p>
            </div>
            <div>
              <p class="text-xs font-semibold text-stone-500 uppercase tracking-wide">
                Musterlösung
              </p>
              <p class="font-mono text-sm text-violet-600 mt-0.5">
                rasch; flink; zügig; geschwind
              </p>
            </div>
            <p class="text-xs text-stone-500 leading-relaxed pt-1">
              Jede dieser vier Eingaben zählt als richtig.
            </p>
          </div>

          <ul class="text-sm text-stone-600 space-y-2 leading-relaxed">
            <li class="flex gap-2">
              <span class="text-stone-400 shrink-0">•</span>
              <span>
                Gilt für <span class="font-medium text-stone-700">Antwortfelder</span>
                und <span class="font-medium text-stone-700">Lückentextfelder</span>
                – nicht für Multiple-Choice und Single-Choice.
              </span>
            </li>
            <li class="flex gap-2">
              <span class="text-stone-400 shrink-0">•</span>
              <span :if={@kind == :exam}>
                Wirkt bei der Auto-Korrektur und als Vorschlag in der Korrektur nach Frage.
                Du kannst jede Bewertung weiterhin überschreiben.
              </span>
              <span :if={@kind == :task}>
                Wirkt bei der Selbstkontrolle, die Lernende nach der Freigabe sehen.
              </span>
            </li>
            <li class="flex gap-2">
              <span class="text-stone-400 shrink-0">•</span>
              <span>
                Jede Alternative wird mit denselben Regeln geprüft wie eine einzelne
                Musterlösung – auch „Gross-/Kleinschreibung ignorieren“,
                „Satzzeichen ignorieren“ und „Rechtschreibung ignorieren“.
              </span>
            </li>
            <li class="flex gap-2">
              <span class="text-stone-400 shrink-0">•</span>
              <span>
                Leerzeichen rund um die Alternativen und leere Abschnitte werden ignoriert.
              </span>
            </li>
            <li class="flex gap-2">
              <span class="text-stone-400 shrink-0">•</span>
              <span>
                Teilnehmende sehen das Semikolon nie. Wird ihnen die Musterlösung gezeigt,
                steht dort <span class="font-medium text-stone-700">„rasch, flink, zügig,
                geschwind"</span>.
              </span>
            </li>
            <li class="flex gap-2">
              <span class="text-stone-400 shrink-0">•</span>
              <span>
                Das Semikolon ist das Trennzeichen: eine Antwort, die selbst ein Semikolon
                enthält, lässt sich so nicht abbilden.
              </span>
            </li>
          </ul>
        </div>

        <div class="px-6 py-4 border-t border-stone-100 flex items-center justify-end">
          <button
            type="button"
            phx-click="close_alternatives_help"
            class="bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] cursor-pointer"
          >
            Verstanden
          </button>
        </div>
      </div>
    </dialog>
    """
  end
end
