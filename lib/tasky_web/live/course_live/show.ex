defmodule TaskyWeb.CourseLive.Show do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Courses.DuplicateRunner
  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/courses/#{@course}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Kurse", navigate: ~p"/courses"},
              %{label: @course.name}
            ]} />

            <div class="flex items-center gap-2">
              <button
                type="button"
                id="share-course"
                phx-click="open_share"
                class="inline-flex items-center gap-2 text-stone-600 text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-700 active:scale-[0.98]"
              >
                <.icon name="hero-sparkles" class="w-4 h-4" /> KI-Link
              </button>

              <button
                type="button"
                id="duplicate-course"
                phx-click="open_duplicate"
                class="inline-flex items-center gap-2 text-stone-600 text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-700 active:scale-[0.98]"
              >
                <.icon name="hero-document-duplicate" class="w-4 h-4" /> Inhalt duplizieren
              </button>

              <.link
                navigate={~p"/courses/#{@course}/edit?return_to=show"}
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
              >
                <.icon name="hero-pencil" class="w-4 h-4" /> Bearbeiten
              </.link>
            </div>
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button navigate={~p"/courses"} tooltip="Zurück zu Kursen" />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              {@course.name}
            </h1>
          </div>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            {@course.description || "Keine Beschreibung verfügbar"}
          </p>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <%!-- Navigation Cards --%>
        <div class="grid grid-cols-3 gap-6">
          <%!-- Progress Card --%>
          <.link
            navigate={~p"/courses/#{@course}/progress"}
            class="group bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] transition-all duration-150 hover:shadow-[0_4px_12px_rgba(0,0,0,0.1)] hover:border-emerald-200"
          >
            <div class="p-6 flex items-start gap-4">
              <div class="w-12 h-12 rounded-[12px] flex items-center justify-center shrink-0 bg-emerald-50 text-emerald-500 group-hover:bg-emerald-100 transition-colors duration-150">
                <.icon name="hero-chart-bar" class="w-6 h-6" />
              </div>
              <div class="flex-1">
                <h3 class="text-base font-semibold text-stone-800 mb-1.5 group-hover:text-emerald-600 transition-colors duration-150">
                  Fortschritt anzeigen
                </h3>
                <p class="text-sm text-stone-500 leading-relaxed">
                  Sehen Sie den Lernfortschritt aller eingeschriebenen Lernenden im Kurs
                </p>
              </div>
              <.icon
                name="hero-arrow-right"
                class="w-5 h-5 text-stone-300 group-hover:text-emerald-500 group-hover:translate-x-1 transition-all duration-150"
              />
            </div>
          </.link>

          <%!-- Students Card --%>
          <.link
            navigate={~p"/courses/#{@course}/students"}
            class="group bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] transition-all duration-150 hover:shadow-[0_4px_12px_rgba(0,0,0,0.1)] hover:border-purple-200"
          >
            <div class="p-6 flex items-start gap-4">
              <div class="w-12 h-12 rounded-[12px] flex items-center justify-center shrink-0 bg-purple-50 text-purple-500 group-hover:bg-purple-100 transition-colors duration-150">
                <.icon name="hero-users" class="w-6 h-6" />
              </div>
              <div class="flex-1">
                <h3 class="text-base font-semibold text-stone-800 mb-1.5 group-hover:text-purple-600 transition-colors duration-150">
                  Lernende verwalten
                </h3>
                <p class="text-sm text-stone-500 leading-relaxed">
                  Lernende in den Kurs einschreiben oder aus dem Kurs ausschreiben
                </p>
              </div>
              <.icon
                name="hero-arrow-right"
                class="w-5 h-5 text-stone-300 group-hover:text-purple-500 group-hover:translate-x-1 transition-all duration-150"
              />
            </div>
          </.link>

          <%!-- Feedback Card. Bleibt auch bei geschlossenem Briefkasten sichtbar:
                bereits eingegangene Nachrichten müssen lesbar bleiben. --%>
          <.link
            navigate={~p"/courses/#{@course}/feedback"}
            class="group bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] transition-all duration-150 hover:shadow-[0_4px_12px_rgba(0,0,0,0.1)] hover:border-amber-200"
          >
            <div class="p-6 flex items-start gap-4">
              <div class="w-12 h-12 rounded-[12px] flex items-center justify-center shrink-0 bg-amber-50 text-amber-500 group-hover:bg-amber-100 transition-colors duration-150">
                <.icon name="hero-inbox" class="w-6 h-6" />
              </div>
              <div class="flex-1">
                <h3 class="text-base font-semibold text-stone-800 mb-1.5 group-hover:text-amber-600 transition-colors duration-150">
                  Feedback-Briefkasten
                </h3>
                <p class="text-sm text-stone-500 leading-relaxed">
                  {if @course.feedback_box_enabled,
                    do: "Anonyme Rückmeldungen der Lernenden zu diesem Kurs lesen",
                    else: "Der Briefkasten ist geschlossen – im Kurs bearbeiten aktivieren"}
                </p>
              </div>
              <.icon
                name="hero-arrow-right"
                class="w-5 h-5 text-stone-300 group-hover:text-amber-500 group-hover:translate-x-1 transition-all duration-150"
              />
            </div>
          </.link>
        </div>

        <%!-- Tasks Section --%>
        <%!-- No `overflow-hidden` here: it would clip the per-row actions dropdown. --%>
        <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="flex items-center justify-between p-6 border-b border-stone-100">
            <div>
              <h2 class="text-lg font-semibold text-stone-800">Lerneinheiten</h2>

              <p class="text-sm text-stone-500 mt-1">{length(@course.tasks)} Aufgaben insgesamt</p>
            </div>

            <div class="flex items-center gap-2">
              <.link
                :if={length(@course.tasks) > 1}
                navigate={~p"/courses/#{@course}/reorder"}
                class="inline-flex items-center gap-2 text-stone-600 text-sm font-semibold px-5 py-2.5 rounded-[10px] border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300"
              >
                <.icon name="hero-arrows-up-down" class="w-4 h-4" /> Sortieren
              </.link>
              <.link
                navigate={~p"/courses/#{@course}/add"}
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
              >
                <.icon name="hero-plus" class="w-4 h-4" /> Lerneinheit hinzufügen
              </.link>
            </div>
          </div>

          <ul :if={@has_tasks} id="tasks" phx-update="stream" class="list-none p-0 m-0">
            <li
              :for={{id, task} <- @streams.tasks}
              id={id}
              class="flex items-start gap-5 px-6 py-5 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 last:rounded-b-[14px] hover:bg-stone-50"
            >
              <div class="w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5 bg-sky-100 text-sky-600">
                <.icon name="hero-clipboard-document-list" class="w-5 h-5" />
              </div>

              <div class="flex-1 min-w-0 flex flex-col gap-1.5">
                <div class="flex items-center gap-2.5 flex-wrap">
                  <.link
                    navigate={~p"/tasks/#{task.id}/content"}
                    class="text-[15px] font-semibold text-stone-800 leading-[1.4] hover:text-sky-600 transition-colors"
                  >
                    {task.name}
                  </.link>

                  <.task_status_chip status={task.status} />

                  <%= if task.locked do %>
                    <span class="inline-flex items-center gap-1 text-[11px] font-semibold px-2.5 py-0.5 rounded-full whitespace-nowrap tracking-[0.01em] bg-red-100 text-red-700">
                      <.icon name="hero-lock-closed" class="w-3 h-3" /> Gesperrt
                    </span>
                  <% end %>

                  <.extended_chip :if={task.extended} />
                </div>

                <%= if task.locked do %>
                  <p class="text-[12px] text-stone-400 leading-snug mt-0.5">
                    Lernende sehen diese Aufgabe, können sie aber nicht starten.
                  </p>
                <% end %>

                <%= if task.extended do %>
                  <p class="text-[12px] text-stone-400 leading-snug mt-0.5">
                    Freiwilliger Zusatzauftrag – zählt nicht zum Pflicht-Fortschritt der Lernenden.
                  </p>
                <% end %>

                <div class="flex items-center gap-2">
                  <span class="text-[13px] text-stone-400">Position: {task.position}</span>
                </div>
              </div>

              <div class="dropdown dropdown-end shrink-0 pt-0.5">
                <label
                  id={"task-actions-#{task.id}"}
                  tabindex="0"
                  aria-label="Aktionen"
                  class="cursor-pointer flex items-center justify-center w-8 h-8 rounded-lg text-stone-400 transition-colors duration-150 hover:bg-stone-100 hover:text-stone-700"
                >
                  <.icon name="hero-ellipsis-vertical" class="w-5 h-5" />
                </label>
                <ul
                  tabindex="0"
                  class="dropdown-content z-[60] menu p-2 shadow-lg bg-white rounded-[10px] w-60 mt-2 border border-stone-100"
                >
                  <li>
                    <button
                      type="button"
                      phx-click="open_rename"
                      phx-value-id={task.id}
                      class="flex items-center gap-2 text-sm text-stone-700"
                    >
                      <.icon name="hero-pencil" class="w-4 h-4 text-stone-400" /> Bearbeiten
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      phx-click="toggle_status"
                      phx-value-id={task.id}
                      class="flex items-center gap-2 text-sm text-stone-700"
                    >
                      <%= if task.status == "draft" do %>
                        <.icon name="hero-eye" class="w-4 h-4 text-stone-400" /> Veröffentlichen
                      <% else %>
                        <.icon name="hero-eye-slash" class="w-4 h-4 text-stone-400" /> Verbergen
                      <% end %>
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      phx-click="toggle_locked"
                      phx-value-id={task.id}
                      class="flex items-center gap-2 text-sm text-stone-700"
                    >
                      <%= if task.locked do %>
                        <.icon name="hero-lock-open" class="w-4 h-4 text-stone-400" /> Freigeben
                      <% else %>
                        <.icon name="hero-lock-closed" class="w-4 h-4 text-stone-400" /> Sperren
                      <% end %>
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      phx-click={JS.push("delete_task", value: %{id: task.id}) |> hide("##{id}")}
                      data-confirm="Sind Sie sicher?"
                      class="flex items-center gap-2 text-sm text-red-600 hover:bg-red-50"
                    >
                      <.icon name="hero-trash" class="w-4 h-4" /> Löschen
                    </button>
                  </li>
                </ul>
              </div>
            </li>
          </ul>

          <div :if={!@has_tasks} class="flex flex-col items-center text-center px-8 py-16 bg-white">
            <div class="w-14 h-14 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-5">
              <.icon name="hero-clipboard-document-list" class="w-6 h-6" />
            </div>

            <h3 class="text-base font-semibold text-stone-700 mb-2">Noch keine Lerneinheiten</h3>

            <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6] mb-6">
              Fügen Sie Ihre erste Lerneinheit hinzu, um zu beginnen.
            </p>

            <.link
              navigate={~p"/courses/#{@course}/add"}
              class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
            >
              <.icon name="hero-plus" class="w-4 h-4" /> Erste Lerneinheit hinzufügen
            </.link>
          </div>
        </div>
      </div>
      <%!-- KI Share Link Modal --%>
      <%= if @share_url do %>
        <dialog
          id="share-course-modal"
          class="modal modal-open"
          phx-window-keydown="close_share"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_share"></div>
          <div class="modal-box max-w-lg p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-violet-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-sparkles" class="w-5 h-5 text-violet-600" />
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-stone-800">Kursinhalt für KI</h3>
                  <p class="text-xs text-stone-400 mt-0.5">
                    Alle Lerneinheiten als Text unter einem Link.
                  </p>
                </div>
              </div>
            </div>

            <div class="p-6 space-y-4">
              <p class="text-sm text-stone-600 leading-relaxed">
                Geben Sie diesen Link einem KI-Werkzeug, zum Beispiel mit dem Auftrag
                <span class="italic">
                  „Lies dir folgenden Kurs durch und erstelle mir Aufgaben für eine Prüfung."
                </span>
              </p>

              <div class="flex items-center gap-2">
                <input
                  type="text"
                  id="share-course-url"
                  value={@share_url}
                  readonly
                  class="flex-1 text-[13px] font-mono text-stone-700 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2.5 focus:outline-none focus:border-violet-300"
                />
                <button
                  type="button"
                  id="copy-share-url"
                  phx-click="copy_share_url"
                  phx-value-url={@share_url}
                  class="inline-flex items-center gap-2 bg-violet-500 text-white text-sm font-semibold px-4 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(139,92,246,0.25)] transition-all duration-150 hover:bg-violet-600 active:scale-[0.98]"
                >
                  <.icon name="hero-clipboard-document" class="w-4 h-4" /> Kopieren
                </button>
              </div>

              <div class="bg-amber-50 rounded-lg p-3 border border-amber-100">
                <div class="flex items-start gap-2.5">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-4 h-4 text-amber-500 shrink-0 mt-0.5"
                  />
                  <p class="text-xs text-amber-700 leading-relaxed">
                    Jede Person mit diesem Link kann den gesamten Kursinhalt lesen – auch
                    Entwürfe und noch nicht freigeschaltete Lerneinheiten. Abgaben und
                    Lernende sind nicht enthalten.
                  </p>
                </div>
              </div>
            </div>

            <div class="p-6 pt-0 flex items-center justify-end gap-3">
              <.link
                href={@share_url}
                target="_blank"
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Vorschau öffnen
              </.link>
              <button
                type="button"
                phx-click="close_share"
                class="text-sm font-semibold text-stone-600 px-5 py-2.5 rounded-lg border border-stone-200 transition-colors duration-150 hover:bg-stone-50"
              >
                Schliessen
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <%!-- Duplicate Course Confirmation Modal --%>
      <%= if @duplicating_course do %>
        <dialog
          id="duplicate-course-modal"
          class="modal modal-open"
          phx-window-keydown="close_duplicate"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_duplicate"></div>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-sky-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-document-duplicate" class="w-5 h-5 text-sky-600" />
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-stone-800">Inhalt duplizieren</h3>
                  <p class="text-xs text-stone-400 mt-0.5">Es entsteht ein neuer Kurs.</p>
                </div>
              </div>
            </div>
            <div class="p-6">
              <p class="text-sm text-stone-600 leading-relaxed">
                Kopie von <span class="font-semibold text-stone-800">{@course.name}</span>
                mit allen Lerneinheiten erstellen?
              </p>
              <div class="bg-amber-50 rounded-lg p-3 mt-4 border border-amber-100">
                <div class="flex items-start gap-2.5">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-4 h-4 text-amber-500 shrink-0 mt-0.5"
                  />
                  <p class="text-xs text-amber-700 leading-relaxed">
                    Lernende und Abgaben werden nicht kopiert.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6 pt-0 flex items-center justify-end gap-3">
              <button
                type="button"
                phx-click="close_duplicate"
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Abbrechen
              </button>
              <button
                type="button"
                id="confirm-duplicate-course"
                phx-click="duplicate_course"
                phx-disable-with="Wird dupliziert…"
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <.icon name="hero-document-duplicate" class="w-4 h-4" /> Duplizieren
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <%!-- Duplicate Progress Modal — the records are already committed, so
           there is deliberately no way to cancel or dismiss this. --%>
      <%= if @duplicate_status do %>
        <dialog id="duplicate-progress-modal" class="modal modal-open">
          <div class="modal-backdrop bg-stone-900/50"></div>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-sky-50 flex items-center justify-center shrink-0">
                  <.icon
                    name="hero-arrow-path"
                    class="w-5 h-5 text-sky-600 motion-safe:animate-spin"
                  />
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-stone-800">Kurs wird dupliziert</h3>
                  <p class="text-xs text-stone-400 mt-0.5">Die Dateien werden kopiert.</p>
                </div>
              </div>
            </div>
            <div class="p-6">
              <div class="flex items-center justify-between text-sm text-stone-600">
                <span>Dateien</span>
                <span class="font-semibold text-stone-800 tabular-nums">
                  {@duplicate_status.done}/{@duplicate_status.total}
                </span>
              </div>
              <div
                class="mt-3 h-2 w-full rounded-full bg-stone-100 overflow-hidden"
                role="progressbar"
                aria-valuemin="0"
                aria-valuemax={@duplicate_status.total}
                aria-valuenow={@duplicate_status.done}
                aria-label="Fortschritt beim Kopieren der Dateien"
              >
                <div
                  class="h-full rounded-full bg-sky-500 transition-[width] duration-300"
                  style={"width: #{duplicate_percent(@duplicate_status)}%"}
                >
                </div>
              </div>
            </div>
          </div>
        </dialog>
      <% end %>

      <%!-- Rename Modal --%>
      <%= if @renaming_task do %>
        <dialog
          id="rename-task-modal"
          class="modal modal-open"
          phx-window-keydown="close_rename"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_rename"></div>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <h3 class="text-lg font-semibold text-stone-800">Lerneinheit bearbeiten</h3>
            </div>

            <.form
              for={@rename_form}
              id="rename-task-form"
              phx-change="validate_rename"
              phx-submit="save_rename"
            >
              <div class="p-6 space-y-5">
                <.input
                  field={@rename_form[:name]}
                  type="text"
                  label="Name der Lerneinheit"
                  required
                  maxlength="255"
                  phx-mounted={JS.focus()}
                />

                <.checkbox_field
                  field={@rename_form[:extended]}
                  accent="violet"
                  label="Erweiterte Lerneinheit"
                  description="Markiert die Lerneinheit für Lernende als freiwillige Erweiterung."
                />
              </div>

              <div class="flex items-center justify-end gap-3 px-6 pb-6">
                <button
                  type="button"
                  phx-click="close_rename"
                  class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
                >
                  Abbrechen
                </button>
                <button
                  type="submit"
                  phx-disable-with="Speichert…"
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Speichern
                </button>
              </div>
            </.form>
          </div>
        </dialog>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    course = Courses.get_course!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, course.name)
     |> assign(:course, course)
     |> assign(:has_tasks, course.tasks != [])
     |> assign(:renaming_task, nil)
     |> assign(:rename_form, nil)
     |> assign(:duplicating_course, false)
     |> assign(:duplicate_status, nil)
     |> assign(:share_url, nil)
     |> stream(:tasks, course.tasks)}
  end

  @impl true
  def handle_event("open_share", _params, socket) do
    case Courses.ensure_share_slug(socket.assigns.current_scope, socket.assigns.course) do
      {:ok, course} ->
        {:noreply,
         socket
         |> assign(:course, course)
         |> assign(:share_url, url(~p"/share/course/#{course.share_slug}"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Der Link konnte nicht erstellt werden.")}
    end
  end

  @impl true
  def handle_event("close_share", _params, socket) do
    {:noreply, assign(socket, :share_url, nil)}
  end

  @impl true
  def handle_event("copy_share_url", %{"url" => share_url}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Link wurde in die Zwischenablage kopiert!")
     |> push_event("copy-to-clipboard", %{text: share_url})}
  end

  @impl true
  def handle_event("open_duplicate", _params, socket) do
    {:noreply, assign(socket, :duplicating_course, true)}
  end

  @impl true
  def handle_event("close_duplicate", _params, socket) do
    {:noreply, assign(socket, :duplicating_course, false)}
  end

  @impl true
  def handle_event("duplicate_course", _params, socket) do
    case DuplicateRunner.start(
           socket.assigns.current_scope,
           socket.assigns.course,
           "Kopie von — #{socket.assigns.course.name}",
           self()
         ) do
      # Nothing to copy — the duplicate is already complete, so skip the
      # progress dialog entirely and navigate as this always has.
      {:ok, course, 0} ->
        {:noreply,
         socket
         |> put_flash(:info, "Inhalt wurde in einen neuen Kurs dupliziert.")
         |> push_navigate(to: ~p"/courses/#{course}")}

      {:ok, course, total} ->
        {:noreply,
         socket
         |> assign(:duplicating_course, false)
         |> assign(:duplicate_status, %{course_id: course.id, done: 0, total: total})}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:duplicating_course, false)
         |> put_flash(:error, "Inhalt konnte nicht dupliziert werden.")}
    end
  end

  @impl true
  def handle_event("delete_task", %{"id" => id}, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)
    {:ok, _} = Tasks.delete_task(socket.assigns.current_scope, task)

    course = Courses.get_course!(socket.assigns.current_scope, socket.assigns.course.id)

    {:noreply,
     socket
     |> assign(:course, course)
     |> assign(:has_tasks, course.tasks != [])
     |> stream_delete(:tasks, task)}
  end

  @impl true
  def handle_event("toggle_locked", %{"id" => id}, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)
    {:ok, updated_task} = Tasks.toggle_locked(socket.assigns.current_scope, task)

    {:noreply, stream_insert(socket, :tasks, updated_task)}
  end

  @impl true
  def handle_event("toggle_status", %{"id" => id}, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)
    new_status = if task.status == "draft", do: "published", else: "draft"

    {:ok, updated_task} =
      Tasks.update_task(socket.assigns.current_scope, task, %{status: new_status})

    {:noreply, stream_insert(socket, :tasks, updated_task)}
  end

  @impl true
  def handle_event("open_rename", %{"id" => id}, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)
    changeset = Tasks.change_task(socket.assigns.current_scope, task)

    {:noreply,
     socket
     |> assign(:renaming_task, task)
     |> assign(:rename_form, to_form(changeset, as: :task))}
  end

  @impl true
  def handle_event("validate_rename", %{"task" => task_params}, socket) do
    changeset =
      Tasks.change_task(socket.assigns.current_scope, socket.assigns.renaming_task, task_params)

    {:noreply, assign(socket, :rename_form, to_form(changeset, action: :validate, as: :task))}
  end

  @impl true
  def handle_event("save_rename", %{"task" => params}, socket) do
    task = socket.assigns.renaming_task

    attrs = %{
      name: params |> Map.get("name", "") |> String.trim(),
      extended: params["extended"] == "true"
    }

    case Tasks.update_task(socket.assigns.current_scope, task, attrs) do
      {:ok, updated_task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lerneinheit «#{updated_task.name}» gespeichert.")
         |> assign(:renaming_task, nil)
         |> assign(:rename_form, nil)
         |> stream_insert(:tasks, updated_task)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :rename_form, to_form(changeset, as: :task))}
    end
  end

  @impl true
  def handle_event("close_rename", _params, socket) do
    {:noreply, socket |> assign(:renaming_task, nil) |> assign(:rename_form, nil)}
  end

  @impl true
  def handle_info({:duplicate_progress, status}, socket) do
    {:noreply, update(socket, :duplicate_status, &(&1 && Map.merge(&1, status)))}
  end

  @impl true
  def handle_info({:duplicate_done, %{course_id: course_id, failed: failed}}, socket) do
    # The records are committed either way — a copy failure is reported, not
    # treated as a failed duplication. `:warning` is not rendered by
    # `Layouts.flash_group/1`, so the count rides along in the :info text.
    message =
      if failed == 0 do
        "Inhalt wurde in einen neuen Kurs dupliziert."
      else
        "Inhalt dupliziert — #{failed} Datei(en) konnten nicht kopiert werden."
      end

    {:noreply,
     socket
     |> assign(:duplicate_status, nil)
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/courses/#{course_id}")}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp duplicate_percent(%{total: total}) when total <= 0, do: 100
  defp duplicate_percent(%{done: done, total: total}), do: round(done / total * 100)
end
