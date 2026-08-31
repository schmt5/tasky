defmodule TaskyWeb.ExamLive.Cockpit do
  use TaskyWeb, :live_view

  import TaskyWeb.ExamComponents, only: [seb_derivation_alert: 1]

  alias Tasky.Exams
  alias TaskyWeb.Params
  alias TaskyWeb.SebGuard

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Cockpit"}
            ]} />
          </div>

          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3 mb-3">
              <.back_button
                navigate={~p"/exams/#{@exam}"}
                tooltip={"Zurück zu #{@exam.name}"}
              />
              <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
                Cockpit
              </h1>
            </div>

            <div class="flex items-center gap-3">
              <.link
                :if={@exam.status in ["open", "running"]}
                navigate={~p"/exams/#{@exam}/cockpit/config"}
                id="cockpit-config-btn"
                class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-sm font-semibold px-5 py-2.5 rounded-xl transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 active:scale-[0.98]"
              >
                <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Konfigurieren
              </.link>

              <button
                :if={@assigned_mode? and @exam.status in ["open", "running"]}
                type="button"
                id="add-participants-btn"
                phx-click="open_assign"
                class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-sm font-semibold px-5 py-2.5 rounded-xl transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 active:scale-[0.98]"
              >
                <.icon name="hero-user-plus" class="w-4 h-4" /> Lernende zuweisen
              </button>

              <%= if @exam.status == "open" do %>
                <button
                  type="button"
                  phx-click="show_confirm"
                  phx-value-action="start_exam"
                  class="inline-flex items-center gap-2 bg-emerald-500 text-white text-sm font-semibold px-5 py-2.5 rounded-xl shadow-[0_2px_8px_rgba(16,185,129,0.25)] transition-all duration-150 hover:bg-emerald-600 active:scale-[0.98]"
                >
                  <.icon name="hero-play" class="w-4 h-4" /> Prüfung starten
                </button>
              <% end %>
              <%= if @exam.status == "running" do %>
                <button
                  type="button"
                  phx-click="show_confirm"
                  phx-value-action="end_exam"
                  class="inline-flex items-center gap-2 bg-red-500 text-white text-sm font-semibold px-5 py-2.5 rounded-xl shadow-[0_2px_8px_rgba(239,68,68,0.25)] transition-all duration-150 hover:bg-red-600 active:scale-[0.98]"
                >
                  <.icon name="hero-stop" class="w-4 h-4" /> Prüfung beenden
                </button>
              <% end %>
              <%!-- Recovery from a misclicked "Prüfung beenden". Deliberately
                    quiet: it is a way back, not a step forward. --%>
              <%= if @exam.status == "finished" do %>
                <button
                  type="button"
                  phx-click="show_confirm"
                  phx-value-action="reopen_exam"
                  class="inline-flex items-center gap-2 text-stone-500 text-sm font-semibold px-4 py-2.5 rounded-xl border border-stone-200 transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
                >
                  <.icon name="hero-arrow-uturn-left" class="w-4 h-4" /> Prüfung wieder öffnen
                </button>
              <% end %>
            </div>
          </div>

          <.exam_status_chip status={@exam.status} />
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <%= if @anonymous_mode? and @exam.status != "finished" do %>
          <%!-- Enrollment Token Card --%>
          <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-[10px] flex items-center justify-center shrink-0 bg-amber-50 text-amber-500">
                  <.icon name="hero-key" class="w-5 h-5" />
                </div>
                <div>
                  <h2 class="text-lg font-semibold text-stone-800">Einschreibelink</h2>
                  <p class="text-sm text-stone-500 mt-0.5">
                    Teile diesen Link mit allen, die an der Prüfung teilnehmen sollen.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6">
              <%= if @exam.enrollment_token do %>
                <div class="flex items-center gap-3">
                  <input
                    id="enrollment-token-field"
                    type="text"
                    value={url(~p"/guest/enroll/#{@exam.enrollment_token}")}
                    readonly
                    class="flex-1 font-mono text-sm text-stone-700 bg-stone-50 border border-stone-200 rounded-lg px-4 py-2.5 focus:outline-none focus:ring-2 focus:ring-amber-300 focus:border-amber-400 select-all cursor-text"
                    phx-hook=".CopyToClipboard"
                  />
                  <button
                    id="copy-token-btn"
                    type="button"
                    phx-hook=".CopyButton"
                    data-target="enrollment-token-field"
                    class="inline-flex items-center gap-2 bg-amber-500 text-white text-sm font-semibold px-4 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(245,158,11,0.25)] transition-all duration-150 hover:bg-amber-600 active:scale-[0.98]"
                  >
                    <.icon name="hero-clipboard-document" class="w-4 h-4" />
                    <span class="copy-label">Kopieren</span>
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if @exam.status == "finished" do %>
          <%!-- Correction Ready Card --%>
          <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
            <div class="p-6">
              <div class="flex items-center justify-between gap-4">
                <div class="flex items-center gap-3">
                  <div class="w-10 h-10 rounded-[10px] flex items-center justify-center shrink-0 bg-purple-50 text-purple-500">
                    <.icon name="hero-clipboard-document-check" class="w-5 h-5" />
                  </div>
                  <div>
                    <h2 class="text-lg font-semibold text-stone-800">Prüfung beendet</h2>
                    <p class="text-sm text-stone-500 mt-0.5">
                      Die Prüfung kann jetzt korrigiert werden.
                    </p>
                  </div>
                </div>
                <.link
                  navigate={~p"/exams/#{@exam}/correction"}
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4" /> Zur Korrektur
                </.link>
              </div>
            </div>
          </div>
        <% end %>

        <.seb_derivation_alert :if={@seb_derivation_error} message={@seb_derivation_error} />

        <%!-- Submissions Card (no overflow-hidden: lets the per-row actions
              dropdown extend past the card edge without being clipped). --%>
        <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6 border-b border-stone-100">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-[10px] flex items-center justify-center shrink-0 bg-blue-50 text-blue-500">
                  <.icon name="hero-users" class="w-5 h-5" />
                </div>
                <div>
                  <h2 class="text-lg font-semibold text-stone-800">Teilnehmende</h2>
                  <p class="text-sm text-stone-500 mt-0.5">
                    <%= if @assigned_mode? do %>
                      Wer dieser Prüfung zugewiesen ist.
                    <% else %>
                      Wer sich für diese Prüfung eingeschrieben hat.
                    <% end %>
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <span class="inline-flex items-center gap-1.5 bg-emerald-50 text-emerald-700 text-sm font-semibold px-3 py-1.5 rounded-full">
                  <span class="w-2 h-2 rounded-full bg-emerald-400" />
                  {map_size(@present)} online
                </span>
                <%!-- Two counters, not one: "im SEB" used to count a
                      spoofable user-agent string and report it as a green
                      shield. Verified means the Config Key hash checked out. --%>
                <%= if @exam.seb_enabled do %>
                  <span class="inline-flex items-center gap-1.5 bg-emerald-50 text-emerald-700 text-sm font-semibold px-3 py-1.5 rounded-full">
                    <.icon name="hero-shield-check-mini" class="w-4 h-4" />
                    {seb_verified_count(@present)} verifiziert
                  </span>
                  <span
                    :if={seb_unverified_count(@present) > 0}
                    class="inline-flex items-center gap-1.5 bg-amber-50 text-amber-700 text-sm font-semibold px-3 py-1.5 rounded-full"
                  >
                    <.icon name="hero-exclamation-triangle-mini" class="w-4 h-4" />
                    {seb_unverified_count(@present)} ohne SEB-Schlüssel
                  </span>
                <% end %>
                <span class="inline-flex items-center gap-1.5 bg-blue-50 text-blue-700 text-sm font-semibold px-3 py-1.5 rounded-full">
                  <.icon name="hero-user-group-mini" class="w-4 h-4" />
                  {@submissions_count}
                </span>
              </div>
            </div>
          </div>
          <div class="p-6">
            <div id="submissions" phx-update="stream">
              <div
                id="submissions-empty"
                class="hidden only:flex flex-col items-center justify-center py-12 text-stone-400"
              >
                <.icon name="hero-user-group" class="w-10 h-10 mb-3 text-stone-300" />
                <p class="text-sm font-medium">
                  <%= if @assigned_mode? do %>
                    Noch keine Teilnehmenden zugewiesen.
                  <% else %>
                    Noch keine Teilnehmenden eingeschrieben.
                  <% end %>
                </p>
              </div>
              <div
                :for={{id, submission} <- @streams.submissions}
                id={id}
                class="flex items-center gap-4 px-4 py-3 -mx-4 rounded-lg hover:bg-stone-50 transition-colors duration-150 group"
              >
                <div class="relative shrink-0">
                  <.participant_avatar person={submission} />
                  <% {dot_class, label_class, label} =
                    presence_label(@present, submission, @exam) %>
                  <div class={[
                    "absolute -bottom-0.5 -right-0.5 w-3.5 h-3.5 rounded-full border-2 border-white",
                    dot_class
                  ]} />
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-semibold text-stone-800 truncate">
                    {submission.firstname} {submission.lastname}
                  </p>
                  <p class="text-xs mt-0.5">
                    <span class={["font-medium", label_class]}>{label}</span>
                    <span :if={not @assigned_mode?} class="text-stone-300 mx-1">·</span>
                    <span :if={not @assigned_mode?} class="text-stone-400">
                      Eingeschrieben am {Calendar.strftime(
                        submission.inserted_at,
                        "%d.%m.%Y um %H:%M"
                      )}
                    </span>
                  </p>
                </div>
                <div class="dropdown dropdown-end opacity-0 group-hover:opacity-100 focus-within:opacity-100 transition-opacity duration-150">
                  <label
                    tabindex="0"
                    aria-label="Aktionen"
                    class="cursor-pointer flex items-center justify-center w-8 h-8 rounded-lg text-stone-400 transition-colors duration-150 hover:bg-stone-100 hover:text-stone-700"
                  >
                    <.icon name="hero-ellipsis-vertical" class="w-5 h-5" />
                  </label>
                  <%!-- The exam_token is a cookie-less bearer credential for this
                        submission. Handing it to a human defeats the point of an
                        assigned session, so it is neither offered nor put in the
                        DOM in that mode. --%>
                  <input
                    :if={@anonymous_mode?}
                    id={"resume-link-#{submission.exam_token}"}
                    type="text"
                    value={url(~p"/guest/exam/#{submission.exam_token}")}
                    readonly
                    aria-hidden="true"
                    tabindex="-1"
                    class="sr-only"
                  />
                  <ul
                    tabindex="0"
                    class="dropdown-content z-[60] menu p-2 shadow-lg bg-white rounded-[10px] w-60 mt-2 border border-stone-100"
                  >
                    <li :if={@anonymous_mode?}>
                      <button
                        id={"resume-copy-#{submission.exam_token}"}
                        type="button"
                        phx-hook=".CopyMenuItem"
                        data-target={"resume-link-#{submission.exam_token}"}
                        class="flex items-center gap-2 text-sm text-stone-700"
                      >
                        <.icon name="hero-link" class="copy-icon w-4 h-4 text-stone-400" />
                        <span class="copy-label">Teilnahmelink kopieren</span>
                      </button>
                    </li>
                    <li :if={@assigned_mode? and not submission.submitted}>
                      <button
                        id={"unassign-#{submission.id}"}
                        type="button"
                        phx-click="unassign_student"
                        phx-value-submission_id={submission.id}
                        data-confirm={unassign_confirm(submission)}
                        class="flex items-center gap-2 text-sm text-red-600"
                      >
                        <.icon name="hero-user-minus" class="w-4 h-4 text-red-400" />
                        <span>Zuweisung entfernen</span>
                      </button>
                    </li>
                  </ul>
                </div>
                <%= if submission.submitted do %>
                  <div class="flex flex-col items-end gap-1 shrink-0">
                    <span class="inline-flex items-center gap-1.5 bg-purple-50 text-purple-700 text-xs font-semibold px-2.5 py-1 rounded-full">
                      <.icon name="hero-check-circle-mini" class="w-3.5 h-3.5" /> Abgegeben
                    </span>
                    <%!-- The hand-in time, not updated_at: auto-correction during
                          a running exam moves updated_at past the hand-in. --%>
                    <span :if={submission.submitted_at} class="text-[11px] text-stone-400">
                      {Calendar.strftime(submission.submitted_at, "%d.%m.%Y, %H:%M")}
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Start Exam Confirmation Modal --%>
      <%= if @confirm_action == :start_exam do %>
        <dialog
          id="start-exam-modal"
          class="modal modal-open"
          phx-window-keydown="close_confirm"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_confirm"></div>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-emerald-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-play" class="w-5 h-5 text-emerald-600" />
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-stone-800">Prüfung starten</h3>
                  <p class="text-xs text-stone-400 mt-0.5">
                    Diese Aktion kann nicht rückgängig gemacht werden.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6">
              <p class="text-sm text-stone-600 leading-relaxed">
                Möchtest du die Prüfung <span class="font-semibold text-stone-800">{@exam.name}</span>
                jetzt starten?
                <%= if @assigned_mode? do %>
                  Alle zugewiesenen Teilnehmenden erhalten sofort Zugang zu den Aufgaben.
                <% else %>
                  Alle eingeschriebenen Teilnehmenden erhalten sofort Zugang zu den Aufgaben.
                <% end %>
              </p>
              <div class="bg-amber-50 rounded-lg p-3 mt-4 border border-amber-100">
                <div class="flex items-start gap-2.5">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-4 h-4 text-amber-500 shrink-0 mt-0.5"
                  />
                  <p class="text-xs text-amber-700 leading-relaxed">
                    Der Start lässt sich nicht rückgängig machen.
                    <%= if @assigned_mode? do %>
                      Weitere Lernende kannst du auch während der Prüfung noch zuweisen.
                    <% else %>
                      Wer sich mit dem Einschreibelink später anmeldet, kommt direkt in die
                      laufende Prüfung.
                    <% end %>
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6 pt-0 flex items-center justify-end gap-3">
              <button
                type="button"
                phx-click="close_confirm"
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Abbrechen
              </button>
              <button
                type="button"
                phx-click="confirm_action"
                class="inline-flex items-center gap-2 bg-emerald-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(16,185,129,0.25)] transition-all duration-150 hover:bg-emerald-600 active:scale-[0.98]"
              >
                <.icon name="hero-play" class="w-4 h-4" /> Jetzt starten
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <%!-- End Exam Confirmation Modal --%>
      <%= if @confirm_action == :end_exam do %>
        <dialog
          id="end-exam-modal"
          class="modal modal-open"
          phx-window-keydown="close_confirm"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_confirm"></div>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-red-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-stop" class="w-5 h-5 text-red-600" />
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-stone-800">Prüfung beenden</h3>
                  <p class="text-xs text-stone-400 mt-0.5">
                    Danach im Notfall wieder zu öffnen.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6">
              <p class="text-sm text-stone-600 leading-relaxed">
                Möchtest du die Prüfung <span class="font-semibold text-stone-800">{@exam.name}</span>
                jetzt beenden?
                Alle Teilnehmenden werden sofort von der Prüfung getrennt.
              </p>
              <div class="bg-red-50 rounded-lg p-3 mt-4 border border-red-100">
                <div class="flex items-start gap-2.5">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-4 h-4 text-red-500 shrink-0 mt-0.5"
                  />
                  <p class="text-xs text-red-700 leading-relaxed">
                    Nach dem Beenden können Teilnehmende keine Änderungen mehr vornehmen.
                    Wer bis dahin nicht abgegeben hat, wird mit dem letzten
                    automatisch gespeicherten Stand korrigiert.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6 pt-0 flex items-center justify-end gap-3">
              <button
                type="button"
                phx-click="close_confirm"
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Abbrechen
              </button>
              <button
                type="button"
                phx-click="confirm_action"
                class="inline-flex items-center gap-2 bg-red-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(239,68,68,0.25)] transition-all duration-150 hover:bg-red-600 active:scale-[0.98]"
              >
                <.icon name="hero-stop" class="w-4 h-4" /> Jetzt beenden
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <%= if @confirm_action == :reopen_exam do %>
        <dialog
          id="reopen-exam-modal"
          class="modal modal-open"
          phx-window-keydown="close_confirm"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_confirm"></div>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-amber-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-arrow-uturn-left" class="w-5 h-5 text-amber-600" />
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-stone-800">Prüfung wieder öffnen</h3>
                  <p class="text-xs text-stone-400 mt-0.5">Für den Fall eines Fehlklicks.</p>
                </div>
              </div>
            </div>
            <div class="p-6">
              <p class="text-sm text-stone-600 leading-relaxed">
                Möchtest du <span class="font-semibold text-stone-800">{@exam.name}</span>
                wieder öffnen?
              </p>
              <div class="bg-amber-50 rounded-lg p-3 mt-4 border border-amber-100">
                <div class="flex items-start gap-2.5">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-4 h-4 text-amber-500 shrink-0 mt-0.5"
                  />
                  <p class="text-xs text-amber-800 leading-relaxed">
                    Wer noch nicht abgegeben hat, kann danach wieder schreiben und
                    abgeben. Bereits abgegebene Arbeiten bleiben abgegeben, und
                    bereits erfasste Korrekturen bleiben erhalten.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6 pt-0 flex items-center justify-end gap-3">
              <button
                type="button"
                phx-click="close_confirm"
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Abbrechen
              </button>
              <button
                type="button"
                phx-click="confirm_action"
                class="inline-flex items-center gap-2 bg-amber-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(245,158,11,0.25)] transition-all duration-150 hover:bg-amber-600 active:scale-[0.98]"
              >
                <.icon name="hero-arrow-uturn-left" class="w-4 h-4" /> Wieder öffnen
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <%!-- Participant Assignment Modal --%>
      <%= if @show_assign? and @assigned_mode? and @exam.status in ["open", "running"] do %>
        <dialog
          id="assign-participants-modal"
          class="modal modal-open"
          phx-window-keydown="close_assign"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_assign"></div>
          <div class="modal-box max-w-xl p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center justify-between gap-3">
                <div class="flex items-center gap-3">
                  <div class="w-10 h-10 rounded-[10px] flex items-center justify-center shrink-0 bg-sky-50 text-sky-500">
                    <.icon name="hero-user-plus" class="w-5 h-5" />
                  </div>
                  <div>
                    <h3 class="text-lg font-semibold text-stone-800">Lernende auswählen</h3>
                    <p class="text-sm text-stone-500 mt-0.5">
                      Zugewiesene Lernende sehen die Prüfung auf ihrem Dashboard.
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  id="close-assign-modal-btn"
                  phx-click="close_assign"
                  class="shrink-0 text-stone-400 p-1.5 rounded-lg transition-colors duration-150 hover:text-stone-600 hover:bg-stone-50"
                  aria-label="Schliessen"
                >
                  <.icon name="hero-x-mark" class="w-5 h-5" />
                </button>
              </div>
            </div>
            <div class="p-6 space-y-4">
              <.form for={%{}} phx-change="filter_by_class" id="assign-class-filter">
                <.input
                  type="select"
                  name="class_id"
                  value={@class_filter}
                  label="Klasse"
                  prompt="Alle Klassen"
                  options={@class_options}
                />
              </.form>

              <%= if @class_filter && @assignable != [] do %>
                <div class="flex items-center justify-between gap-4 bg-sky-50 border border-sky-100 rounded-xl px-4 py-3">
                  <p class="text-sm text-sky-900">
                    {length(@assignable)} Lernende dieser Klasse sind noch nicht zugewiesen.
                  </p>
                  <button
                    type="button"
                    id="assign-all-btn"
                    phx-click="assign_all_from_class"
                    class="inline-flex items-center gap-2 shrink-0 bg-sky-500 text-white text-sm font-semibold px-4 py-2 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                  >
                    <.icon name="hero-user-plus" class="w-4 h-4" /> Alle zuweisen
                  </button>
                </div>
              <% end %>

              <div class="max-h-72 overflow-y-auto -mx-2 px-2">
                <%= if @assignable == [] do %>
                  <p class="text-sm text-stone-400 py-6 text-center">
                    Keine weiteren Lernenden zum Zuweisen.
                  </p>
                <% else %>
                  <div
                    :for={student <- @assignable}
                    class="flex items-center gap-3 px-2 py-2 rounded-lg hover:bg-stone-50 transition-colors duration-150"
                  >
                    <.participant_avatar person={student} size="sm" />
                    <div class="flex-1 min-w-0">
                      <p class="text-sm font-medium text-stone-800 truncate">
                        {student.firstname} {student.lastname}
                      </p>
                      <p class="text-xs text-stone-400 truncate">{student.email}</p>
                    </div>
                    <button
                      type="button"
                      id={"assign-student-#{student.id}"}
                      phx-click="assign_student"
                      phx-value-student_id={student.id}
                      class="inline-flex items-center gap-1.5 shrink-0 text-[13px] font-semibold text-sky-600 border border-sky-200 px-3 py-1.5 rounded-lg transition-colors duration-150 hover:bg-sky-50 hover:border-sky-300 active:scale-[0.98]"
                    >
                      <.icon name="hero-plus" class="w-3.5 h-3.5" /> Zuweisen
                    </button>
                  </div>
                <% end %>
              </div>
            </div>
            <div class="p-6 pt-0 flex items-center justify-end">
              <button
                type="button"
                phx-click="close_assign"
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Fertig
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              this.el.select();
            });
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyButton">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const targetId = this.el.getAttribute("data-target");
              const input = document.getElementById(targetId);
              if (!input) return;

              const IDLE = ["bg-amber-500", "hover:bg-amber-600"];
              const DONE = ["bg-emerald-500", "hover:bg-emerald-600"];
              const FAIL = ["bg-stone-500", "hover:bg-stone-600"];

              const span = this.el.querySelector(".copy-label");
              if (!span) return;
              const original = this._orig || span.textContent;
              this._orig = original;

              const flash = (label, classes) => {
                span.textContent = label;
                this.el.classList.remove(...IDLE);
                this.el.classList.add(...classes);
                if (this._t) clearTimeout(this._t);
                this._t = setTimeout(() => {
                  span.textContent = original;
                  this.el.classList.remove(...classes);
                  this.el.classList.add(...IDLE);
                  this._t = null;
                }, 2000);
              };

              navigator.clipboard
                .writeText(input.value)
                .then(() => flash("Kopiert!", DONE))
                .catch(() => {
                  // Clipboard denied (permission, insecure context): select the
                  // field so Ctrl/Cmd+C still works.
                  input.focus();
                  input.select();
                  flash("Bitte manuell kopieren", FAIL);
                });
            });
          },
          destroyed() {
            if (this._t) clearTimeout(this._t);
          },
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyMenuItem">
        export default {
          mounted() {
            const label = this.el.querySelector(".copy-label");
            this._orig = label ? label.textContent : "";
            this.el.addEventListener("click", () => {
              const input = document.getElementById(this.el.getAttribute("data-target"));
              if (!input || !label) return;
              const flash = (text) => {
                label.textContent = text;
                label.classList.add("text-sky-600", "font-medium");
                if (this._t) clearTimeout(this._t);
                this._t = setTimeout(() => {
                  label.textContent = this._orig;
                  label.classList.remove("text-sky-600", "font-medium");
                  this._t = null;
                }, 1500);
              };

              navigator.clipboard
                .writeText(input.value)
                .then(() => flash("Kopiert!"))
                .catch(() => flash("Kopieren nicht möglich"));
            });
          },
          destroyed() {
            if (this._t) clearTimeout(this._t);
          },
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    if connected?(socket) do
      Exams.subscribe_exam(exam.id)
      Phoenix.PubSub.subscribe(Tasky.PubSub, "exam_waiting:#{exam.id}")
      Phoenix.PubSub.subscribe(Tasky.PubSub, "exam_cockpit:#{exam.id}")
    end

    submissions = Exams.list_exam_submissions(exam)

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Cockpit")
     |> assign(:exam, exam)
     |> assign(:assigned_mode?, Exams.assigned_mode?(exam))
     |> assign(:anonymous_mode?, Exams.anonymous_mode?(exam))
     |> assign(:submissions_count, length(submissions))
     |> assign(:present, presence_state(exam.id))
     |> assign(:confirm_action, nil)
     |> assign(:show_assign?, false)
     |> assign(:class_filter, nil)
     |> assign(:class_options, class_options(socket.assigns.current_scope))
     |> assign(:seb_derivation_error, SebGuard.derivation_error(exam))
     |> assign_assignable()
     |> stream(:submissions, submissions)}
  end

  # Only assigned sessions have anything to assign; the query is skipped
  # entirely for anonymous ones.
  defp assign_assignable(socket) do
    exam = socket.assigns.exam

    assignable =
      if Exams.assigned_mode?(exam) and exam.status in ["open", "running"] do
        Exams.list_assignable_students(exam, socket.assigns.class_filter)
      else
        []
      end

    assign(socket, :assignable, assignable)
  end

  defp class_options(scope) do
    Enum.map(Tasky.Classes.list_classes(scope), &{&1.name, &1.id})
  end

  defp unassign_confirm(%{content: content}) when is_map(content) and map_size(content) > 0 do
    "Diese Person hat bereits Antworten erfasst. Zuweisung samt Antworten wirklich entfernen?"
  end

  defp unassign_confirm(_submission), do: "Zuweisung wirklich entfernen?"

  # Map of present exam_token => %{in_seb: bool}. A participant counts as in SEB
  # if any of their tracked sessions reports it (e.g. the SEB window alongside a
  # still-open gate tab).
  defp presence_state(exam_id) do
    TaskyWeb.Presence.list("exam_waiting:#{exam_id}")
    |> Map.new(fn {token, %{metas: metas}} ->
      {token,
       %{
         in_seb: Enum.any?(metas, & &1[:in_seb]),
         # `in_seb` is a user-agent sniff and a participant can set it to
         # anything. `seb_state` is what the Config Key check concluded, and it
         # is the only one of the two worth acting on.
         seb_state: best_seb_state(metas)
       }}
    end)
  end

  @seb_state_rank %{verified: 3, stamped: 2, unverified: 1}

  # One participant can hold several sockets (a reload leaves the old one
  # briefly alive); take the best state among them.
  defp best_seb_state(metas) do
    metas
    |> Enum.map(&(&1[:seb_state] || :unverified))
    |> Enum.max_by(&Map.get(@seb_state_rank, &1, 0), fn -> :unverified end)
  end

  # Returns {dot_class, label_class, label} for a participant's presence state.
  # gray = absent, yellow = online but SEB not yet started, green = present.
  #
  # The green label depends on the exam status: before the start everyone sits in
  # the waiting room, afterwards they are working on the exam. It used to say
  # "Im Warteraum" for the whole run, which read like nobody had been let in.
  #
  # An absent participant with no answers yet never showed up at all — which is
  # a normal state for an assigned exam, unlike someone who dropped off midway.
  defp presence_label(present, submission, exam) do
    case Map.get(present, submission.exam_token) do
      nil ->
        if never_started?(submission) do
          {"bg-stone-300", "text-stone-400", "Noch nicht begonnen"}
        else
          {"bg-stone-300", "text-stone-400", "Abwesend"}
        end

      %{seb_state: :unverified, in_seb: false} when exam.seb_enabled ->
        {"bg-yellow-400", "text-yellow-600", "SEB noch nicht gestartet"}

      # Claims to be SEB but sent no valid Config Key hash. Either a stale
      # `.seb` file or a spoofed user agent — worth the teacher's attention
      # either way, and it used to render as a green shield.
      %{seb_state: :unverified, in_seb: true} when exam.seb_enabled ->
        {"bg-amber-400", "text-amber-600", "SEB nicht verifiziert"}

      _ ->
        {"bg-emerald-400", "text-emerald-500", present_label(exam.status, submission)}
    end
  end

  # Someone who has already handed in is not working on anything — the row's
  # "Abgegeben" chip says the rest.
  defp present_label(_status, %{submitted: true}), do: "Online"
  defp present_label("open", _submission), do: "Im Warteraum"
  defp present_label("running", _submission), do: "In Bearbeitung"
  defp present_label(_status, _submission), do: "Online"

  defp seb_verified_count(present),
    do: present |> Map.values() |> Enum.count(&(&1.seb_state != :unverified))

  defp seb_unverified_count(present),
    do: present |> Map.values() |> Enum.count(&(&1.seb_state == :unverified))

  defp never_started?(%{submitted: false, content: content}) when is_map(content),
    do: map_size(content) == 0

  defp never_started?(_submission), do: false

  # Re-streams every submission. Both the presence dot and the status label are
  # computed inside the stream item, and a stream does not re-render items it has
  # already sent just because another assign changed — so a reset is the only way
  # to get a new label onto an existing row.
  #
  # The counter is recomputed here too: a fresh anonymous enrolment produces no
  # signal other than the presence join (EnrollLive redirects straight into the
  # exam), and the number used to stay at its mount value while the list below it
  # grew.
  defp refresh_submissions(socket) do
    submissions = Exams.list_exam_submissions(socket.assigns.exam)

    socket
    |> assign(:present, presence_state(socket.assigns.exam.id))
    |> assign(:submissions_count, length(submissions))
    |> stream(:submissions, submissions, reset: true)
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, refresh_submissions(socket)}
  end

  # Every status change lands here, including the one this cockpit triggered
  # itself — PubSub.broadcast/3 delivers to the sender as well. Without this the
  # labels froze at the status of the last render: a running exam kept reading
  # "Im Warteraum", and a second cockpit tab never learned about the start at all.
  #
  # :exam has to be assigned before the re-stream so presence_label/3 sees the new
  # status, and assign_assignable/1 has to re-run because it keys off the status.
  def handle_info({:exam_status_changed, exam}, socket) do
    {:noreply,
     socket
     |> assign(:exam, exam)
     |> assign_assignable()
     |> refresh_submissions()}
  end

  def handle_info({:submission_submitted, submission}, socket) do
    {:noreply, stream_insert(socket, :submissions, submission)}
  end

  @impl true
  def handle_event("open_assign", _params, socket) do
    {:noreply, assign(socket, :show_assign?, true)}
  end

  def handle_event("close_assign", _params, socket) do
    {:noreply, assign(socket, :show_assign?, false)}
  end

  def handle_event("filter_by_class", %{"class_id" => raw}, socket) do
    {:noreply,
     socket
     |> assign(:class_filter, Params.int(raw))
     |> assign_assignable()}
  end

  def handle_event("assign_student", %{"student_id" => raw}, socket) do
    case Exams.assign_student(socket.assigns.current_scope, socket.assigns.exam, Params.int(raw)) do
      {:ok, submission} ->
        {:noreply,
         socket
         |> stream_insert(:submissions, submission)
         |> assign(:submissions_count, socket.assigns.submissions_count + 1)
         |> assign_assignable()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, assign_error_message(reason))}
    end
  end

  def handle_event("assign_all_from_class", _params, socket) do
    case socket.assigns.class_filter do
      nil ->
        {:noreply, socket}

      class_id ->
        case Exams.assign_students_from_class(
               socket.assigns.current_scope,
               socket.assigns.exam,
               class_id
             ) do
          {:ok, %{assigned: assigned, skipped: skipped}} ->
            submissions = Exams.list_exam_submissions(socket.assigns.exam)

            {:noreply,
             socket
             |> assign(:submissions_count, length(submissions))
             |> stream(:submissions, submissions, reset: true)
             |> assign_assignable()
             |> put_flash(:info, assign_all_message(assigned, skipped))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, assign_error_message(reason))}
        end
    end
  end

  def handle_event("unassign_student", %{"submission_id" => raw}, socket) do
    exam = socket.assigns.exam

    with id when not is_nil(id) <- Params.int(raw),
         submission when not is_nil(submission) <- Exams.get_submission(exam, id),
         {:ok, _} <- Exams.unassign_student(socket.assigns.current_scope, exam, submission) do
      {:noreply,
       socket
       |> stream_delete(:submissions, submission)
       |> assign(:submissions_count, max(socket.assigns.submissions_count - 1, 0))
       |> assign_assignable()}
    else
      {:error, :already_submitted} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Diese Prüfung wurde bereits abgegeben und kann nicht mehr entfernt werden."
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Zuweisung konnte nicht entfernt werden.")}
    end
  end

  def handle_event("show_confirm", %{"action" => action}, socket) do
    # Explicit whitelist: client params must never mint or crash on atoms.
    confirm_action =
      case action do
        "start_exam" -> :start_exam
        "reopen_exam" -> :reopen_exam
        "end_exam" -> :end_exam
        _ -> nil
      end

    {:noreply, assign(socket, :confirm_action, confirm_action)}
  end

  def handle_event("close_confirm", _params, socket) do
    {:noreply, assign(socket, :confirm_action, nil)}
  end

  # Every confirmable action is the same shape: one status transition, one
  # message when it fails, sometimes one when it succeeds. Spelling them out
  # three times made the differences hard to see and the function hard to
  # extend — the reopen action was the third copy.
  @confirmable_actions %{
    start_exam: %{
      status: "running",
      error: "Prüfung konnte nicht gestartet werden."
    },
    end_exam: %{
      status: "finished",
      error: "Prüfung konnte nicht beendet werden."
    },
    reopen_exam: %{
      status: "running",
      error: "Prüfung konnte nicht wieder geöffnet werden.",
      info: "Prüfung ist wieder offen. Teilnehmende können weiterschreiben."
    }
  }

  def handle_event("confirm_action", _params, socket) do
    case Map.fetch(@confirmable_actions, socket.assigns.confirm_action) do
      {:ok, action} -> transition(socket, action)
      :error -> {:noreply, assign(socket, :confirm_action, nil)}
    end
  end

  defp transition(socket, action) do
    result =
      Exams.update_exam_status(
        socket.assigns.current_scope,
        socket.assigns.exam,
        action.status
      )

    socket = assign(socket, :confirm_action, nil)

    case result do
      {:ok, exam} ->
        socket = assign(socket, :exam, exam)

        case action do
          %{info: info} -> {:noreply, put_flash(socket, :info, info)}
          _ -> {:noreply, socket}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, action.error)}
    end
  end

  defp assign_all_message(assigned, 0), do: "#{assigned_word(assigned)} zugewiesen."

  defp assign_all_message(assigned, skipped),
    do: "#{assigned_word(assigned)} zugewiesen, #{skipped} übersprungen."

  defp assigned_word(1), do: "1 Teilnehmer:in"
  defp assigned_word(n), do: "#{n} Teilnehmende"

  defp assign_error_message(:not_assigned_mode),
    do: "Diese Durchführung läuft mit dem Einschreibelink."

  defp assign_error_message(:exam_not_open), do: "Die Durchführung ist nicht offen."
  defp assign_error_message(:not_a_student), do: "Nur Lernende können zugewiesen werden."

  defp assign_error_message(%Ecto.Changeset{}),
    do: "Diese Person ist der Prüfung bereits zugewiesen."

  defp assign_error_message(_), do: "Zuweisung fehlgeschlagen."
end
