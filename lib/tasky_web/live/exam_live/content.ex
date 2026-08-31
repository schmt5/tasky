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
                  <button
                    type="button"
                    phx-click="adjust_max_points"
                    phx-value-direction="down"
                    phx-value-part-id={pv.id}
                    disabled={is_nil(pv.max_points) or pv.max_points <= 0}
                    aria-label="−0.25"
                    class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent shrink-0"
                  >
                    <.icon name="hero-minus" class="w-4 h-4" />
                  </button>
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
                      class="w-full font-mono text-base text-center text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-purple-300 focus:border-purple-400"
                    />
                  </form>
                  <button
                    type="button"
                    phx-click="adjust_max_points"
                    phx-value-direction="up"
                    phx-value-part-id={pv.id}
                    aria-label="+0.25"
                    class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 shrink-0"
                  >
                    <.icon name="hero-plus" class="w-4 h-4" />
                  </button>
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
                    <button
                      type="button"
                      phx-click="adjust_max_points"
                      phx-value-direction="down"
                      phx-value-part-id={pv.id}
                      disabled={is_nil(pv.max_points) or pv.max_points <= 0}
                      aria-label="−0.25"
                      class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent shrink-0"
                    >
                      <.icon name="hero-minus" class="w-4 h-4" />
                    </button>
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
                        class="w-full font-mono text-base text-center text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-purple-300 focus:border-purple-400"
                      />
                    </form>
                    <button
                      type="button"
                      phx-click="adjust_max_points"
                      phx-value-direction="up"
                      phx-value-part-id={pv.id}
                      aria-label="+0.25"
                      class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 shrink-0"
                    >
                      <.icon name="hero-plus" class="w-4 h-4" />
                    </button>
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

                  <label class="flex items-start gap-3 cursor-pointer mt-4">
                    <input
                      type="checkbox"
                      checked={pv.custom_points}
                      phx-click="toggle_custom_block_points"
                      phx-value-part-id={pv.id}
                      class="mt-0.5 w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150 shrink-0"
                    />
                    <span class="min-w-0">
                      <span class="block text-sm font-medium text-stone-700">
                        Punkte pro Antwortfeld
                      </span>
                      <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                        Punkte ungleich auf die Antwortfelder dieser Aufgabe verteilen.
                      </span>
                    </span>
                  </label>

                  <div :if={pv.custom_points} class="mt-3 space-y-2">
                    <div
                      :for={block <- pv.blocks}
                      :if={block.answer_id}
                      class="rounded-lg border border-stone-200 bg-stone-50/60 px-2.5 py-2"
                    >
                      <p class="text-xs text-stone-500 truncate mb-1.5">{block.snippet}</p>
                      <div class="flex items-center gap-1">
                        <button
                          type="button"
                          phx-click="adjust_block_points"
                          phx-value-direction="down"
                          phx-value-part-id={pv.id}
                          phx-value-answer-id={block.answer_id}
                          disabled={(block.points || 0) <= 0}
                          aria-label="−0.25"
                          class="inline-flex items-center justify-center w-7 h-7 rounded-full text-stone-500 hover:bg-stone-100 hover:text-stone-700 transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent shrink-0"
                        >
                          <.icon name="hero-minus" class="w-3.5 h-3.5" />
                        </button>
                        <form
                          phx-change="set_block_points"
                          phx-submit="set_block_points"
                          class="flex-1"
                        >
                          <input type="hidden" name="part_id" value={pv.id} />
                          <input type="hidden" name="answer_id" value={block.answer_id} />
                          <input
                            type="number"
                            name="points"
                            value={block.points || ""}
                            step="0.25"
                            min="0"
                            inputmode="decimal"
                            phx-debounce="500"
                            placeholder="0"
                            class="w-full font-mono text-sm text-center text-stone-800 bg-white border border-stone-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-purple-300 focus:border-purple-400"
                          />
                        </form>
                        <button
                          type="button"
                          phx-click="adjust_block_points"
                          phx-value-direction="up"
                          phx-value-part-id={pv.id}
                          phx-value-answer-id={block.answer_id}
                          aria-label="+0.25"
                          class="inline-flex items-center justify-center w-7 h-7 rounded-full text-stone-500 hover:bg-stone-100 hover:text-stone-700 transition-colors duration-150 shrink-0"
                        >
                          <.icon name="hero-plus" class="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="p-5 border-t border-stone-100 space-y-4">
                  <label class="flex items-start gap-3 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={pv.auto_correct}
                      phx-click="toggle_auto_correct"
                      phx-value-part-id={pv.id}
                      class="mt-0.5 w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150 shrink-0"
                    />
                    <span class="min-w-0">
                      <span class="block text-sm font-medium text-stone-700">Auto-Korrektur</span>
                      <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                        Diese Aufgabe wird beim Start der Auto-Korrektur automatisch bewertet.
                      </span>
                    </span>
                  </label>

                  <label class={[
                    "flex items-start gap-3",
                    if(pv.auto_correct, do: "cursor-pointer", else: "cursor-not-allowed opacity-40")
                  ]}>
                    <input
                      type="checkbox"
                      checked={pv.ignore_case}
                      disabled={!pv.auto_correct}
                      phx-click="toggle_ignore_case"
                      phx-value-part-id={pv.id}
                      class="mt-0.5 w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 transition-colors duration-150 shrink-0 disabled:cursor-not-allowed"
                    />
                    <span class="min-w-0">
                      <span class="block text-sm font-medium text-stone-700">
                        Gross-/Kleinschreibung ignorieren
                      </span>
                      <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                        Bei der Auto-Korrektur dieser Aufgabe wird Gross-/Kleinschreibung nicht bewertet.
                      </span>
                    </span>
                  </label>

                  <label class={[
                    "flex items-start gap-3",
                    if(pv.auto_correct, do: "cursor-pointer", else: "cursor-not-allowed opacity-40")
                  ]}>
                    <input
                      type="checkbox"
                      checked={pv.ignore_spelling}
                      disabled={!pv.auto_correct}
                      phx-click="toggle_ignore_spelling"
                      phx-value-part-id={pv.id}
                      class="mt-0.5 w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 transition-colors duration-150 shrink-0 disabled:cursor-not-allowed"
                    />
                    <span class="min-w-0">
                      <span class="block text-sm font-medium text-stone-700">
                        Rechtschreibung ignorieren
                      </span>
                      <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                        Bei der Auto-Korrektur dieser Aufgabe werden Rechtschreibfehler nicht streng bewertet (Fuzzy-Matching ab Jaro-Ähnlichkeit ≥ 0,85).
                      </span>
                    </span>
                  </label>
                </div>
              </div>
            </aside>
          </div>
        </div>

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
                      – nicht für Ankreuzaufgaben.
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
                      Musterlösung – auch „Gross-/Kleinschreibung ignorieren“ und
                      „Rechtschreibung ignorieren“.
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

      custom = Map.get(exam.sample_solution_block_points || %{}, part.id) || %{}

      blocks =
        nodes
        |> Tasky.AI.NodePatcher.list_answer_blocks()
        |> Enum.map(fn entry ->
          snippet =
            case String.slice(entry.text || "", 0, 40) do
              "" -> "Antwort #{entry.index + 1}"
              s -> s
            end

          %{
            answer_id: entry.answer_id,
            snippet: snippet,
            points: Map.get(custom, entry.answer_id)
          }
        end)

      %{
        id: part.id,
        label: part.label,
        doc_json: Jason.encode!(%{"type" => "doc", "content" => nodes}),
        max_points: Map.get(exam.sample_solution_points || %{}, part.id),
        blocks: blocks,
        custom_points: map_size(custom) > 0,
        auto_correct: part_config_flag(exam, part.id, "auto_correct"),
        ignore_case: part_config_flag(exam, part.id, "ignore_case"),
        ignore_spelling: part_config_flag(exam, part.id, "ignore_spelling")
      }
    end)
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

  def handle_event("toggle_custom_block_points", %{"part-id" => part_id}, socket) do
    case part_view(socket, part_id) do
      nil ->
        {:noreply, socket}

      pv ->
        result =
          if pv.custom_points do
            Exams.clear_custom_block_points(
              socket.assigns.current_scope,
              socket.assigns.exam,
              part_id
            )
          else
            Exams.enable_custom_block_points(
              socket.assigns.current_scope,
              socket.assigns.exam,
              part_id
            )
          end

        apply_block_points_result(socket, part_id, result)
    end
  end

  def handle_event("set_block_points", params, socket) do
    %{"points" => raw, "part_id" => part_id, "answer_id" => answer_id} = params
    points = parse_points(raw) || 0

    result =
      Exams.set_sample_solution_block_point(
        socket.assigns.current_scope,
        socket.assigns.exam,
        part_id,
        answer_id,
        points
      )

    apply_block_points_result(socket, part_id, result)
  end

  def handle_event("adjust_block_points", params, socket) do
    %{"direction" => dir, "part-id" => part_id, "answer-id" => answer_id} = params

    case part_view(socket, part_id) do
      nil ->
        {:noreply, socket}

      pv ->
        current =
          case Enum.find(pv.blocks, &(&1.answer_id == answer_id)) do
            %{points: p} when is_number(p) -> p
            _ -> 0
          end

        delta = if dir == "up", do: 0.25, else: -0.25
        new_value = max(current + delta, 0)

        result =
          Exams.set_sample_solution_block_point(
            socket.assigns.current_scope,
            socket.assigns.exam,
            part_id,
            answer_id,
            new_value
          )

        apply_block_points_result(socket, part_id, result)
    end
  end

  def handle_event("toggle_auto_correct", %{"part-id" => part_id}, socket) do
    case part_view(socket, part_id) do
      nil ->
        {:noreply, socket}

      pv ->
        exam = socket.assigns.exam
        new_val = !pv.auto_correct
        part_config = Map.get(exam.ai_correction_config || %{}, part_id, %{})

        updated_part_config =
          part_config
          |> Map.put("auto_correct", new_val)
          |> then(fn cfg ->
            if new_val,
              do: cfg,
              else: cfg |> Map.put("ignore_spelling", false) |> Map.put("ignore_case", false)
          end)

        case Exams.update_ai_correction_config(
               socket.assigns.current_scope,
               exam,
               part_id,
               updated_part_config
             ) do
          {:ok, updated_exam} ->
            changes =
              if new_val,
                do: %{auto_correct: true},
                else: %{auto_correct: false, ignore_case: false, ignore_spelling: false}

            {:noreply,
             socket
             |> assign(:exam, updated_exam)
             |> update_part_view(part_id, changes)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Einstellung konnte nicht gespeichert werden.")}
        end
    end
  end

  def handle_event("toggle_ignore_case", %{"part-id" => part_id}, socket) do
    toggle_flag_if_auto(socket, part_id, "ignore_case", :ignore_case)
  end

  def handle_event("toggle_ignore_spelling", %{"part-id" => part_id}, socket) do
    toggle_flag_if_auto(socket, part_id, "ignore_spelling", :ignore_spelling)
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

  defp toggle_flag_if_auto(socket, part_id, config_key, view_key) do
    pv = part_view(socket, part_id)

    if pv && pv.auto_correct do
      exam = socket.assigns.exam
      new_val = !Map.fetch!(pv, view_key)
      part_config = Map.get(exam.ai_correction_config || %{}, part_id, %{})
      updated = Map.put(part_config, config_key, new_val)

      case Exams.update_ai_correction_config(socket.assigns.current_scope, exam, part_id, updated) do
        {:ok, updated_exam} ->
          {:noreply,
           socket
           |> assign(:exam, updated_exam)
           |> update_part_view(part_id, %{view_key => new_val})}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Einstellung konnte nicht gespeichert werden.")}
      end
    else
      {:noreply, socket}
    end
  end

  # Refreshes the part view's block points, custom flag and (derived) total
  # from the freshly updated exam.
  defp apply_block_points_result(socket, part_id, result) do
    case result do
      {:ok, updated_exam} ->
        custom = Map.get(updated_exam.sample_solution_block_points || %{}, part_id) || %{}
        pv = part_view(socket, part_id)

        blocks =
          Enum.map(pv.blocks, fn b -> %{b | points: Map.get(custom, b.answer_id)} end)

        {:noreply,
         socket
         |> assign(:exam, updated_exam)
         |> update_part_view(part_id, %{
           blocks: blocks,
           custom_points: map_size(custom) > 0,
           max_points: Map.get(updated_exam.sample_solution_points || %{}, part_id)
         })}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Punkte konnten nicht gespeichert werden.")}
    end
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
