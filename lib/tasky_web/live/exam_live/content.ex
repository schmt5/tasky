defmodule TaskyWeb.ExamLive.Content do
  use TaskyWeb, :live_view

  import TaskyWeb.FileComponents

  import TaskyWeb.ContentComponents,
    only: [
      tab_link: 1,
      upload_field_form: 1,
      new_field_draft: 0,
      presence: 1,
      put_draft_error: 5
    ]

  alias Tasky.Exams
  alias Tasky.Uploads
  alias TaskyWeb.ExamComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/exams/#{@exam}/content"}
    >
      <%!-- Page Header --%>
      <div
        id="content-page-header"
        phx-hook="StickyShadow"
        class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 h-[54px] flex items-center transition-shadow duration-200"
      >
        <div class="max-w-7xl mx-auto w-full flex items-center justify-between gap-4">
          <div class="flex items-center gap-2 min-w-0">
            <.back_button
              navigate={~p"/exams/#{@exam}"}
              tooltip={"Zurück zu #{@exam.name}"}
              size="sm"
            />
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Bearbeiten"}
            ]} />
          </div>

          <div class="inline-flex items-center gap-0.5 bg-sky-100/70 rounded-lg p-0.5">
            <.tab_link
              label="Inhalt"
              active={@tab == "inhalt"}
              patch={~p"/exams/#{@exam}/content?tab=inhalt"}
            />
            <.tab_link
              label={solution_tab_label(@free_document)}
              active={@tab == "musterloesung"}
              patch={~p"/exams/#{@exam}/content?tab=musterloesung"}
            />
            <.tab_link
              label="Dateien"
              active={@tab == "dateien"}
              patch={~p"/exams/#{@exam}/content?tab=dateien"}
            />
          </div>
        </div>
      </div>

      <%!-- Inhalt tab: full-width editor flush under the header --%>
      <div :if={@tab == "inhalt"} class="min-w-0">
        <div
          id={"exam-content-editor-#{@exam.id}"}
          phx-hook="ExamContentEditor"
          phx-update="ignore"
          data-exam-id={@exam.id}
          data-editor-mode={ExamComponents.author_editor_mode(@exam)}
          data-content={@content_json}
        >
        </div>
      </div>

      <%!-- Musterlösung tab --%>
      <div :if={@tab == "musterloesung"} class="bg-stone-100 min-h-[calc(100vh-54px)]">
        <%!-- Shared toolbar: one bar bound to the focused part editor --%>
        <div
          :if={@part_views != [] and not @free_document}
          id={"solution-toolbar-#{@exam.id}"}
          phx-hook="SolutionToolbar"
          phx-update="ignore"
          class="sticky top-[54px] z-30"
        >
        </div>

        <div class="max-w-7xl mx-auto px-8 py-6">
          <%!-- Freies Dokument: keine Fragen, keine Antwortfelder — also auch
               keine Musterlösung. Zu bestimmen bleibt genau eine Zahl: wie viele
               Punkte das Dokument als Ganzes wert ist. --%>
          <div :if={@free_document} class="max-w-md">
            <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
              <div class="p-5 border-b border-stone-100">
                <h2 class="text-base font-semibold text-stone-800">Punkte</h2>
                <p class="text-xs text-stone-500 mt-1">
                  Lernende bearbeiten das ganze Dokument, deshalb wird es als Ganzes bewertet.
                  Die Punkte vergibst du in der Korrektur.
                </p>
              </div>
              <div :for={pv <- @part_views} class="p-5">
                <label class="block text-xs font-semibold text-stone-500 uppercase tracking-wide mb-2">
                  Max. Punkte
                </label>
                <div class="flex items-center gap-1.5">
                  <.step_button
                    direction="up"
                    phx-click="adjust_max_points"
                    phx-value-part-id={pv.id}
                  />
                  <form phx-change="set_max_points" phx-submit="set_max_points" class="flex-1">
                    <input type="hidden" name="part_id" value={pv.id} />
                    <input
                      type="number"
                      name="points"
                      value={pv.max_points || ""}
                      step="0.25"
                      min="0"
                      inputmode="decimal"
                      phx-debounce="500"
                      placeholder="—"
                      class={points_input_class()}
                    />
                  </form>
                  <.step_button
                    direction="down"
                    phx-click="adjust_max_points"
                    phx-value-part-id={pv.id}
                    disabled={is_nil(pv.max_points) or pv.max_points <= 0}
                  />
                </div>
              </div>
            </div>
          </div>

          <div
            :if={@part_views == [] and not @free_document}
            class="flex flex-col items-center justify-center text-center py-24"
          >
            <div class="flex items-center justify-center w-14 h-14 rounded-2xl bg-stone-100 text-stone-400 mb-4">
              <.icon name="hero-document-text" class="w-7 h-7" />
            </div>
            <h3 class="text-base font-semibold text-stone-700">Noch keine Frage vorhanden</h3>
            <p class="text-sm text-stone-500 mt-1.5 max-w-md leading-relaxed">
              Lege zuerst im Tab <span class="font-medium text-stone-600">„Inhalt“</span>
              eine Frage (Überschrift) an, um hier die Musterlösung zu erfassen.
            </p>
          </div>

          <div
            :for={pv <- @part_views}
            :if={not @free_document}
            class="grid grid-cols-4 gap-6 items-stretch mb-10"
          >
            <div class="col-span-3 min-w-0">
              <div
                id={"sample-solution-part-editor-#{@exam.id}-#{pv.id}"}
                phx-hook="ExamSampleSolutionPartEditor"
                phx-update="ignore"
                data-exam-id={@exam.id}
                data-part-id={pv.id}
                data-content={pv.doc_json}
                class="h-full"
              >
              </div>
            </div>

            <%!-- top offset: 54px header + shared toolbar height --%>
            <aside class="col-span-1 self-start sticky top-[180px]">
              <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
                <div class="p-5 border-b border-stone-100">
                  <h2 class="text-base font-semibold text-stone-800 truncate">{pv.label}</h2>
                  <p class="text-xs text-stone-500 mt-1">Musterlösung</p>
                  <button
                    type="button"
                    phx-click="open_alternatives_help"
                    class="block w-full text-left mt-2 text-xs font-medium text-stone-500 hover:text-stone-700 hover:underline underline-offset-2 cursor-pointer transition-colors duration-150"
                  >
                    Mehrere Musterlösungen pro Antwortfeld
                  </button>
                </div>

                <div class="p-5">
                  <label class="block text-xs font-semibold text-stone-500 uppercase tracking-wide mb-2">
                    Max. Punkte
                  </label>
                  <div :if={!pv.custom_points} class="flex items-center gap-1.5">
                    <.step_button
                      direction="up"
                      phx-click="adjust_max_points"
                      phx-value-part-id={pv.id}
                    />
                    <form phx-change="set_max_points" phx-submit="set_max_points" class="flex-1">
                      <input type="hidden" name="part_id" value={pv.id} />
                      <input
                        type="number"
                        name="points"
                        value={pv.max_points || ""}
                        step="0.25"
                        min="0"
                        inputmode="decimal"
                        phx-debounce="500"
                        placeholder="—"
                        class={points_input_class()}
                      />
                    </form>
                    <.step_button
                      direction="down"
                      phx-click="adjust_max_points"
                      phx-value-part-id={pv.id}
                      disabled={is_nil(pv.max_points) or pv.max_points <= 0}
                    />
                  </div>
                  <div
                    :if={pv.custom_points}
                    class="font-mono text-base text-center text-stone-800 bg-stone-100 border border-stone-200 rounded-lg px-3 py-2"
                  >
                    {format_block_points(pv.max_points)}
                  </div>
                  <p :if={pv.custom_points} class="text-xs text-stone-500 mt-1.5 leading-relaxed">
                    Summe der Punkte pro Antwortfeld.
                  </p>
                </div>

                <div class="p-5 border-t border-stone-100">
                  <button
                    type="button"
                    id={"correction-options-btn-#{pv.id}"}
                    phx-click="open_correction_options"
                    phx-value-part-id={pv.id}
                    class="w-full inline-flex items-center justify-center gap-2 text-sm font-semibold text-stone-700 bg-white border border-stone-200 hover:bg-stone-50 hover:border-stone-300 px-4 py-2.5 rounded-lg transition-colors duration-150 active:scale-[0.98]"
                  >
                    <.icon name="hero-adjustments-horizontal" class="w-4 h-4" /> Korrekturoptionen
                  </button>

                  <ul id={"correction-options-summary-#{pv.id}"} class="mt-4 space-y-1.5">
                    <li
                      :for={label <- active_option_labels(pv)}
                      class="flex items-center gap-2 text-xs text-stone-600"
                    >
                      <.icon name="hero-check-circle" class="w-4 h-4 text-stone-400 shrink-0" />
                      <span class="min-w-0">{label}</span>
                    </li>
                    <li :if={active_option_labels(pv) == []} class="text-xs text-stone-400">
                      Keine Korrekturoptionen aktiv
                    </li>
                  </ul>
                </div>
              </div>
            </aside>
          </div>
        </div>

        <%!-- Korrekturoptionen: one dialog for whichever question it was opened
             for. It edits a draft; nothing is saved before "Übernehmen". --%>
        <%= if @options_draft do %>
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
                    <p class="text-xs text-stone-500 truncate">{@options_draft.label}</p>
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
                for={@options_form}
                id={"correction-options-form-#{@options_draft.part_id}"}
                phx-change="change_correction_options"
                phx-submit="apply_correction_options"
              >
                <div class="px-6 py-5 space-y-6 max-h-[65vh] overflow-y-auto">
                  <section class="space-y-3">
                    <h4 class="text-xs font-semibold text-stone-500 uppercase tracking-wide">
                      Punkte
                    </h4>
                    <.points_field
                      :if={!@options_draft.custom_points}
                      id={@options_form[:max_points].id}
                      name={@options_form[:max_points].name}
                      value={@options_draft.max_points}
                      label="Max. Punkte"
                      key="max_points"
                      class="max-w-[14rem]"
                    />
                    <p :if={@options_draft.custom_points} class="text-sm text-stone-700">
                      Max. Punkte:
                      <span class="font-mono font-semibold">
                        {format_block_points(draft_total(@options_draft))}
                      </span>
                      <span class="text-xs text-stone-500">(Summe der Antwortfelder)</span>
                    </p>

                    <%!-- One field takes all points anyway. A distribution
                         already set stays switchable, so it can be turned off. --%>
                    <.option_toggle
                      :if={@options_draft.custom_points or answer_field_count(@options_draft) > 1}
                      field={@options_form[:custom_points]}
                      label="Punkte pro Antwortfeld"
                      hint="Punkte ungleich auf die Antwortfelder dieser Aufgabe verteilen."
                    />
                    <div
                      :if={@options_draft.custom_points}
                      class="grid grid-cols-2 gap-3 pl-7"
                    >
                      <.points_field
                        :for={block <- @options_draft.blocks}
                        :if={block.answer_id}
                        id={"options-block-points-#{block.answer_id}"}
                        name={"options[block_points][#{block.answer_id}]"}
                        value={Map.get(@options_draft.block_points, block.answer_id)}
                        label={block.snippet}
                        key={block.answer_id}
                      />
                    </div>

                    <.split_hint hint={uneven_split_hint(@options_draft)} />
                  </section>

                  <section class="space-y-3 pt-5 border-t border-stone-100">
                    <h4 class="text-xs font-semibold text-stone-500 uppercase tracking-wide">
                      Auto-Korrektur
                    </h4>
                    <p
                      :if={@options_draft.choice_only}
                      id="auto-correct-always-note"
                      class="flex items-start gap-2 text-sm text-stone-600 leading-relaxed"
                    >
                      <.icon
                        name="hero-check-circle"
                        class="w-[18px] h-[18px] text-violet-500 shrink-0 mt-0.5"
                      />
                      <span>
                        {choice_kinds(@options_draft)} werden immer automatisch korrigiert.
                        Du kannst jede Bewertung weiterhin von Hand ändern.
                      </span>
                    </p>
                    <.option_toggle
                      :if={!@options_draft.choice_only}
                      field={@options_form[:auto_correct]}
                      label="Auto-Korrektur"
                      hint="Diese Aufgabe wird beim Start der Auto-Korrektur automatisch bewertet."
                    />
                    <%= if @options_draft.has_text_answers do %>
                      <p
                        :if={@options_draft.has_checkboxes}
                        id="text-options-note"
                        class="text-xs text-stone-500 leading-relaxed pl-7"
                      >
                        Die folgenden Optionen gelten nur für Textantworten, nicht für Multiple-Choice.
                      </p>
                      <div class="pl-7 space-y-3">
                        <.option_toggle
                          :for={{key, label, hint} <- text_options()}
                          field={@options_form[key]}
                          label={label}
                          hint={hint}
                          disabled={!@options_draft.auto_correct}
                        />
                      </div>
                    <% end %>
                  </section>

                  <section
                    :if={@options_draft.has_checkboxes}
                    id="checkbox-scoring"
                    class="space-y-3 pt-5 border-t border-stone-100"
                  >
                    <div>
                      <h4 class="text-xs font-semibold text-stone-500 uppercase tracking-wide">
                        Punkte bei Multiple-Choice
                      </h4>
                      <p class="text-xs text-stone-500 mt-1 leading-relaxed">
                        Gilt für die Auto-Korrektur und die Korrektur von Hand. Manuelle Punkte
                        bleiben immer möglich.
                      </p>
                    </div>
                    <.input type="hidden" field={@options_form[:checkbox_rule]} />
                    <div class="grid grid-cols-2 gap-2" role="radiogroup">
                      <button
                        :for={{rule, label, hint} <- checkbox_rule_options()}
                        type="button"
                        id={"checkbox-scoring-#{rule}"}
                        role="radio"
                        aria-checked={to_string(@options_draft.checkbox_rule == rule)}
                        phx-click="draft_checkbox_rule"
                        phx-value-rule={rule}
                        class={[
                          "flex flex-col gap-1 rounded-lg border px-3 py-2.5 text-left transition-colors duration-150",
                          if(@options_draft.checkbox_rule == rule,
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
        <% end %>

        <%!-- Erklär-Dialog: rendered ONCE outside the part loop, so several
             question cards share one <dialog> instead of duplicating its ID. --%>
        <%= if @show_alternatives_help do %>
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
                    <span>
                      Wirkt bei der Auto-Korrektur und als Vorschlag in der Korrektur nach Frage.
                      Du kannst jede Bewertung weiterhin überschreiben.
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
        <% end %>
      </div>

      <%!-- Dateien tab --%>
      <div :if={@tab == "dateien"} class="bg-stone-100 min-h-[calc(100vh-54px)]">
        <div class="max-w-4xl mx-auto px-8 py-8 space-y-8">
          <%!-- Anhänge --%>
          <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
            <div class="p-6 flex items-start justify-between gap-4">
              <div class="min-w-0">
                <div class="flex items-center gap-2.5">
                  <.icon name="hero-paper-clip" class="w-5 h-5 text-sky-500" />
                  <h2 class="text-lg font-semibold text-stone-800">Anhänge</h2>
                </div>
                <p class="text-sm text-stone-500 mt-1">
                  Dateien, welche die Schüler während der Prüfung herunterladen können.
                </p>
              </div>
              <form id="attachment-upload-form" phx-change="validate_attachment" class="shrink-0">
                <label class="inline-flex items-center gap-2 border border-stone-200 text-stone-700 text-sm font-semibold px-4 py-2.5 rounded-xl cursor-pointer transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 active:scale-[0.98]">
                  <.icon name="hero-arrow-up-tray" class="w-4 h-4" /> Datei hochladen
                  <.live_file_input upload={@uploads.attachment} class="hidden" />
                </label>
              </form>
            </div>

            <div class="px-6 pb-6 space-y-2.5">
              <%!-- In-flight uploads + per-entry errors --%>
              <div
                :for={entry <- @uploads.attachment.entries}
                class="rounded-xl border border-stone-200 px-4 py-3"
              >
                <div class="flex items-center gap-3">
                  <p class="flex-1 min-w-0 text-sm font-medium text-stone-700 truncate">
                    {entry.client_name}
                  </p>
                  <%= if upload_errors(@uploads.attachment, entry) == [] do %>
                    <progress
                      class="progress progress-info w-32"
                      value={entry.progress}
                      max="100"
                    >
                    </progress>
                  <% end %>
                  <button
                    type="button"
                    phx-click="cancel_attachment_upload"
                    phx-value-ref={entry.ref}
                    aria-label="Upload abbrechen"
                    class="inline-flex items-center justify-center w-7 h-7 rounded-full text-stone-400 hover:bg-stone-100 hover:text-stone-600 transition-colors duration-150 shrink-0"
                  >
                    <.icon name="hero-x-mark" class="w-4 h-4" />
                  </button>
                </div>
                <p
                  :for={err <- upload_errors(@uploads.attachment, entry)}
                  class="text-xs text-red-600 mt-1.5"
                >
                  {upload_error_message(err)}
                </p>
              </div>
              <p
                :for={err <- upload_errors(@uploads.attachment)}
                class="text-xs text-red-600"
              >
                {upload_error_message(err)}
              </p>

              <div
                :if={@attachments == [] and @uploads.attachment.entries == []}
                class="rounded-xl border border-dashed border-stone-200 px-4 py-8 text-center"
              >
                <p class="text-sm text-stone-400">
                  Noch keine Anhänge. Lade z.&nbsp;B. einen Lesetext (PDF) oder eine Audio-Datei hoch.
                </p>
              </div>

              <div
                :for={attachment <- @attachments}
                class="flex items-center gap-4 rounded-xl border border-stone-200 px-4 py-3"
              >
                <.file_badge filename={attachment.stored_filename} />
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-semibold text-stone-800 truncate">
                    {attachment.original_name}
                  </p>
                  <p class="text-xs text-stone-400 mt-0.5">
                    {file_type_label(attachment.stored_filename)} · {Uploads.format_size(
                      attachment.size
                    )}
                  </p>
                </div>
                <a
                  href={~p"/uploads/exams/#{@exam.id}/attachments/#{attachment.stored_filename}"}
                  target="_blank"
                  rel="noopener"
                  class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-sm font-semibold px-3.5 py-2 rounded-lg transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 shrink-0"
                >
                  <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Herunterladen
                </a>
                <button
                  type="button"
                  phx-click="delete_attachment"
                  phx-value-id={attachment.id}
                  data-confirm={"Anhang «#{attachment.original_name}» wirklich löschen?"}
                  aria-label="Anhang löschen"
                  class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-400 hover:bg-red-50 hover:text-red-500 transition-colors duration-150 shrink-0"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>

          <%!-- Datei-Abgaben --%>
          <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
            <div class="p-6 flex items-start justify-between gap-4">
              <div class="min-w-0">
                <div class="flex items-center gap-2.5">
                  <.icon name="hero-arrow-up-tray" class="w-5 h-5 text-sky-500" />
                  <h2 class="text-lg font-semibold text-stone-800">Datei-Abgaben</h2>
                </div>
                <p class="text-sm text-stone-500 mt-1">
                  Felder, in die Schüler ihre Antwort als Datei hochladen. Eine Datei pro Feld.
                </p>
              </div>
              <button
                :if={@editing_field_id == nil}
                type="button"
                phx-click="add_upload_field"
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-4 py-2.5 rounded-xl shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] shrink-0"
              >
                <.icon name="hero-plus" class="w-4 h-4" /> Upload-Feld hinzufügen
              </button>
            </div>

            <div class="px-6 pb-6 space-y-3">
              <div
                :if={@upload_fields == [] and @editing_field_id != :new}
                class="rounded-xl border border-dashed border-stone-200 px-4 py-8 text-center"
              >
                <p class="text-sm text-stone-400">
                  Noch keine Upload-Felder. Füge ein Feld hinzu, damit Schüler Dateien abgeben können.
                </p>
              </div>

              <div
                :for={field <- @upload_fields}
                class="rounded-xl border border-stone-200 px-5 py-4"
              >
                <%= if @editing_field_id == field.id do %>
                  <.upload_field_form
                    draft={@field_draft}
                    label_placeholder="z. B. Aufsatz, Sprachaufnahme, …"
                  />
                <% else %>
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0">
                      <div class="flex items-center gap-2.5 flex-wrap">
                        <h3 class="text-base font-semibold text-stone-800 truncate">
                          {field.label}
                        </h3>
                        <span
                          :if={field.required}
                          class="text-[11px] font-semibold text-amber-700 bg-amber-50 border border-amber-200 rounded-full px-2 py-0.5"
                        >
                          Pflicht
                        </span>
                        <span
                          :if={!field.required}
                          class="text-[11px] font-semibold text-stone-500 bg-stone-100 border border-stone-200 rounded-full px-2 py-0.5"
                        >
                          Optional
                        </span>
                      </div>
                      <p :if={field.instruction} class="text-sm text-stone-500 mt-1">
                        {field.instruction}
                      </p>
                      <div class="flex items-center gap-1.5 mt-2.5 flex-wrap">
                        <span class="text-xs text-stone-400 mr-1">Erlaubte Dateitypen:</span>
                        <span
                          :for={type <- field.allowed_types}
                          class="text-[11px] font-semibold text-stone-600 bg-stone-100 rounded-md px-2 py-0.5"
                        >
                          {type_chip_label(type)}
                        </span>
                      </div>
                    </div>
                    <div class="flex items-center gap-1 shrink-0">
                      <button
                        type="button"
                        phx-click="edit_upload_field"
                        phx-value-id={field.id}
                        aria-label="Feld bearbeiten"
                        class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-400 hover:bg-stone-100 hover:text-stone-600 transition-colors duration-150"
                      >
                        <.icon name="hero-pencil" class="w-4 h-4" />
                      </button>
                      <button
                        type="button"
                        phx-click="delete_upload_field"
                        phx-value-id={field.id}
                        data-confirm={"Upload-Feld «#{field.label}» wirklich löschen? Bereits hochgeladene Abgaben der Schüler werden ebenfalls gelöscht."}
                        aria-label="Feld löschen"
                        class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-400 hover:bg-red-50 hover:text-red-500 transition-colors duration-150"
                      >
                        <.icon name="hero-trash" class="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>

              <div
                :if={@editing_field_id == :new}
                class="rounded-xl border border-sky-200 bg-sky-50/40 px-5 py-4"
              >
                <.upload_field_form
                  draft={@field_draft}
                  label_placeholder="z. B. Aufsatz, Sprachaufnahme, …"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:exam, exam)
     # Assigned here rather than in the "musterloesung" branch of
     # handle_params/3 so the flag is defined on every tab.
     |> assign(:show_alternatives_help, false)
     |> assign(:options_draft, nil)
     |> assign(:options_form, nil)
     |> assign(:free_document, ExamComponents.free_document?(exam))
     |> allow_upload(:attachment,
       accept: Uploads.attachment_accept_exts(),
       max_entries: 3,
       max_file_size: Uploads.max_file_bytes(),
       auto_upload: true,
       progress: &handle_attachment_progress/3
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Reload exam each time params change so structure edits made in the
    # Inhalt tab are reflected when the teacher switches to Musterlösung.
    exam = Exams.get_exam!(socket.assigns.current_scope, socket.assigns.exam.id)
    free_document? = ExamComponents.free_document?(exam)

    tab =
      case params["tab"] do
        "musterloesung" -> "musterloesung"
        "dateien" -> "dateien"
        _ -> "inhalt"
      end

    socket =
      socket
      |> assign(:exam, exam)
      |> assign(:free_document, free_document?)
      |> assign(:tab, tab)
      |> assign(:page_title, "#{exam.name} – #{tab_label(tab, free_document?)}")

    case tab do
      "inhalt" ->
        {:noreply, assign(socket, :content_json, Jason.encode!(exam.content || %{}))}

      "musterloesung" ->
        {:noreply, assign(socket, :part_views, build_part_views(exam))}

      "dateien" ->
        {:noreply,
         socket
         |> assign(:attachments, Exams.list_exam_attachments(exam))
         |> assign(:upload_fields, Exams.list_upload_fields(exam))
         |> assign(:editing_field_id, nil)
         |> assign(:field_draft, nil)}
    end
  end

  # One view-model entry per part, rendered as a stacked editor + points card.
  # `doc_json` is only computed here (full navigation) — event handlers must
  # never touch it, so the phx-update="ignore" editor hooks stay untouched.
  defp build_part_views(exam) do
    parts = Exams.split_content_into_parts(exam.content || %{}, exam.answer_mode)

    sample_parts =
      exam
      |> Exams.sample_solution_doc()
      |> Exams.split_content_into_parts(exam.answer_mode)
      |> Map.new(&{&1.id, &1})

    Enum.map(parts, fn part ->
      nodes =
        case Map.get(sample_parts, part.id) do
          nil -> part.nodes
          sample -> sample.nodes
        end

      blocks =
        nodes
        |> Tasky.AI.NodePatcher.list_answer_blocks()
        |> Enum.map(fn entry ->
          snippet =
            case String.slice(entry.text || "", 0, 40) do
              "" -> "Antwort #{entry.index + 1}"
              s -> s
            end

          %{answer_id: entry.answer_id, type: entry.type, snippet: snippet, points: nil}
        end)

      Map.merge(
        %{
          id: part.id,
          label: part.label,
          doc_json: Jason.encode!(%{"type" => "doc", "content" => nodes}),
          has_text_answers: Enum.any?(blocks, &(&1.type in ["answerBlock", "lueckentext"])),
          has_checkboxes: Enum.any?(blocks, &(&1.type == "taskItem"))
        },
        option_fields(exam, part.id, blocks)
      )
    end)
  end

  # The part view's points and correction options, as stored on the exam.
  # Shared by the full build and the refresh after "Übernehmen", which must
  # not touch `doc_json`.
  defp option_fields(exam, part_id, blocks) do
    custom = Map.get(exam.sample_solution_block_points || %{}, part_id) || %{}
    scoring = Exams.checkbox_scoring(exam, part_id)
    choice_only? = Exams.choice_only_blocks?(blocks)

    %{
      max_points: Map.get(exam.sample_solution_points || %{}, part_id),
      blocks: Enum.map(blocks, &%{&1 | points: Map.get(custom, &1.answer_id)}),
      custom_points: map_size(custom) > 0,
      # A part of only ticks is always auto-corrected (`Exams.auto_correct_part_ids/1`).
      choice_only: choice_only?,
      auto_correct: choice_only? or part_config_flag(exam, part_id, "auto_correct"),
      ignore_case: part_config_flag(exam, part_id, "ignore_case"),
      ignore_spelling: part_config_flag(exam, part_id, "ignore_spelling"),
      ignore_punctuation: part_config_flag(exam, part_id, "ignore_punctuation"),
      checkbox_rule: scoring.rule
    }
  end

  @impl true
  def handle_event("set_max_points", %{"points" => raw, "part_id" => part_id}, socket) do
    save_max_points(socket, part_id, parse_points(raw))
  end

  def handle_event("adjust_max_points", %{"direction" => dir, "part-id" => part_id}, socket) do
    case part_view(socket, part_id) do
      nil ->
        {:noreply, socket}

      pv ->
        delta = if dir == "up", do: 0.25, else: -0.25
        new_value = max((pv.max_points || 0) + delta, 0)
        save_max_points(socket, part_id, new_value)
    end
  end

  def handle_event("open_correction_options", %{"part-id" => part_id}, socket) do
    case part_view(socket, part_id) do
      nil ->
        {:noreply, socket}

      pv ->
        draft = %{
          part_id: pv.id,
          label: pv.label,
          blocks: pv.blocks,
          has_text_answers: pv.has_text_answers,
          has_checkboxes: pv.has_checkboxes,
          choice_only: pv.choice_only,
          max_points: pv.max_points,
          custom_points: pv.custom_points,
          block_points: Map.new(pv.blocks, &{&1.answer_id, &1.points}),
          auto_correct: pv.auto_correct,
          ignore_case: pv.ignore_case,
          ignore_spelling: pv.ignore_spelling,
          ignore_punctuation: pv.ignore_punctuation,
          checkbox_rule: pv.checkbox_rule
        }

        {:noreply, assign_options_draft(socket, draft)}
    end
  end

  def handle_event("close_correction_options", _params, socket) do
    {:noreply, assign_options_draft(socket, nil)}
  end

  def handle_event("change_correction_options", %{"options" => params}, socket) do
    case socket.assigns.options_draft do
      nil -> {:noreply, socket}
      draft -> {:noreply, assign_options_draft(socket, merge_options_params(draft, params))}
    end
  end

  # The ± buttons next to a points field in the dialog: `key` is
  # "max_points" or a block's answer id.
  def handle_event("step_draft_points", %{"key" => key, "direction" => dir}, socket) do
    case socket.assigns.options_draft do
      nil ->
        {:noreply, socket}

      draft ->
        step = &step_points(&1, dir)

        draft =
          cond do
            key == "max_points" -> %{draft | max_points: step.(draft.max_points)}
            Map.has_key?(draft.block_points, key) -> update_in(draft.block_points[key], step)
            true -> draft
          end

        {:noreply, assign_options_draft(socket, draft)}
    end
  end

  # A suggestion of the uneven-split hint: the max points that split evenly.
  def handle_event("draft_max_points", %{"points" => raw}, socket) do
    case {socket.assigns.options_draft, parse_points(raw)} do
      {%{} = draft, points} when is_number(points) ->
        {:noreply, assign_options_draft(socket, %{draft | max_points: points})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("draft_checkbox_rule", %{"rule" => rule}, socket) do
    case socket.assigns.options_draft do
      %{} = draft when is_binary(rule) ->
        rule = if rule in Tasky.Grading.checkbox_rules(), do: rule, else: draft.checkbox_rule
        {:noreply, assign_options_draft(socket, %{draft | checkbox_rule: rule})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("apply_correction_options", %{"options" => params}, socket) do
    case socket.assigns.options_draft do
      nil ->
        {:noreply, socket}

      draft ->
        draft = merge_options_params(draft, params)

        opts = %{
          max_points: draft.max_points,
          block_points: if(draft.custom_points, do: draft.block_points),
          config: options_config(draft)
        }

        case Exams.apply_part_options(
               socket.assigns.current_scope,
               socket.assigns.exam,
               draft.part_id,
               opts
             ) do
          {:ok, updated_exam} ->
            pv = part_view(socket, draft.part_id)

            {:noreply,
             socket
             |> assign(:exam, updated_exam)
             |> update_part_view(draft.part_id, option_fields(updated_exam, pv.id, pv.blocks))
             |> assign_options_draft(nil)}

          {:error, _reason} ->
            {:noreply,
             put_flash(socket, :error, "Korrekturoptionen konnten nicht gespeichert werden.")}
        end
    end
  end

  def handle_event("open_alternatives_help", _params, socket) do
    {:noreply, assign(socket, :show_alternatives_help, true)}
  end

  def handle_event("close_alternatives_help", _params, socket) do
    {:noreply, assign(socket, :show_alternatives_help, false)}
  end

  ## Dateien tab: attachments

  def handle_event("validate_attachment", _params, socket) do
    # auto_upload does the work; this handler just accepts the phx-change.
    {:noreply, socket}
  end

  def handle_event("cancel_attachment_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachment, ref)}
  end

  def handle_event("delete_attachment", %{"id" => id}, socket) do
    with attachment when not is_nil(attachment) <-
           Exams.get_exam_attachment(socket.assigns.exam, id),
         {:ok, _} <- Exams.delete_exam_attachment(socket.assigns.current_scope, attachment) do
      {:noreply, assign(socket, :attachments, Exams.list_exam_attachments(socket.assigns.exam))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Anhang konnte nicht gelöscht werden.")}
    end
  end

  ## Dateien tab: upload fields

  def handle_event("add_upload_field", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_field_id, :new)
     |> assign(:field_draft, new_field_draft())}
  end

  def handle_event("edit_upload_field", %{"id" => id}, socket) do
    case Exams.get_upload_field(socket.assigns.exam, id) do
      nil ->
        {:noreply, socket}

      field ->
        {:noreply,
         socket
         |> assign(:editing_field_id, field.id)
         |> assign(:field_draft, %{
           "label" => field.label,
           "instruction" => field.instruction || "",
           "required" => to_string(field.required),
           "allowed_types" => field.allowed_types
         })}
    end
  end

  def handle_event("cancel_field_edit", _params, socket) do
    {:noreply, socket |> assign(:editing_field_id, nil) |> assign(:field_draft, nil)}
  end

  def handle_event("field_draft_changed", params, socket) do
    draft =
      socket.assigns.field_draft
      |> Map.merge(Map.take(params, ["label", "instruction", "required"]))
      |> Map.delete("label_error")

    {:noreply, assign(socket, :field_draft, draft)}
  end

  def handle_event("toggle_field_type", %{"type" => type}, socket) do
    draft = socket.assigns.field_draft
    types = draft["allowed_types"]

    types =
      if type in types,
        do: List.delete(types, type),
        else: types ++ [type]

    {:noreply,
     assign(
       socket,
       :field_draft,
       draft |> Map.put("allowed_types", types) |> Map.delete("types_error")
     )}
  end

  def handle_event("save_upload_field", params, socket) do
    draft =
      socket.assigns.field_draft
      |> Map.merge(Map.take(params, ["label", "instruction", "required"]))

    attrs = %{
      "label" => String.trim(draft["label"] || ""),
      "instruction" => presence(String.trim(draft["instruction"] || "")),
      "required" => draft["required"] == "true",
      "allowed_types" => draft["allowed_types"]
    }

    result =
      case socket.assigns.editing_field_id do
        :new ->
          Exams.create_upload_field(socket.assigns.current_scope, socket.assigns.exam, attrs)

        id ->
          case Exams.get_upload_field(socket.assigns.exam, id) do
            nil -> {:error, :not_found}
            field -> Exams.update_upload_field(socket.assigns.current_scope, field, attrs)
          end
      end

    case result do
      {:ok, _field} ->
        {:noreply,
         socket
         |> assign(:upload_fields, Exams.list_upload_fields(socket.assigns.exam))
         |> assign(:editing_field_id, nil)
         |> assign(:field_draft, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        draft =
          draft
          |> put_draft_error(
            changeset,
            :label,
            "label_error",
            "Bezeichnung darf nicht leer sein."
          )
          |> put_draft_error(
            changeset,
            :allowed_types,
            "types_error",
            "Mindestens einen Dateityp wählen."
          )

        {:noreply, assign(socket, :field_draft, draft)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Upload-Feld konnte nicht gespeichert werden.")}
    end
  end

  def handle_event("delete_upload_field", %{"id" => id}, socket) do
    with field when not is_nil(field) <- Exams.get_upload_field(socket.assigns.exam, id),
         {:ok, _} <- Exams.delete_upload_field(socket.assigns.current_scope, field) do
      {:noreply, assign(socket, :upload_fields, Exams.list_upload_fields(socket.assigns.exam))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Upload-Feld konnte nicht gelöscht werden.")}
    end
  end

  defp checkbox_rule_options do
    [
      {"per_checkbox", "Pro Checkbox",
       "Jede richtig angekreuzte oder richtig leer gelassene Checkbox gibt ihren Anteil der Punkte."},
      {"all_or_nothing", "Alles oder nichts",
       "Volle Punkte nur, wenn alle Checkboxen stimmen, sonst 0."}
    ]
  end

  defp assign_options_draft(socket, nil),
    do: socket |> assign(:options_draft, nil) |> assign(:options_form, nil)

  defp assign_options_draft(socket, draft) do
    params = %{
      "max_points" => draft.max_points,
      "custom_points" => draft.custom_points,
      "auto_correct" => draft.auto_correct,
      "ignore_case" => draft.ignore_case,
      "ignore_spelling" => draft.ignore_spelling,
      "ignore_punctuation" => draft.ignore_punctuation,
      "checkbox_rule" => draft.checkbox_rule
    }

    socket
    |> assign(:options_draft, draft)
    |> assign(:options_form, to_form(params, as: :options))
  end

  # Folds the dialog's form params into the draft. Turning the custom
  # distribution on starts from the equal split of the current total, turning
  # it off keeps the sum as the total; text options go with auto-correction.
  defp merge_options_params(draft, params) do
    custom? = Map.get(params, "custom_points", to_string(draft.custom_points)) == "true"

    block_points =
      Enum.reduce(Map.get(params, "block_points", %{}), draft.block_points, fn {id, raw}, acc ->
        if Map.has_key?(acc, id), do: Map.put(acc, id, parse_points(raw) || 0), else: acc
      end)

    max_points =
      case Map.fetch(params, "max_points") do
        {:ok, raw} -> parse_points(raw)
        :error -> draft.max_points
      end

    {block_points, max_points} =
      cond do
        custom? and not draft.custom_points ->
          ids = draft.blocks |> Enum.map(& &1.answer_id) |> Enum.reject(&is_nil/1)
          {Exams.equal_shares(ids, max_points || 0), max_points}

        draft.custom_points and not custom? ->
          {block_points, draft_total(%{draft | block_points: block_points})}

        true ->
          {block_points, max_points}
      end

    auto? = flag_param(params, "auto_correct", draft.auto_correct)

    %{
      draft
      | custom_points: custom?,
        block_points: block_points,
        max_points: max_points,
        auto_correct: auto?,
        ignore_case: auto? and flag_param(params, "ignore_case", draft.ignore_case),
        ignore_spelling: auto? and flag_param(params, "ignore_spelling", draft.ignore_spelling),
        ignore_punctuation:
          auto? and flag_param(params, "ignore_punctuation", draft.ignore_punctuation),
        checkbox_rule: Map.get(params, "checkbox_rule", draft.checkbox_rule)
    }
  end

  # The kinds of tick questions in a part of only ticks, as the note names them.
  defp choice_kinds(draft) do
    types = MapSet.new(draft.blocks, & &1.type)

    case {"taskItem" in types, "choice" in types} do
      {true, true} -> "Multiple-Choice- und Single-Choice-Aufgaben"
      {true, false} -> "Multiple-Choice-Aufgaben"
      {false, true} -> "Single-Choice-Aufgaben"
      _ -> "Ankreuzaufgaben"
    end
  end

  # A part of only ticks shows no auto-correction switch, so its stored flag
  # stays as it is — a text field added later falls back to it.
  defp options_config(draft) do
    config = %{
      "auto_correct" => draft.auto_correct,
      "ignore_case" => draft.ignore_case,
      "ignore_spelling" => draft.ignore_spelling,
      "ignore_punctuation" => draft.ignore_punctuation,
      "checkbox_scoring" => draft.checkbox_rule
    }

    if draft.choice_only, do: Map.delete(config, "auto_correct"), else: config
  end

  defp flag_param(params, key, default) do
    case Map.fetch(params, key) do
      {:ok, value} -> value == "true"
      :error -> default
    end
  end

  defp answer_field_count(draft), do: Enum.count(draft.blocks, & &1.answer_id)

  # Whether the dialog warns that the max points do not split evenly over the
  # answer fields (`Tasky.Grading.uneven_split/2`), and what it suggests. Not
  # with a custom distribution — the teacher chose the shares — and not for
  # a Multiple-Choice question scored all or nothing, where only the sum counts.
  defp uneven_split_hint(draft) do
    fields = Enum.filter(draft.blocks, & &1.answer_id)
    multiple_choice? = fields != [] and Enum.all?(fields, &(&1.type == "taskItem"))
    all_or_nothing? = draft.checkbox_rule == "all_or_nothing"

    split =
      if draft.custom_points or (multiple_choice? and all_or_nothing?),
        do: nil,
        else: Tasky.Grading.uneven_split(draft.max_points, length(fields))

    if split do
      {one, many} =
        if multiple_choice?, do: {"Option", "Optionen"}, else: {"Antwortfeld", "Antwortfelder"}

      count = length(fields)

      %{
        split: split,
        summary:
          "#{points_label(draft.max_points)} auf #{count} #{many} ergibt je " <>
            "#{approx_points(split.exact)} Punkte. LearningLine rechnet in Viertelpunkten, " <>
            "darum zählt #{count_label(split.high_count, one, many)} " <>
            "#{points_label(split.high)} und #{count_label(split.low_count, one, many)} " <>
            "#{points_label(split.low)}.",
        add_fields:
          split.fields &&
            "Lass die Punkte bei #{points_label(draft.max_points)}, doch füge " <>
              "#{count_label(split.fields - count, one, many)} hinzu: Bei #{split.fields} " <>
              "#{many} zählt jede#{if multiple_choice?, do: "", else: "s"} " <>
              "#{points_label(draft.max_points / split.fields)}.",
        all_or_nothing: multiple_choice? and not all_or_nothing?
      }
    end
  end

  defp count_label(1, one, _many), do: "1 #{one}"
  defp count_label(n, _one, many), do: "#{n} #{many}"

  defp points_label(n) when n in [1, 1.0], do: "1 Punkt"
  defp points_label(n), do: "#{format_block_points(Tasky.Grading.normalize_points(n))} Punkte"

  # 1/3 → "rund 0.33", 0.2 → "0.2".
  defp approx_points(n) do
    rounded = Float.round(n * 1.0, 2)

    text =
      rounded
      |> :erlang.float_to_binary(decimals: 2)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")

    if rounded == n * 1.0, do: text, else: "rund #{text}"
  end

  defp draft_total(draft) do
    draft.block_points |> Map.values() |> Enum.map(&(&1 || 0)) |> Enum.sum()
  end

  # What the sidebar lists under "Korrekturoptionen": the active settings by
  # name, without their descriptions.
  defp active_option_labels(pv) do
    text =
      if pv.has_text_answers,
        do: for({key, label, _hint} <- text_options(), Map.fetch!(pv, key), do: label),
        else: []

    Enum.reject(
      [
        pv.custom_points && "Punkte pro Antwortfeld",
        pv.auto_correct && "Auto-Korrektur"
      ],
      &(&1 in [nil, false])
    ) ++ text ++ checkbox_rule_summary(pv)
  end

  defp checkbox_rule_summary(%{has_checkboxes: false}), do: []

  defp checkbox_rule_summary(%{checkbox_rule: "all_or_nothing"}),
    do: ["Multiple-Choice: alles oder nichts"]

  defp checkbox_rule_summary(_pv), do: ["Multiple-Choice: pro Checkbox"]

  # One 0.25 step up or down, never below 0; whole numbers stay integers.
  defp step_points(value, dir) do
    stepped = max((value || 0) + if(dir == "up", do: 0.25, else: -0.25), 0)
    if stepped == trunc(stepped), do: trunc(stepped), else: stepped
  end

  attr :direction, :string, values: ~w(up down), required: true
  attr :disabled, :boolean, default: false
  attr :rest, :global

  # The ± button of a points field. Plus sits left, minus right — the same
  # order in the sidebar and in the options dialog.
  defp step_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-value-direction={@direction}
      disabled={@disabled}
      aria-label={if @direction == "up", do: "+0.25", else: "−0.25"}
      class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 active:scale-90 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent shrink-0"
      {@rest}
    >
      <.icon name={if @direction == "up", do: "hero-plus", else: "hero-minus"} class="w-4 h-4" />
    </button>
    """
  end

  # One look for every points input, in the sidebar and in the options dialog.
  defp points_input_class,
    do:
      "w-full font-mono text-base text-center text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-purple-300 focus:border-purple-400"

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :label, :string, required: true
  attr :key, :string, required: true
  attr :class, :string, default: nil

  # A points input of the options dialog, between its + and − buttons.
  defp points_field(assigns) do
    ~H"""
    <div class={@class}>
      <label for={@id} class="block text-sm text-stone-700 mb-1 truncate">{@label}</label>
      <div class="flex items-center gap-1.5 [&_.fieldset]:mb-0">
        <.step_button
          id={"#{@id}-up"}
          direction="up"
          phx-click="step_draft_points"
          phx-value-key={@key}
        />
        <div class="flex-1 min-w-0">
          <.input
            type="number"
            id={@id}
            name={@name}
            value={@value}
            step="0.25"
            min="0"
            inputmode="decimal"
            class={points_input_class()}
          />
        </div>
        <.step_button
          id={"#{@id}-down"}
          direction="down"
          phx-click="step_draft_points"
          phx-value-key={@key}
          disabled={is_nil(@value) or @value <= 0}
        />
      </div>
    </div>
    """
  end

  attr :hint, :map, default: nil

  # The warning under the points when they do not split evenly, with its
  # suggestions as one-click fixes for the draft.
  defp split_hint(%{hint: nil} = assigns), do: ~H""

  defp split_hint(assigns) do
    ~H"""
    <div
      id="points-split-hint"
      role="status"
      class="rounded-xl border border-amber-200 bg-amber-50/70 px-4 py-3.5 space-y-3"
    >
      <div class="flex items-start gap-2.5">
        <.icon
          name="hero-exclamation-triangle"
          class="w-[18px] h-[18px] text-amber-500 shrink-0 mt-0.5"
        />
        <div class="space-y-1 min-w-0">
          <p class="text-sm font-semibold text-stone-800">
            Die Punkte lassen sich nicht gleichmässig verteilen
          </p>
          <p class="text-xs text-stone-600 leading-relaxed">{@hint.summary}</p>
        </div>
      </div>

      <div class="pl-7 space-y-2">
        <p class="text-xs font-semibold text-stone-500 uppercase tracking-wide">Empfehlung</p>
        <ul class="space-y-2 text-xs text-stone-600 leading-relaxed">
          <li class="flex flex-wrap items-center gap-1.5">
            <span>Ändere die max. Punktzahl auf</span>
            <.hint_button
              :if={@hint.split.lower}
              id="split-hint-lower"
              phx-click="draft_max_points"
              phx-value-points={@hint.split.lower}
            >
              {format_block_points(@hint.split.lower)} Punkte
            </.hint_button>
            <span :if={@hint.split.lower}>oder</span>
            <.hint_button
              id="split-hint-higher"
              phx-click="draft_max_points"
              phx-value-points={@hint.split.higher}
            >
              {format_block_points(@hint.split.higher)} Punkte
            </.hint_button>
          </li>
          <li :if={@hint.add_fields} id="split-hint-add-fields">{@hint.add_fields}</li>
          <li :if={@hint.all_or_nothing} class="flex flex-wrap items-center gap-1.5">
            <span>Ändere die Korrektur-Option auf</span>
            <.hint_button
              id="split-hint-all-or-nothing"
              phx-click="draft_checkbox_rule"
              phx-value-rule="all_or_nothing"
            >
              Alles oder nichts
            </.hint_button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :rest, :global
  slot :inner_block, required: true

  defp hint_button(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      class="inline-flex items-center rounded-md border border-amber-300 bg-white px-2 py-0.5 font-semibold text-amber-700 transition-colors duration-150 hover:bg-amber-100 hover:border-amber-400 active:scale-[0.98] cursor-pointer"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :hint, :string, required: true
  attr :disabled, :boolean, default: false

  # A checkbox with its description underneath, for the options dialog.
  defp option_toggle(assigns) do
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

  defp save_max_points(socket, part_id, points) do
    case part_view(socket, part_id) do
      nil ->
        {:noreply, socket}

      # The total is derived from the per-block sum while custom distribution
      # is active — ignore direct edits (the input is read-only anyway).
      %{custom_points: true} ->
        {:noreply, socket}

      _pv ->
        case Exams.set_sample_solution_part_points(
               socket.assigns.current_scope,
               socket.assigns.exam,
               part_id,
               points
             ) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:exam, updated)
             |> update_part_view(part_id, %{max_points: points})}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Punkte konnten nicht gespeichert werden.")}
        end
    end
  end

  defp handle_attachment_progress(:attachment, entry, socket) do
    if entry.done? do
      exam = socket.assigns.exam

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          case Uploads.save_exam_attachment(exam.id, path, entry.client_name) do
            {:ok, meta} ->
              {:ok,
               Exams.create_exam_attachment(
                 socket.assigns.current_scope,
                 exam,
                 Map.put(meta, :original_name, entry.client_name)
               )}

            {:error, reason} ->
              {:ok, {:error, reason}}
          end
        end)

      case result do
        {:ok, _attachment} ->
          {:noreply, assign(socket, :attachments, Exams.list_exam_attachments(exam))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, file_save_error_message(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  # The text comparison options of a part, in display order. Keys match both
  # the part view and `ai_correction_config` (see
  # `Tasky.Correction.StringComparator.match_opts/1`).
  defp text_options do
    [
      {:ignore_case, "Gross-/Kleinschreibung ignorieren",
       "Bei der Auto-Korrektur dieser Aufgabe wird Gross-/Kleinschreibung nicht bewertet."},
      {:ignore_punctuation, "Satzzeichen ignorieren",
       "Punkt, Komma, Ausrufe- und Fragezeichen usw. werden beim Vergleich nicht beachtet."},
      {:ignore_spelling, "Rechtschreibung ignorieren",
       "Bei der Auto-Korrektur dieser Aufgabe werden Rechtschreibfehler nicht streng bewertet (Fuzzy-Matching ab Jaro-Ähnlichkeit ≥ 0,85)."}
    ]
  end

  defp part_view(socket, part_id),
    do: Enum.find(socket.assigns.part_views, &(&1.id == part_id))

  # Merges `changes` into the matching part view. Deliberately never touches
  # `doc_json` — see build_part_views/1.
  defp update_part_view(socket, part_id, changes) do
    part_views =
      Enum.map(socket.assigns.part_views, fn pv ->
        if pv.id == part_id, do: Map.merge(pv, changes), else: pv
      end)

    assign(socket, :part_views, part_views)
  end

  defp tab_label("inhalt", _free_document?), do: "Inhalt"
  defp tab_label("musterloesung", free?), do: solution_tab_label(free?)
  defp tab_label("dateien", _free_document?), do: "Dateien"

  # Im freien Modus gibt es keine Musterlösung — der Tab trägt nur noch die
  # Maximalpunkte, und "Musterlösung" wäre ein Versprechen, das er nicht hält.
  defp solution_tab_label(true), do: "Punkte"
  defp solution_tab_label(false), do: "Musterlösung"

  defp part_config_flag(exam, part_id, key) do
    (exam.ai_correction_config || %{})
    |> Map.get(part_id, %{})
    |> Map.get(key, false)
  end

  defp format_block_points(n), do: Tasky.Grading.format_points(n)

  defp parse_points(value), do: Tasky.Grading.parse_points(value)
end
