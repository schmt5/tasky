defmodule TaskyWeb.Student.TaskLive do
  @moduledoc """
  Student view of a learning unit (task): the Tiptap doc with the teacher's
  content locked and only answer fields editable, teacher attachments to
  download, upload slots for file answers, and the "mark as complete" flow
  with teacher review states (approved / sent back).
  """
  use TaskyWeb, :live_view

  import TaskyWeb.FileComponents
  import TaskyWeb.StudentComponents

  alias Tasky.Tasks
  alias Tasky.Uploads

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/student/tasks/#{@task}"}
    >
      <%!-- Compact Page Header --%>
      <div class="sticky top-0 z-20 bg-white border-b border-stone-200 h-[54px] flex items-center px-8">
        <div class="max-w-6xl mx-auto w-full flex items-center justify-between gap-4">
          <h1 class="text-[16px] font-semibold text-stone-900 truncate">
            {@task.name}
          </h1>

          <div
            :if={@has_files and (@editable or @preview_mode)}
            class="inline-flex items-center gap-0.5 bg-sky-100/70 rounded-lg p-0.5 shrink-0"
          >
            <.student_tab_button label="Aufgabe" tab="aufgabe" active={@student_tab == "aufgabe"} />
            <.student_tab_button label="Dateien" tab="dateien" active={@student_tab == "dateien"} />
          </div>

          <div class="flex items-center gap-3 shrink-0">
            <.back_link navigate={~p"/student/courses/#{@task.course_id}"} label="Zurück zum Kurs" />
            <button
              :if={@editable}
              id="complete-task-btn"
              type="button"
              phx-click="show_complete_modal"
              class="inline-flex items-center gap-2 bg-emerald-500 text-white text-sm font-semibold px-5 py-2 rounded-lg shadow-[0_2px_8px_rgba(16,185,129,0.25)] transition-all duration-150 hover:bg-emerald-600 active:scale-[0.98]"
            >
              <.icon name="hero-check" class="w-4 h-4" /> Als erledigt markieren
            </button>
          </div>
        </div>
      </div>

      <%!-- Preview Mode Banner --%>
      <div :if={@preview_mode} class="max-w-4xl mx-auto px-8 pt-6">
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div class="flex items-center gap-3">
            <.icon name="hero-eye" class="w-5 h-5 text-blue-600 flex-shrink-0" />
            <div class="flex-1">
              <p class="text-[14px] font-medium text-blue-900">Vorschaumodus</p>
              <p class="text-[13px] text-blue-700">
                Du siehst deine eingereichten Antworten zur Ansicht.
              </p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Review-denied feedback banner (unit was sent back for revision) --%>
      <div
        :if={@editable and @submission.status == "review_denied"}
        class="max-w-4xl mx-auto px-8 pt-6"
      >
        <div class="bg-rose-50 border border-rose-200 rounded-[14px] p-5">
          <div class="flex items-start gap-3">
            <div class="w-9 h-9 rounded-full bg-rose-100 flex items-center justify-center shrink-0">
              <.icon name="hero-arrow-uturn-left" class="w-5 h-5 text-rose-600" />
            </div>
            <div class="flex-1 min-w-0">
              <h3 class="text-[15px] font-semibold text-rose-900">
                Zur Überarbeitung zurückgegeben
              </h3>
              <p class="text-[13px] text-rose-700 mt-0.5">
                Deine Lehrperson hat die Aufgabe zurückgegeben. Überarbeite deine Antworten
                und markiere die Aufgabe erneut als erledigt.
              </p>
              <div
                :if={present?(@submission.feedback)}
                class="mt-3 bg-white rounded-lg p-4 border border-rose-100"
              >
                <p class="text-[13px] font-semibold text-stone-700 mb-1.5">
                  Feedback der Lehrperson:
                </p>
                <p class="text-[14px] text-stone-600 whitespace-pre-wrap leading-relaxed">
                  {@submission.feedback}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%= if @editable or @preview_mode do %>
        <%!-- Aufgabe tab: CSS-hidden (never unmounted) so the phx-update="ignore"
            editor keeps its DOM and state. --%>
        <div class={@student_tab != "aufgabe" && "hidden"}>
          <div
            id={"task-answers-editor-#{@submission.id}"}
            phx-hook="TaskAnswersEditor"
            phx-update="ignore"
            data-task-id={@task.id}
            data-content={@content_json}
            data-editable={to_string(@editable)}
          >
          </div>
        </div>

        <%!-- Dateien tab: also CSS-hidden so in-flight uploads survive switching. --%>
        <div
          :if={@has_files}
          class={[
            "bg-stone-100 min-h-[calc(100vh-54px)]",
            @student_tab != "dateien" && "hidden"
          ]}
        >
          <div class="max-w-4xl mx-auto px-8 py-8 space-y-6">
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
                  Dateien zur Aufgabe, die du herunterladen kannst.
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
                    href={~p"/uploads/tasks/#{@task.id}/attachments/#{attachment.stored_filename}"}
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
                        <progress class="progress progress-info w-32" value={entry.progress} max="100">
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
                      href={~p"/student/tasks/#{@task.id}/files/#{field.id}"}
                      target="_blank"
                      rel="noopener"
                      aria-label="Datei herunterladen"
                      class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-400 hover:bg-stone-100 hover:text-stone-600 transition-colors duration-150 shrink-0"
                    >
                      <.icon name="hero-arrow-down-tray" class="w-4 h-4" />
                    </a>
                    <button
                      :if={@editable}
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
                    :if={@editable}
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

                  <p
                    :if={!@editable and !uploaded_file}
                    class="mt-3 text-sm text-stone-400 italic"
                  >
                    Keine Datei hochgeladen.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <%!-- Status view (completed / approved) --%>
        <div class="max-w-4xl mx-auto px-8 py-8">
          <%= if @submission.status == "review_approved" do %>
            <%!-- Approved Feedback Card --%>
            <div class="bg-gradient-to-br from-emerald-50 to-white rounded-[14px] border border-emerald-200 p-8 shadow-sm">
              <div class="flex items-start gap-4">
                <div class="flex-shrink-0">
                  <div class="w-12 h-12 bg-emerald-100 rounded-full flex items-center justify-center">
                    <.icon name="hero-check-badge" class="w-6 h-6 text-emerald-600" />
                  </div>
                </div>

                <div class="flex-1">
                  <h3 class="text-lg font-semibold text-emerald-900 mb-1">Aufgabe genehmigt!</h3>
                  <p class="text-[14px] text-stone-500">
                    Deine Lehrperson hat deine Aufgabe angeschaut und genehmigt.
                  </p>

                  <div
                    :if={present?(@submission.feedback)}
                    class="mt-4 bg-white rounded-lg p-4 border border-emerald-100"
                  >
                    <p class="text-[13px] font-semibold text-stone-700 mb-2">
                      Feedback der Lehrperson:
                    </p>
                    <p class="text-[14px] text-stone-600 whitespace-pre-wrap leading-relaxed">
                      {@submission.feedback}
                    </p>
                  </div>

                  <div :if={@submission.graded_at} class="mt-3 text-[12px] text-stone-500">
                    Bewertet am {format_date(@submission.graded_at)}
                  </div>

                  <div class="mt-5 flex items-center gap-3">
                    <.link
                      navigate={~p"/student/tasks/#{@task.id}?preview=true"}
                      class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-[13px] font-semibold px-4 py-2.5 rounded-[10px] transition-all duration-150 hover:bg-stone-50 hover:border-stone-300"
                    >
                      <.icon name="hero-eye" class="w-4 h-4" /> Antworten ansehen
                    </.link>
                    <.link
                      navigate={~p"/student/courses/#{@task.course_id}"}
                      class="inline-flex items-center gap-2 px-5 py-2.5 text-[13px] font-semibold text-white bg-emerald-500 hover:bg-emerald-600 active:scale-[0.97] rounded-[10px] shadow-[0_2px_8px_rgba(16,185,129,0.25)] transition-all duration-150"
                    >
                      Weiter <.icon name="hero-arrow-right" class="w-3.5 h-3.5" />
                    </.link>
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <%!-- Completed – waiting for review --%>
            <div class="border border-stone-200 rounded-[18px] bg-white shadow-sm overflow-hidden">
              <div class="flex flex-col items-center text-center px-10 py-16 bg-white">
                <div class="text-[56px] leading-none mb-1.5 animate-bounce">
                  {@success_emoji}
                </div>

                <div class="w-6 h-[1.5px] bg-stone-200 rounded-sm my-5"></div>

                <h3 class="font-serif text-[34px] font-normal text-stone-900 leading-tight mb-2.5 animate-[fadeUp_0.4s_0.15s_ease_both]">
                  Aufgabe <em class="italic text-emerald-500">eingereicht.</em>
                </h3>

                <p class="text-[14px] text-stone-400 leading-relaxed max-w-[320px] mb-8 animate-[fadeUp_0.4s_0.2s_ease_both]">
                  Sehr gute Arbeit — deine Lehrperson schaut sich deine Antworten an
                  und gibt dir Feedback.
                </p>

                <div class="flex items-center gap-3 animate-[fadeUp_0.4s_0.25s_ease_both]">
                  <.link
                    navigate={~p"/student/tasks/#{@task.id}?preview=true"}
                    class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-[13px] font-semibold px-4 py-2.5 rounded-[10px] transition-all duration-150 hover:bg-stone-50 hover:border-stone-300"
                  >
                    <.icon name="hero-eye" class="w-4 h-4" /> Antworten ansehen
                  </.link>
                  <.link
                    navigate={~p"/student/courses/#{@task.course_id}"}
                    class="inline-flex items-center gap-2 px-5 py-2.5 text-[13px] font-semibold text-white bg-emerald-500 hover:bg-emerald-600 active:scale-[0.97] rounded-[10px] shadow-[0_2px_8px_rgba(16,185,129,0.25)] transition-all duration-150"
                  >
                    Weiter <.icon name="hero-arrow-right" class="w-3.5 h-3.5" />
                  </.link>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Complete Confirmation Modal --%>
      <%= if @show_complete_modal do %>
        <dialog
          id="complete-task-modal"
          class="modal modal-open"
          phx-window-keydown="close_complete_modal"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_complete_modal"></div>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-emerald-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-check-circle" class="w-5 h-5 text-emerald-500" />
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-stone-800">
                    Aufgabe als erledigt markieren
                  </h3>
                  <p class="text-xs text-stone-400 mt-0.5">Bitte bestätige den Vorgang.</p>
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
                    Möchtest du die Aufgabe
                    <span class="font-semibold text-stone-800">{@task.name}</span>
                    jetzt als erledigt markieren?
                  </p>
                  <div class="bg-amber-50 rounded-lg p-3 mt-4 border border-amber-100">
                    <div class="flex items-start gap-2.5">
                      <.icon
                        name="hero-exclamation-triangle"
                        class="w-4 h-4 text-amber-500 shrink-0 mt-0.5"
                      />
                      <p class="text-xs text-amber-700 leading-relaxed">
                        Sobald du die Aufgabe als erledigt markiert hast, kannst du deine
                        Antworten nicht mehr ändern, bis deine Lehrperson sie angeschaut hat.
                      </p>
                    </div>
                  </div>
                <% :error -> %>
                  <div id="submit-check-error" class="bg-red-50 rounded-lg p-3 border border-red-100">
                    <div class="flex items-start gap-2.5">
                      <.icon
                        name="hero-exclamation-circle"
                        class="w-4 h-4 text-red-500 shrink-0 mt-0.5"
                      />
                      <p class="text-xs text-red-700 leading-relaxed">
                        Deine letzten Änderungen konnten nicht gespeichert werden.
                        Prüfe deine Internetverbindung und versuche es erneut.
                        Du kannst die Aufgabe erst als erledigt markieren, wenn alle
                        Antworten gespeichert sind.
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
                      Lade die Dateien im Tab «Dateien» hoch, bevor du die Aufgabe
                      als erledigt markierst.
                    </p>
                  </div>
                </div>
              </div>
            </div>
            <div class="p-6 pt-0 flex items-center justify-end gap-3">
              <button
                id="cancel-complete-btn"
                type="button"
                phx-click="close_complete_modal"
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
                id="confirm-complete-btn"
                type="button"
                phx-click="confirm_complete_task"
                disabled={@submit_check != :ok or @missing_uploads != []}
                class="inline-flex items-center gap-2 bg-emerald-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(16,185,129,0.25)] transition-all duration-150 hover:bg-emerald-600 active:scale-[0.98] disabled:opacity-50 disabled:pointer-events-none"
              >
                <.icon name="hero-check" class="w-4 h-4" /> Jetzt als erledigt markieren
              </button>
            </div>
          </div>
        </dialog>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    scope = socket.assigns.current_scope

    task =
      case Integer.parse(id) do
        {task_id, ""} -> Tasks.get_task_for_student(scope, task_id)
        _ -> nil
      end

    case task do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Aufgabe nicht gefunden.")
         |> push_navigate(to: ~p"/student/courses")}

      task ->
        mount_task(task, params, socket)
    end
  end

  defp mount_task(task, params, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Tasky.PubSub,
        "student:#{socket.assigns.current_scope.user.id}:submissions"
      )
    end

    {:ok, submission} = Tasks.get_or_create_submission(socket.assigns.current_scope, task.id)

    submission = %{submission | task: task}

    if task.locked do
      {:ok,
       socket
       |> put_flash(:info, "Diese Aufgabe ist noch nicht verfügbar.")
       |> push_navigate(to: ~p"/student/courses/#{task.course_id}")}
    else
      # Auto-start the task if it's not started yet
      submission =
        if submission.status in ["not_started", "open", "draft"] do
          case Tasks.update_submission_status(
                 socket.assigns.current_scope,
                 submission.id,
                 "in_progress"
               ) do
            {:ok, updated_submission} ->
              %{updated_submission | task: task}

            {:error, _} ->
              submission
          end
        else
          submission
        end

      preview_mode = Map.get(params, "preview") == "true"

      attachments = Tasks.list_task_attachments(task)
      upload_fields = Tasks.list_task_upload_fields(task)

      socket =
        socket
        |> assign(:page_title, task.name)
        |> assign(:task, task)
        |> assign(:preview_mode, preview_mode)
        |> assign(:success_emoji, random_success_emoji())
        |> assign(:attachments, attachments)
        |> assign(:upload_fields, upload_fields)
        |> assign(:has_files, attachments != [] or upload_fields != [])
        |> assign(:student_tab, "aufgabe")
        |> assign(:show_complete_modal, false)
        |> assign(:submit_check, :checking)
        |> assign(:missing_uploads, [])
        |> assign_submission(submission)
        |> assign(:content_json, content_json(task, submission))

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
  end

  # Keeps submission-derived assigns (editable flag, uploaded files) in sync.
  defp assign_submission(socket, submission) do
    socket
    |> assign(:submission, submission)
    |> assign(:editable, Tasks.editable_submission?(submission))
    |> assign(:submission_files, submission_files_by_field(submission))
  end

  defp content_json(task, submission) do
    initial_content =
      case submission.content do
        content when is_map(content) and map_size(content) > 0 -> content
        _ -> task.content || %{}
      end

    Jason.encode!(initial_content)
  end

  defp submission_files_by_field(submission) do
    submission
    |> Tasks.list_submission_files()
    |> Map.new(&{&1.upload_field_id, &1})
  end

  defp field_upload_name(field_id), do: :"answer_field_#{field_id}"

  @impl true
  def handle_event("switch_student_tab", %{"tab" => tab}, socket)
      when tab in ["aufgabe", "dateien"] do
    {:noreply, assign(socket, :student_tab, tab)}
  end

  def handle_event("show_complete_modal", _params, socket) do
    # Opening the modal freezes the editor behind it, so once the client
    # reports a successful flush the server provably holds the full document
    # and completing needs no content payload.
    {:noreply,
     socket
     |> assign(:show_complete_modal, true)
     |> assign(:submit_check, :checking)
     |> assign(:missing_uploads, Tasks.missing_required_uploads(socket.assigns.submission))
     |> push_event("flush-before-submit", %{})}
  end

  def handle_event("submit_check_result", %{"ok" => ok}, socket) do
    {:noreply, assign(socket, :submit_check, if(ok == true, do: :ok, else: :error))}
  end

  def handle_event("retry_submit_check", _params, socket) do
    {:noreply,
     socket
     |> assign(:submit_check, :checking)
     |> assign(:missing_uploads, Tasks.missing_required_uploads(socket.assigns.submission))
     |> push_event("flush-before-submit", %{})}
  end

  def handle_event("close_complete_modal", _params, socket) do
    {:noreply, assign(socket, :show_complete_modal, false)}
  end

  def handle_event("confirm_complete_task", _params, socket) do
    complete_task(socket)
  end

  def handle_event("validate_answer_upload", _params, socket) do
    # auto_upload does the work; this handler just accepts the phx-change.
    {:noreply, socket}
  end

  def handle_event("cancel_answer_upload", %{"ref" => ref, "field-id" => field_id}, socket) do
    {:noreply, cancel_upload(socket, field_upload_name(field_id), ref)}
  end

  def handle_event("delete_answer_file", %{"field-id" => field_id}, socket) do
    submission = socket.assigns.submission

    with true <- socket.assigns.editable,
         file when not is_nil(file) <- Tasks.get_submission_file(submission, field_id),
         {:ok, _} <- Tasks.delete_submission_file(submission, file) do
      {:noreply, refresh_submission_files(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Datei konnte nicht gelöscht werden.")}
    end
  end

  defp complete_task(%{assigns: %{submit_check: check}} = socket) when check != :ok do
    # Defense against stale clicks: the button is disabled unless the flush
    # check passed, but the event could still arrive from a stale DOM.
    {:noreply, socket}
  end

  defp complete_task(socket) do
    case Tasks.complete_task(socket.assigns.current_scope, socket.assigns.submission.id) do
      {:ok, updated_submission} ->
        updated_submission = %{updated_submission | task: socket.assigns.task}

        {:noreply,
         socket
         |> assign_submission(updated_submission)
         |> assign(:show_complete_modal, false)}

      {:error, :missing_uploads} ->
        {:noreply,
         assign(
           socket,
           :missing_uploads,
           Tasks.missing_required_uploads(socket.assigns.submission)
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Aufgabe konnte nicht als erledigt markiert werden.")
         |> assign(:show_complete_modal, false)}
    end
  end

  @impl true
  def handle_info({:submission_updated, updated_submission}, socket) do
    if updated_submission.id == socket.assigns.submission.id do
      updated_submission = %{updated_submission | task: socket.assigns.task}

      {:noreply, assign_submission(socket, updated_submission)}
    else
      {:noreply, socket}
    end
  end

  # Consumes a finished answer upload: stores the bytes, upserts the
  # per-field file record (replacing an earlier upload) and refreshes the view.
  defp handle_answer_progress(name, entry, socket) do
    if entry.done? do
      %{task: task, submission: submission} = socket.assigns

      field_id =
        name |> Atom.to_string() |> String.replace_prefix("answer_field_", "")

      field = Enum.find(socket.assigns.upload_fields, &(to_string(&1.id) == field_id))

      if is_nil(field) or not socket.assigns.editable do
        {:noreply, cancel_upload(socket, name, entry.ref)}
      else
        result =
          consume_uploaded_entry(socket, entry, fn %{path: path} ->
            case Uploads.save_task_submission_file(
                   task.id,
                   submission.id,
                   path,
                   entry.client_name,
                   field.allowed_types
                 ) do
              {:ok, meta} ->
                {:ok,
                 Tasks.put_submission_file(
                   submission,
                   field,
                   Map.put(meta, :original_name, entry.client_name)
                 )}

              {:error, reason} ->
                {:ok, {:error, reason}}
            end
          end)

        case result do
          {:ok, _file} ->
            {:noreply, refresh_submission_files(socket)}

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Datei konnte nicht gespeichert werden (Typ oder Grösse nicht erlaubt)."
             )}
        end
      end
    else
      {:noreply, socket}
    end
  end

  defp refresh_submission_files(socket) do
    socket
    |> assign(:submission_files, submission_files_by_field(socket.assigns.submission))
    |> assign(:missing_uploads, Tasks.missing_required_uploads(socket.assigns.submission))
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%d.%m.%Y um %H:%M")
  end

  # Pick a random success emoji to celebrate task completion
  defp random_success_emoji do
    success_emojis = ["🎉", "🚀", "⭐", "🎊", "✨", "🏆", "🎯", "💫", "🌟", "👏"]
    Enum.random(success_emojis)
  end
end
