defmodule TaskyWeb.Guest.ExamLive do
  use TaskyWeb, :live_view

  import TaskyWeb.FileComponents
  import TaskyWeb.StudentComponents

  alias Tasky.Exams
  alias Tasky.Uploads
  alias TaskyWeb.Params

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.guest flash={@flash}>
      <%= if @not_found do %>
        <%!-- Invalid / expired exam link (unknown token, e.g. a stale resume
              link to a deleted submission). --%>
        <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
          <div class="w-full max-w-md text-center">
            <div class="w-16 h-16 rounded-2xl bg-stone-100 flex items-center justify-center mx-auto mb-4">
              <.icon name="hero-link-slash" class="w-8 h-8 text-stone-400" />
            </div>
            <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
              Link ungültig
            </h1>
            <p class="text-stone-500 text-sm leading-relaxed">
              Dieser Prüfungslink ist ungültig oder abgelaufen. Bitte melde dich
              erneut über den Einschreibelink an oder wende dich an deine Lehrperson.
            </p>
          </div>
        </div>
      <% else %>
        <%!-- Stores this submission's token in the browser so the enroll page can
              offer a "continue" link after an accidental tab close (same browser). --%>
        <div
          id="exam-resume-point"
          phx-hook=".ResumePoint"
          data-exam-id={@exam.id}
          data-token={@submission.exam_token}
          data-firstname={@submission.firstname}
          data-lastname={@submission.lastname}
          data-submitted={to_string(@submission.submitted)}
          hidden
        />
        <%= cond do %>
          <% @exam.seb_enabled and not @in_seb and not @submission.submitted and @exam.status in ["open", "running"] -> %>
            <%!-- SEB Required Gate --%>
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
                  <div class="bg-sky-50 rounded-xl p-4 border border-sky-100">
                    <div class="flex items-start gap-3">
                      <.icon
                        name="hero-information-circle"
                        class="w-5 h-5 text-sky-500 shrink-0 mt-0.5"
                      />
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
                    href={~p"/guest/exam/#{@submission.exam_token}/seb-config"}
                    id="open-in-seb-btn"
                    class="w-full inline-flex items-center justify-center gap-2.5 bg-sky-500 text-white text-sm font-semibold px-6 py-3.5 rounded-xl shadow-[0_2px_12px_rgba(14,165,233,0.3)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                  >
                    <.icon name="hero-shield-check" class="w-5 h-5" /> Im Safe Exam Browser öffnen
                  </a>
                </div>
              </div>
            </div>
          <% @exam.status == "open" -> %>
            <%!-- Waiting Room --%>
            <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
              <div class="w-full max-w-lg">
                <div class="text-center mb-8">
                  <div class="w-16 h-16 rounded-2xl bg-amber-50 flex items-center justify-center mx-auto mb-4">
                    <.icon name="hero-clock" class="w-8 h-8 text-amber-500 animate-pulse" />
                  </div>
                  <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
                    Warteraum
                  </h1>
                  <p class="text-stone-500 text-sm">
                    Hallo <span class="font-semibold text-stone-700">{@submission.firstname} {@submission.lastname}</span>,
                    du bist im Warteraum für die Prüfung.
                  </p>
                </div>

                <%!-- Exam Info Card --%>
                <div class="bg-white rounded-2xl border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-6 mb-6">
                  <div class="flex items-center gap-3 mb-4">
                    <div class="w-10 h-10 rounded-xl bg-sky-50 flex items-center justify-center shrink-0">
                      <.icon name="hero-academic-cap" class="w-5 h-5 text-sky-500" />
                    </div>
                    <div>
                      <h2 class="text-lg font-semibold text-stone-800">{@exam.name}</h2>
                      <p class="text-xs text-stone-400">Lehrperson: {@exam.teacher.email}</p>
                    </div>
                  </div>

                  <div class="bg-amber-50 rounded-xl p-4 border border-amber-100">
                    <div class="flex items-start gap-3">
                      <.icon
                        name="hero-information-circle"
                        class="w-5 h-5 text-amber-500 shrink-0 mt-0.5"
                      />
                      <p class="text-sm text-amber-700 leading-relaxed">
                        Die Prüfung hat noch nicht begonnen. Bitte warte, bis die Lehrperson die Prüfung startet.
                        Diese Seite wird sich automatisch aktualisieren.
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% @exam.status == "running" and @submission.submitted -> %>
            <%!-- Already Submitted --%>
            <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
              <div class="text-center">
                <div class="w-16 h-16 rounded-2xl bg-emerald-50 flex items-center justify-center mx-auto mb-4">
                  <.icon name="hero-check-circle" class="w-8 h-8 text-emerald-500" />
                </div>
                <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
                  Prüfung abgegeben
                </h1>
                <p class="text-stone-500 text-sm">
                  Du hast deine Prüfung <span class="font-semibold text-stone-700">{@exam.name}</span>
                  erfolgreich abgegeben.
                </p>
                <p class="text-stone-500 text-sm mt-1">
                  Abgegeben am {Calendar.strftime(@submission.updated_at, "%d.%m.%Y um %H:%M")} Uhr.
                </p>
                <p class="text-stone-400 text-xs mt-2">
                  Du kannst diese Seite jetzt schliessen.
                </p>
                <%= if @exam.seb_enabled and @in_seb do %>
                  <a
                    href={~p"/guest/exam/#{@submission.exam_token}/seb-quit"}
                    id="quit-seb-btn"
                    class="mt-6 inline-flex items-center gap-2 bg-stone-800 text-white text-sm font-semibold px-6 py-3 rounded-xl shadow-md transition-all duration-150 hover:bg-stone-900 active:scale-[0.98]"
                  >
                    <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" /> SEB beenden
                  </a>
                <% end %>
              </div>
            </div>
          <% @exam.status == "running" -> %>
            <%!-- Running Exam --%>
            <div class="bg-white min-h-screen">
              <div class="sticky top-0 z-50 bg-white h-[54px] flex items-center px-5">
                <div class="max-w-4xl mx-auto w-full flex items-center justify-between gap-4">
                  <h1 class="text-base font-semibold text-stone-900 truncate">
                    {@exam.name}
                  </h1>
                  <div
                    :if={@has_files}
                    class="inline-flex items-center gap-0.5 bg-sky-100/70 rounded-lg p-0.5 shrink-0"
                  >
                    <.student_tab_button
                      label="Prüfung"
                      tab="pruefung"
                      active={@student_tab == "pruefung"}
                    />
                    <.student_tab_button
                      label="Dateien"
                      tab="dateien"
                      active={@student_tab == "dateien"}
                    />
                  </div>
                  <button
                    id="submit-exam-btn"
                    type="button"
                    phx-click="show_submit_modal"
                    class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                  >
                    <.icon name="hero-paper-airplane" class="w-4 h-4" /> Abgeben
                  </button>
                </div>
              </div>
              <%!-- Prüfung tab: hidden via CSS (never unmounted) so the
                  phx-update="ignore" editor keeps its DOM and state. --%>
              <div class={@student_tab != "pruefung" && "hidden"}>
                <%!-- Exam Content --%>
                <div
                  id={"exam-submission-editor-#{@submission.id}"}
                  phx-hook="ExamSubmissionEditor"
                  phx-update="ignore"
                  data-exam-token={@submission.exam_token}
                  data-content={@content_json}
                >
                </div>
              </div>

              <%!-- Dateien tab: also CSS-hidden so in-flight uploads survive
                  switching back to the exam. --%>
              <div
                :if={@has_files}
                class={[
                  "bg-stone-100 min-h-[calc(100vh-54px)]",
                  @student_tab != "dateien" && "hidden"
                ]}
              >
                <div class="max-w-4xl mx-auto px-5 py-8 space-y-6">
                  <%!-- Anhänge (downloads) --%>
                  <div
                    :if={@attachments != []}
                    class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]"
                  >
                    <div class="p-6">
                      <div class="flex items-center gap-2.5">
                        <.icon name="hero-paper-clip" class="w-5 h-5 text-sky-500" />
                        <h2 class="text-lg font-semibold text-stone-800">Anhänge</h2>
                      </div>
                      <p class="text-sm text-stone-500 mt-1">
                        Dateien zur Prüfung, die du herunterladen kannst.
                      </p>
                    </div>
                    <div class="px-6 pb-6 space-y-2.5">
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
                          href={
                            ~p"/uploads/exams/#{@exam.id}/attachments/#{attachment.stored_filename}"
                          }
                          target="_blank"
                          rel="noopener"
                          class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-sm font-semibold px-3.5 py-2 rounded-lg transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 shrink-0"
                        >
                          <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Herunterladen
                        </a>
                      </div>
                    </div>
                  </div>

                  <%!-- Datei-Abgaben (answer uploads) --%>
                  <div
                    :if={@upload_fields != []}
                    class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]"
                  >
                    <div class="p-6">
                      <div class="flex items-center gap-2.5">
                        <.icon name="hero-arrow-up-tray" class="w-5 h-5 text-sky-500" />
                        <h2 class="text-lg font-semibold text-stone-800">Datei-Abgaben</h2>
                      </div>
                      <p class="text-sm text-stone-500 mt-1">
                        Lade hier deine Antwort-Dateien hoch. Eine Datei pro Feld.
                      </p>
                    </div>
                    <div class="px-6 pb-6 space-y-4">
                      <div
                        :for={field <- @upload_fields}
                        class="rounded-xl border border-stone-200 px-5 py-4"
                      >
                        <div class="flex items-center gap-2.5 flex-wrap">
                          <h3 class="text-base font-semibold text-stone-800">{field.label}</h3>
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
                        <div class="flex items-center gap-1.5 mt-2 flex-wrap">
                          <span class="text-xs text-stone-400 mr-1">Erlaubte Dateitypen:</span>
                          <span
                            :for={type <- field.allowed_types}
                            class="text-[11px] font-semibold text-stone-600 bg-stone-100 rounded-md px-2 py-0.5"
                          >
                            {type_chip_label(type)}
                          </span>
                        </div>

                        <% upload_config = @uploads[field_upload_name(field.id)] %>
                        <% uploaded_file = @submission_files[field.id] %>

                        <%!-- In-flight upload --%>
                        <div
                          :for={entry <- upload_config.entries}
                          class="mt-3 rounded-lg border border-stone-200 bg-stone-50/60 px-4 py-3"
                        >
                          <div class="flex items-center gap-3">
                            <p class="flex-1 min-w-0 text-sm font-medium text-stone-700 truncate">
                              {entry.client_name}
                            </p>
                            <%= if upload_errors(upload_config, entry) == [] do %>
                              <progress
                                class="progress progress-info w-32"
                                value={entry.progress}
                                max="100"
                              >
                              </progress>
                            <% end %>
                            <button
                              type="button"
                              phx-click="cancel_answer_upload"
                              phx-value-ref={entry.ref}
                              phx-value-field-id={field.id}
                              aria-label="Upload abbrechen"
                              class="inline-flex items-center justify-center w-7 h-7 rounded-full text-stone-400 hover:bg-stone-100 hover:text-stone-600 transition-colors duration-150 shrink-0"
                            >
                              <.icon name="hero-x-mark" class="w-4 h-4" />
                            </button>
                          </div>
                          <p
                            :for={err <- upload_errors(upload_config, entry)}
                            class="text-xs text-red-600 mt-1.5"
                          >
                            {upload_error_message(err)}
                          </p>
                        </div>

                        <%!-- Uploaded file --%>
                        <div
                          :if={uploaded_file && upload_config.entries == []}
                          class="mt-3 flex items-center gap-4 rounded-lg border border-emerald-200 bg-emerald-50/40 px-4 py-3"
                        >
                          <.file_badge filename={uploaded_file.stored_filename} />
                          <div class="flex-1 min-w-0">
                            <p class="text-sm font-semibold text-stone-800 truncate">
                              {uploaded_file.original_name}
                            </p>
                            <p class="text-xs text-stone-500 mt-0.5">
                              Hochgeladen · {Uploads.format_size(uploaded_file.size)}
                            </p>
                          </div>
                          <a
                            href={~p"/guest/exam/#{@submission.exam_token}/files/#{field.id}"}
                            target="_blank"
                            rel="noopener"
                            aria-label="Datei herunterladen"
                            class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-400 hover:bg-stone-100 hover:text-stone-600 transition-colors duration-150 shrink-0"
                          >
                            <.icon name="hero-arrow-down-tray" class="w-4 h-4" />
                          </a>
                          <button
                            type="button"
                            phx-click="delete_answer_file"
                            phx-value-field-id={field.id}
                            data-confirm={"Datei «#{uploaded_file.original_name}» wirklich löschen?"}
                            aria-label="Datei löschen"
                            class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-400 hover:bg-red-50 hover:text-red-500 transition-colors duration-150 shrink-0"
                          >
                            <.icon name="hero-trash" class="w-4 h-4" />
                          </button>
                        </div>

                        <%!-- Upload input (also used to replace an existing file) --%>
                        <form
                          phx-change="validate_answer_upload"
                          class="mt-3"
                          phx-drop-target={upload_config.ref}
                        >
                          <label class={[
                            "flex items-center justify-center gap-2 rounded-lg cursor-pointer transition-all duration-150 text-sm font-semibold px-4",
                            if(uploaded_file,
                              do:
                                "border border-stone-200 text-stone-500 py-2 hover:bg-stone-50 hover:border-stone-300",
                              else:
                                "border-2 border-dashed border-stone-300 text-stone-500 py-5 hover:border-sky-400 hover:text-sky-600"
                            )
                          ]}>
                            <.icon name="hero-arrow-up-tray" class="w-4 h-4" />
                            {if uploaded_file,
                              do: "Datei ersetzen",
                              else: "Datei auswählen oder hierher ziehen"}
                            <.live_file_input upload={upload_config} class="hidden" />
                          </label>
                        </form>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Submit Confirmation Modal --%>
              <%= if @show_submit_modal do %>
                <dialog
                  id="submit-exam-modal"
                  class="modal modal-open"
                  phx-window-keydown="close_submit_modal"
                  phx-key="escape"
                >
                  <div class="modal-backdrop bg-stone-900/50" phx-click="close_submit_modal"></div>
                  <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
                    <div class="p-6 border-b border-stone-100">
                      <div class="flex items-center gap-3">
                        <div class="w-10 h-10 rounded-xl bg-amber-50 flex items-center justify-center shrink-0">
                          <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-amber-500" />
                        </div>
                        <div>
                          <h3 class="text-lg font-semibold text-stone-800">Prüfung abgeben</h3>
                          <p class="text-xs text-stone-400 mt-0.5">Bitte bestätige die Abgabe.</p>
                        </div>
                      </div>
                    </div>
                    <div class="p-6">
                      <%= case @submit_check do %>
                        <% :checking -> %>
                          <div id="submit-check-pending" class="flex items-center gap-3 py-2">
                            <span class="loading loading-spinner loading-sm text-sky-500"></span>
                            <p class="text-sm text-stone-600 leading-relaxed">
                              Deine Antworten werden gespeichert …
                            </p>
                          </div>
                        <% :ok -> %>
                          <p class="text-sm text-stone-600 leading-relaxed">
                            Möchtest du die Prüfung
                            <span class="font-semibold text-stone-800">{@exam.name}</span>
                            jetzt abgeben?
                          </p>
                          <div class="bg-amber-50 rounded-lg p-3 mt-4 border border-amber-100">
                            <div class="flex items-start gap-2.5">
                              <.icon
                                name="hero-exclamation-triangle"
                                class="w-4 h-4 text-amber-500 shrink-0 mt-0.5"
                              />
                              <p class="text-xs text-amber-700 leading-relaxed">
                                Nach der Abgabe kannst du keine Änderungen mehr vornehmen.
                              </p>
                            </div>
                          </div>
                        <% :error -> %>
                          <div
                            id="submit-check-error"
                            class="bg-red-50 rounded-lg p-3 border border-red-100"
                          >
                            <div class="flex items-start gap-2.5">
                              <.icon
                                name="hero-exclamation-circle"
                                class="w-4 h-4 text-red-500 shrink-0 mt-0.5"
                              />
                              <p class="text-xs text-red-700 leading-relaxed">
                                Deine letzten Änderungen konnten nicht gespeichert werden.
                                Prüfe deine Internetverbindung und versuche es erneut.
                                Du kannst die Prüfung erst abgeben, wenn alle Antworten
                                gespeichert sind.
                              </p>
                            </div>
                          </div>
                      <% end %>

                      <div
                        :if={@missing_uploads != []}
                        id="missing-uploads-warning"
                        class="bg-red-50 rounded-lg p-3 mt-4 border border-red-100"
                      >
                        <div class="flex items-start gap-2.5">
                          <.icon
                            name="hero-exclamation-circle"
                            class="w-4 h-4 text-red-500 shrink-0 mt-0.5"
                          />
                          <div class="text-xs text-red-700 leading-relaxed">
                            <p class="font-semibold mb-1">
                              Folgende Datei-Abgaben fehlen noch (Pflicht):
                            </p>
                            <ul class="list-disc list-inside space-y-0.5">
                              <li :for={field <- @missing_uploads}>{field.label}</li>
                            </ul>
                            <p class="mt-1.5">
                              Lade die Dateien im Tab «Dateien» hoch, bevor du abgibst.
                            </p>
                          </div>
                        </div>
                      </div>
                    </div>
                    <div class="p-6 pt-0 flex items-center justify-end gap-3">
                      <button
                        id="cancel-submit-btn"
                        type="button"
                        phx-click="close_submit_modal"
                        class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
                      >
                        Abbrechen
                      </button>
                      <%= if @submit_check == :error do %>
                        <button
                          id="retry-submit-check-btn"
                          type="button"
                          phx-click="retry_submit_check"
                          class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-sm font-semibold px-4 py-2.5 rounded-lg transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 active:scale-[0.98]"
                        >
                          <.icon name="hero-arrow-path" class="w-4 h-4" /> Erneut versuchen
                        </button>
                      <% end %>
                      <button
                        id="confirm-submit-btn"
                        type="button"
                        phx-click="confirm_submit_exam"
                        disabled={@submit_check != :ok or @missing_uploads != []}
                        class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-50 disabled:pointer-events-none"
                      >
                        <.icon name="hero-paper-airplane" class="w-4 h-4" /> Jetzt abgeben
                      </button>
                    </div>
                  </div>
                </dialog>
              <% end %>
            </div>
          <% @exam.status in ["finished", "archived"] -> %>
            <%!-- Finished --%>
            <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
              <div class="text-center">
                <div class="w-16 h-16 rounded-2xl bg-purple-50 flex items-center justify-center mx-auto mb-4">
                  <.icon name="hero-check-circle" class="w-8 h-8 text-purple-500" />
                </div>
                <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
                  Prüfung beendet
                </h1>
                <p class="text-stone-500 text-sm">
                  Die Prüfung <span class="font-semibold text-stone-700">{@exam.name}</span>
                  wurde beendet.
                </p>
                <%= if @exam.seb_enabled and @in_seb do %>
                  <a
                    href={~p"/guest/exam/#{@submission.exam_token}/seb-quit"}
                    id="quit-seb-btn"
                    class="mt-6 inline-flex items-center gap-2 bg-stone-800 text-white text-sm font-semibold px-6 py-3 rounded-xl shadow-md transition-all duration-150 hover:bg-stone-900 active:scale-[0.98]"
                  >
                    <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5" /> SEB beenden
                  </a>
                <% end %>
              </div>
            </div>
          <% true -> %>
            <%!-- Fallback (draft or other) --%>
            <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
              <div class="text-center">
                <div class="w-16 h-16 rounded-2xl bg-stone-100 flex items-center justify-center mx-auto mb-4">
                  <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-stone-400" />
                </div>
                <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
                  Prüfung nicht verfügbar
                </h1>
                <p class="text-stone-500 text-sm">
                  Diese Prüfung ist aktuell nicht verfügbar.
                </p>
              </div>
            </div>
        <% end %>
      <% end %>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ResumePoint">
        export default {
          sync() {
            const examId = this.el.dataset.examId;
            if (!examId) return;
            const key = "tasky:resume:" + examId;
            if (this.el.dataset.submitted === "true") {
              localStorage.removeItem(key);
              return;
            }
            localStorage.setItem(
              key,
              JSON.stringify({
                token: this.el.dataset.token,
                firstname: this.el.dataset.firstname,
                lastname: this.el.dataset.lastname,
              }),
            );
          },
          mounted() {
            this.sync();
          },
          updated() {
            this.sync();
          },
        }
      </script>
    </Layouts.guest>
    """
  end

  @impl true
  def mount(%{"exam_token" => exam_token}, _session, socket) do
    case Exams.get_exam_submission_by_token(exam_token) do
      nil -> mount_not_found(socket)
      submission -> mount_if_own(submission, socket)
    end
  end

  # The token is the credential — it has to be, because the Safe Exam Browser
  # starts without a session cookie and this is the only entry point that works
  # there. But when a session *is* present we can do better than trusting the
  # token alone: a logged-in student opening someone else's submission is
  # refused. A cookie-less request (SEB, or an anonymous participant) has no
  # scope and falls through unchanged.
  defp mount_if_own(submission, socket) do
    case socket.assigns[:current_scope] do
      %{user: %{role: "student", id: user_id}}
      when not is_nil(submission.user_id) and submission.user_id != user_id ->
        mount_not_found(socket)

      _ ->
        mount_submission(submission, socket)
    end
  end

  defp mount_not_found(socket) do
    {:ok,
     socket
     |> assign(:page_title, "Link ungültig")
     |> assign(:not_found, true)}
  end

  defp mount_submission(submission, socket) do
    exam = submission.exam

    in_seb =
      if connected?(socket) do
        case get_connect_info(socket, :user_agent) do
          ua when is_binary(ua) -> String.contains?(ua, "SEB")
          _ -> false
        end
      else
        false
      end

    if connected?(socket) do
      Exams.subscribe_exam(exam.id)

      if exam.status in ["open", "running"] do
        {:ok, _} =
          TaskyWeb.Presence.track(
            self(),
            "exam_waiting:#{exam.id}",
            submission.exam_token,
            %{
              firstname: submission.firstname,
              lastname: submission.lastname,
              in_seb: in_seb
            }
          )
      end
    end

    initial_content =
      case submission.content do
        content when is_map(content) and map_size(content) > 0 -> content
        _ -> exam.content || %{}
      end

    content_json = Jason.encode!(initial_content)

    attachments = Exams.list_exam_attachments(exam)
    upload_fields = Exams.list_upload_fields(exam)

    socket =
      socket
      |> assign(:not_found, false)
      |> assign(:page_title, exam.name)
      |> assign(:exam, exam)
      |> assign(:submission, submission)
      |> assign(:content_json, content_json)
      |> assign(:show_submit_modal, false)
      |> assign(:submit_check, :checking)
      |> assign(:in_seb, in_seb)
      |> assign(:attachments, attachments)
      |> assign(:upload_fields, upload_fields)
      |> assign(:has_files, attachments != [] or upload_fields != [])
      |> assign(:student_tab, "pruefung")
      |> assign(:submission_files, submission_files_by_field(submission))
      |> assign(:missing_uploads, [])

    socket =
      Enum.reduce(upload_fields, socket, fn field, sock ->
        allow_upload(sock, field_upload_name(field.id),
          accept: Uploads.accept_exts(field.allowed_types),
          max_entries: 1,
          max_file_size: Uploads.max_file_bytes(),
          auto_upload: true,
          progress: &handle_answer_progress/3
        )
      end)

    {:ok, socket}
  end

  defp submission_files_by_field(submission) do
    submission
    |> Exams.list_submission_files()
    |> Map.new(&{&1.upload_field_id, &1})
  end

  defp field_upload_name(field_id), do: :"answer_field_#{field_id}"

  # `field-id` comes off the wire. Interpolating it straight into an atom mints
  # a permanent atom per distinct value — a guest holding nothing but a valid
  # exam token could walk the VM to its atom limit — and `cancel_upload/3`
  # raises on a name that was never `allow_upload`ed, taking a student's
  # LiveView down mid-exam. Resolve against the fields registered at mount and
  # build the name from the trusted id instead.
  defp registered_upload_name(socket, field_id) do
    with id when is_integer(id) <- Params.int(field_id),
         %{} = field <- Enum.find(socket.assigns.upload_fields, &(&1.id == id)) do
      {:ok, field_upload_name(field.id)}
    else
      _ -> :error
    end
  end

  @impl true
  def handle_event("show_submit_modal", _params, socket) do
    # Opening the modal freezes the editor behind it, so once the client
    # reports a successful flush the server provably holds the full document
    # and the submit itself needs no content payload.
    {:noreply,
     socket
     |> assign(:show_submit_modal, true)
     |> assign(:submit_check, :checking)
     |> assign(:missing_uploads, Exams.missing_required_uploads(socket.assigns.submission))
     |> push_event("flush-before-submit", %{})}
  end

  def handle_event("switch_student_tab", %{"tab" => tab}, socket)
      when tab in ["pruefung", "dateien"] do
    {:noreply, assign(socket, :student_tab, tab)}
  end

  def handle_event("validate_answer_upload", _params, socket) do
    # auto_upload does the work; this handler just accepts the phx-change.
    {:noreply, socket}
  end

  def handle_event("cancel_answer_upload", %{"ref" => ref, "field-id" => field_id}, socket) do
    case registered_upload_name(socket, field_id) do
      {:ok, name} -> {:noreply, cancel_upload(socket, name, ref)}
      :error -> {:noreply, socket}
    end
  end

  # Whether files may still change is decided by the context against the locked
  # rows, not by the `submitted` flag on this socket's struct — that one is from
  # mount, and it never covered the exam's status at all.
  def handle_event("delete_answer_file", %{"field-id" => field_id}, socket) do
    submission = socket.assigns.submission

    case field_id |> Params.int() |> then(&(&1 && Exams.get_submission_file(submission, &1))) do
      nil ->
        {:noreply, put_flash(socket, :error, "Datei konnte nicht gelöscht werden.")}

      file ->
        case Exams.delete_submission_file(submission, file) do
          {:ok, _} ->
            {:noreply, refresh_submission_files(socket)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, file_save_error_message(reason))}
        end
    end
  end

  def handle_event("submit_check_result", %{"ok" => ok}, socket) do
    {:noreply, assign(socket, :submit_check, if(ok == true, do: :ok, else: :error))}
  end

  def handle_event("retry_submit_check", _params, socket) do
    {:noreply,
     socket
     |> assign(:submit_check, :checking)
     |> assign(:missing_uploads, Exams.missing_required_uploads(socket.assigns.submission))
     |> push_event("flush-before-submit", %{})}
  end

  def handle_event("close_submit_modal", _params, socket) do
    {:noreply, assign(socket, :show_submit_modal, false)}
  end

  def handle_event("confirm_submit_exam", _params, socket) do
    submit_exam(socket)
  end

  defp submit_exam(%{assigns: %{submit_check: check}} = socket) when check != :ok do
    # Defense against stale clicks: the button is disabled unless the flush
    # check passed, but the event could still arrive from a stale DOM.
    {:noreply, socket}
  end

  defp submit_exam(socket) do
    case Exams.submit_exam_submission(socket.assigns.submission) do
      {:ok, updated_submission} ->
        {:noreply,
         socket
         |> assign(:submission, updated_submission)
         |> assign(:show_submit_modal, false)}

      {:error, :exam_not_running} ->
        {:noreply,
         socket
         |> put_flash(:error, "Die Prüfung kann nicht mehr abgegeben werden.")
         |> assign(:show_submit_modal, false)}

      # A second submit (double click, stale DOM) reaches the desired end state,
      # so show it as done rather than as a failure.
      {:error, :already_submitted} ->
        {:noreply,
         socket
         |> assign(
           :submission,
           Exams.get_submission!(socket.assigns.exam, socket.assigns.submission.id)
         )
         |> assign(:show_submit_modal, false)}

      {:error, :missing_required_uploads} ->
        {:noreply,
         assign(
           socket,
           :missing_uploads,
           Exams.missing_required_uploads(socket.assigns.submission)
         )}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Fehler beim Abgeben der Prüfung.")
         |> assign(:show_submit_modal, false)}
    end
  end

  @impl true
  def handle_info({:exam_status_changed, updated_exam}, socket) do
    {:noreply, assign(socket, :exam, updated_exam)}
  end

  # Consumes a finished answer upload: stores the bytes, upserts the
  # per-field file record (replacing an earlier upload) and refreshes the view.
  defp handle_answer_progress(name, entry, socket) do
    if entry.done? do
      %{exam: exam, submission: submission} = socket.assigns

      field_id =
        name |> Atom.to_string() |> String.replace_prefix("answer_field_", "")

      field = Enum.find(socket.assigns.upload_fields, &(to_string(&1.id) == field_id))

      if is_nil(field) or submission.submitted or exam.status != "running" do
        {:noreply, cancel_upload(socket, name, entry.ref)}
      else
        result =
          consume_uploaded_entry(socket, entry, fn %{path: path} ->
            {:ok, store_answer_file(exam, submission, field, entry, path)}
          end)

        case result do
          {:ok, _file} ->
            {:noreply, refresh_submission_files(socket)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, file_save_error_message(reason))}
        end
      end
    else
      {:noreply, socket}
    end
  end

  defp refresh_submission_files(socket) do
    socket
    |> assign(:submission_files, submission_files_by_field(socket.assigns.submission))
    |> assign(:missing_uploads, Exams.missing_required_uploads(socket.assigns.submission))
  end

  # Stores the bytes, then upserts the per-field file record. The bytes land in
  # storage first, so a refused DB write — the submission was handed in from
  # another tab, the exam stopped running — has to take them back out; nothing
  # else ever would, leaving an unreferenced object in the bucket forever.
  defp store_answer_file(exam, submission, field, entry, path) do
    with {:ok, meta} <-
           Uploads.save_submission_file(
             exam.id,
             submission.id,
             path,
             entry.client_name,
             field.allowed_types
           ) do
      case Exams.put_submission_file(
             submission,
             field,
             Map.put(meta, :original_name, entry.client_name)
           ) do
        {:ok, file} ->
          {:ok, file}

        {:error, reason} ->
          discard_stored_bytes(exam.id, submission.id, meta)
          {:error, reason}
      end
    end
  end

  # Best-effort: the upload has already failed for the student either way, so a
  # failing cleanup must not turn into a second error on top of it.
  defp discard_stored_bytes(exam_id, submission_id, %{stored_filename: stored_filename}) do
    Uploads.delete_submission_file_from_disk(exam_id, submission_id, stored_filename)
  rescue
    _ -> :ok
  end
end
