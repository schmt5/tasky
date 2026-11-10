defmodule TaskyWeb.TaskLive.Content do
  @moduledoc """
  Authoring view for a learning unit (task): the Tiptap content editor
  (tab «Inhalt»), the model answers with their correction options per
  question (tab «Musterlösung», shared with exams via
  `TaskyWeb.SampleSolutionComponents`) plus teacher attachments and student upload fields
  (tab «Dateien»). Adapted from `TaskyWeb.ExamLive.Content`.
  """
  use TaskyWeb, :live_view

  import TaskyWeb.AnswerSheetComponents
  import TaskyWeb.FileComponents
  import TaskyWeb.SampleSolutionComponents

  import TaskyWeb.ContentComponents,
    only: [
      tab_link: 1,
      upload_field_form: 1,
      new_field_draft: 0,
      presence: 1,
      put_draft_error: 5
    ]

  alias Tasky.Correction.AnswerKey
  alias Tasky.Correction.PartConfig
  alias Tasky.ExamDoc
  alias Tasky.Tasks
  alias Tasky.Uploads

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/tasks/#{@task}/content"}
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
              navigate={~p"/courses/#{@task.course_id}"}
              tooltip={"Zurück zu #{@course.name}"}
              size="sm"
            />
            <.breadcrumbs crumbs={[
              %{label: "Kurse", navigate: ~p"/courses"},
              %{label: @course.name, navigate: ~p"/courses/#{@task.course_id}"},
              %{label: @task.name}
            ]} />
          </div>

          <div class="inline-flex items-center gap-0.5 bg-sky-100/70 rounded-lg p-0.5">
            <.tab_link
              label="Inhalt"
              active={@tab == "inhalt"}
              patch={~p"/tasks/#{@task}/content?tab=inhalt"}
            />
            <.tab_link
              label="Musterlösung"
              active={@tab == "musterloesung"}
              patch={~p"/tasks/#{@task}/content?tab=musterloesung"}
            />
            <.tab_link
              label="Vorschau"
              active={@tab == "vorschau"}
              patch={~p"/tasks/#{@task}/content?tab=vorschau"}
            />
            <.tab_link
              label="Dateien"
              active={@tab == "dateien"}
              patch={~p"/tasks/#{@task}/content?tab=dateien"}
            />
          </div>
        </div>
      </div>

      <%!-- Inhalt tab: full-width editor flush under the header --%>
      <div :if={@tab == "inhalt"} class="min-w-0">
        <div
          id={"task-content-editor-#{@task.id}"}
          phx-hook="TaskContentEditor"
          phx-update="ignore"
          data-task-id={@task.id}
          data-content={@content_json}
        >
        </div>
      </div>

      <%!-- Vorschau tab: the learner's answer sheet, fields usable but never
          saved (no save_url). Lets the teacher see the plain-HTML view the
          learners get instead of the editor. --%>
      <div :if={@tab == "vorschau"} class="min-w-0">
        <div class="bg-stone-100 px-4 pt-6">
          <p class="max-w-[210mm] mx-auto flex items-center gap-2 text-[13px] text-stone-500">
            <.icon name="hero-eye" class="w-4 h-4 text-sky-500 shrink-0" />
            So sehen Lernende die Lerneinheit. Du kannst die Felder ausprobieren, gespeichert wird nichts.
          </p>
        </div>
        <.answer_sheet
          id={"task-preview-#{@task.id}-#{@preview_rev}"}
          doc={@task.content || %{}}
        />
      </div>

      <%!-- Musterlösung tab: wie bei Prüfungen ein Editor pro Frage mit
           Korrekturoptionen daneben (TaskyWeb.SampleSolutionComponents) —
           nur ohne Punkte. --%>
      <div :if={@tab == "musterloesung"} class="bg-stone-100 min-h-[calc(100vh-54px)]">
        <.solution_toolbar :if={@part_views != []} id={"solution-toolbar-#{@task.id}"} />

        <div class="max-w-7xl mx-auto px-8 py-6">
          <div
            :if={@loose_answer_count > 0}
            id="loose-answers-note"
            role="status"
            class="mb-6 flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50/70 px-4 py-3.5"
          >
            <.icon
              name="hero-exclamation-triangle"
              class="w-[18px] h-[18px] text-amber-500 shrink-0 mt-0.5"
            />
            <div class="min-w-0 text-sm text-stone-700 leading-relaxed">
              <p class="font-semibold text-stone-800">
                {loose_answers_label(@loose_answer_count)} vor der ersten Frage
              </p>
              <p class="text-xs text-stone-600 mt-0.5">
                Musterlösung und Selbstkontrolle gibt es nur für Antwortfelder unter einer Frage.
                Setze im Inhalt eine Fragen-Überschrift davor.
              </p>
              <.link
                patch={~p"/tasks/#{@task}/content?tab=inhalt"}
                class="inline-block mt-1.5 text-xs font-medium text-sky-700 hover:text-sky-800 hover:underline underline-offset-2 transition-colors duration-150"
              >
                Zum Inhalt
              </.link>
            </div>
          </div>

          <div
            :if={@part_views == [] and @loose_answer_count == 0}
            class="flex flex-col items-center justify-center text-center py-24"
          >
            <div class="flex items-center justify-center w-14 h-14 rounded-2xl bg-stone-100 text-stone-400 mb-4">
              <.icon name="hero-document-text" class="w-7 h-7" />
            </div>
            <h3 class="text-base font-semibold text-stone-700">Noch keine Frage vorhanden</h3>
            <p class="text-sm text-stone-500 mt-1.5 max-w-md leading-relaxed">
              Lege zuerst im Tab <span class="font-medium text-stone-600">„Inhalt“</span>
              eine Frage (Überschrift) mit Antwortfeldern an, um hier die Musterlösung zu erfassen.
            </p>
          </div>

          <.part_row
            :for={pv <- @part_views}
            id={"sample-solution-part-editor-#{@task.id}-#{pv.id}"}
            part={pv}
            save_url={~p"/api/tasks/#{@task}/sample-solution/parts/#{pv.id}/content"}
          >
            <:card>
              <.options_summary part={pv} class="p-5" />
              <.audio_summary part={pv} content_path={~p"/tasks/#{@task}/content?tab=inhalt"} />
              <.pin_panel id={"pin-panel-#{@task.id}-#{pv.id}"} part={pv} />
            </:card>
          </.part_row>
        </div>

        <.correction_options_dialog
          :if={@options_draft}
          kind={:task}
          draft={@options_draft}
          form={@options_form}
        />

        <.alternatives_help_dialog :if={@show_alternatives_help} kind={:task} />
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
                  Dateien, welche die Lernenden in dieser Lerneinheit herunterladen können.
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
              <p :for={err <- upload_errors(@uploads.attachment)} class="text-xs text-red-600">
                {upload_error_message(err)}
              </p>

              <div
                :if={@attachments == [] and @uploads.attachment.entries == []}
                class="rounded-xl border border-dashed border-stone-200 px-4 py-8 text-center"
              >
                <p class="text-sm text-stone-400">
                  Noch keine Anhänge. Lade z.&nbsp;B. ein Arbeitsblatt (PDF) oder eine Audio-Datei hoch.
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
                  href={~p"/uploads/tasks/#{@task.id}/attachments/#{attachment.stored_filename}"}
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
                  Felder, in die Lernende ihre Antwort als Datei hochladen. Eine Datei pro Feld.
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
                  Noch keine Upload-Felder. Füge ein Feld hinzu, damit Lernende Dateien abgeben können.
                </p>
              </div>

              <div :for={field <- @upload_fields} class="rounded-xl border border-stone-200 px-5 py-4">
                <%= if @editing_field_id == field.id do %>
                  <.upload_field_form
                    draft={@field_draft}
                    label_placeholder="z. B. Aufsatz, bearbeitetes Arbeitsblatt, …"
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
                        data-confirm={"Upload-Feld «#{field.label}» wirklich löschen? Bereits hochgeladene Abgaben der Lernenden werden ebenfalls gelöscht."}
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
                  label_placeholder="z. B. Aufsatz, bearbeitetes Arbeitsblatt, …"
                />
              </div>
            </div>
          </div>

          <%!-- Lösungsdateien: z. B. das korrekt formatierte Word-Dokument --%>
          <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
            <div class="p-6 flex items-start justify-between gap-4">
              <div class="min-w-0">
                <div class="flex items-center gap-2.5">
                  <.icon name="hero-document-check" class="w-5 h-5 text-sky-500" />
                  <h2 class="text-lg font-semibold text-stone-800">Lösungsdateien</h2>
                </div>
                <p class="text-sm text-stone-500 mt-1">
                  Dateien, welche die Lernenden zusammen mit der Musterlösung herunterladen
                  können – etwa das korrekt formatierte Word-Dokument.
                </p>
              </div>
              <form
                id="solution-file-upload-form"
                phx-change="validate_solution_file"
                class="shrink-0"
              >
                <label class="inline-flex items-center gap-2 border border-stone-200 text-stone-700 text-sm font-semibold px-4 py-2.5 rounded-xl cursor-pointer transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 active:scale-[0.98]">
                  <.icon name="hero-arrow-up-tray" class="w-4 h-4" /> Datei hochladen
                  <.live_file_input upload={@uploads.solution_file} class="hidden" />
                </label>
              </form>
            </div>

            <div class="px-6 pb-6 space-y-2.5">
              <div
                :for={entry <- @uploads.solution_file.entries}
                class="rounded-xl border border-stone-200 px-4 py-3"
              >
                <div class="flex items-center gap-3">
                  <p class="flex-1 min-w-0 text-sm font-medium text-stone-700 truncate">
                    {entry.client_name}
                  </p>
                  <%= if upload_errors(@uploads.solution_file, entry) == [] do %>
                    <progress class="progress progress-info w-32" value={entry.progress} max="100">
                    </progress>
                  <% end %>
                  <button
                    type="button"
                    phx-click="cancel_solution_file_upload"
                    phx-value-ref={entry.ref}
                    aria-label="Upload abbrechen"
                    class="inline-flex items-center justify-center w-7 h-7 rounded-full text-stone-400 hover:bg-stone-100 hover:text-stone-600 transition-colors duration-150 shrink-0"
                  >
                    <.icon name="hero-x-mark" class="w-4 h-4" />
                  </button>
                </div>
                <p
                  :for={err <- upload_errors(@uploads.solution_file, entry)}
                  class="text-xs text-red-600 mt-1.5"
                >
                  {upload_error_message(err)}
                </p>
              </div>
              <p :for={err <- upload_errors(@uploads.solution_file)} class="text-xs text-red-600">
                {upload_error_message(err)}
              </p>

              <div
                :if={@solution_files == [] and @uploads.solution_file.entries == []}
                class="rounded-xl border border-dashed border-stone-200 px-4 py-8 text-center"
              >
                <p class="text-sm text-stone-400">
                  Noch keine Lösungsdateien.
                </p>
              </div>

              <div
                :for={file <- @solution_files}
                class="flex items-center gap-4 rounded-xl border border-stone-200 px-4 py-3"
              >
                <.file_badge filename={file.stored_filename} />
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-semibold text-stone-800 truncate">
                    {file.original_name}
                  </p>
                  <p class="text-xs text-stone-400 mt-0.5">
                    {file_type_label(file.stored_filename)} · {Uploads.format_size(file.size)}
                  </p>
                </div>
                <a
                  href={~p"/tasks/#{@task.id}/solution-files/#{file.id}"}
                  class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-sm font-semibold px-3.5 py-2 rounded-lg transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 shrink-0"
                >
                  <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Herunterladen
                </a>
                <button
                  type="button"
                  phx-click="delete_solution_file"
                  phx-value-id={file.id}
                  data-confirm={"«#{file.original_name}» wirklich löschen?"}
                  aria-label="Lösungsdatei löschen"
                  class="inline-flex items-center justify-center w-9 h-9 rounded-lg text-stone-400 hover:bg-red-50 hover:text-red-600 transition-colors duration-150 shrink-0"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
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
    task = Tasks.get_task_with_course!(socket.assigns.current_scope, id)

    if connected?(socket), do: Tasks.subscribe_tasks(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:task, task)
     |> assign(:preview_rev, 0)
     |> assign(:course, task.course)
     # Assigned here rather than in the "musterloesung" branch of
     # handle_params/3 so they are defined on every tab.
     |> assign(:show_alternatives_help, false)
     |> assign(:options_draft, nil)
     |> assign(:options_form, nil)
     |> allow_upload(:attachment,
       accept: Uploads.attachment_accept_exts(),
       max_entries: 3,
       max_file_size: Uploads.max_file_bytes(),
       auto_upload: true,
       progress: &handle_attachment_progress/3
     )
     |> allow_upload(:solution_file,
       accept: Uploads.attachment_accept_exts(),
       max_entries: 3,
       max_file_size: Uploads.max_file_bytes(),
       auto_upload: true,
       progress: &handle_solution_file_progress/3
     )}
  end

  # The editor's last autosave lands after the switch to the preview (its
  # unmount flushes it), so the preview re-renders on every save of this unit.
  # The answer sheet is phx-update="ignore": only a new id makes it pick up new
  # content. Every other message on the teacher's task topic is not ours.
  @impl true
  def handle_info({:updated, %{id: id}}, %{assigns: %{tab: "vorschau", task: %{id: id}}} = socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)
    {:noreply, socket |> assign(:task, task) |> update(:preview_rev, &(&1 + 1))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, socket.assigns.task.id)

    tab =
      case params["tab"] do
        "dateien" -> "dateien"
        "musterloesung" -> "musterloesung"
        "vorschau" -> "vorschau"
        _ -> "inhalt"
      end

    socket =
      socket
      |> assign(:task, task)
      |> assign(:tab, tab)
      |> assign(:page_title, "#{task.name} – #{tab_label(tab)}")

    case tab do
      "inhalt" ->
        {:noreply, assign(socket, :content_json, Jason.encode!(task.content || %{}))}

      "vorschau" ->
        {:noreply, socket}

      "musterloesung" ->
        {:noreply,
         socket
         |> assign(:part_views, build_part_views(task))
         |> assign(:loose_answer_count, loose_answer_count(task))}

      "dateien" ->
        {:noreply,
         socket
         |> assign(:attachments, Tasks.list_task_attachments(task))
         |> assign(:upload_fields, Tasks.list_task_upload_fields(task))
         |> assign(:solution_files, Tasks.list_task_solution_files(task))
         |> assign(:editing_field_id, nil)
         |> assign(:field_draft, nil)}
    end
  end

  ## Musterlösung tab: ein Editor und Korrekturoptionen pro Frage

  # One view-model entry per question, rendered as a stacked editor + card.
  # `doc_json` is only computed here (full navigation) — event handlers must
  # never touch it, so the phx-update="ignore" editor hooks stay untouched.
  defp build_part_views(task) do
    parts = ExamDoc.split_content_into_parts(task.content || %{}, "answer_fields")

    sample_parts =
      task
      |> Tasks.sample_solution_doc()
      |> ExamDoc.split_content_into_parts("answer_fields")
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
        |> Enum.map(&Map.take(&1, [:answer_id, :type]))

      %{
        id: part.id,
        label: part.label,
        doc_json: Jason.encode!(%{"type" => "doc", "content" => nodes}),
        blocks: blocks,
        audios: audio_summaries(part.nodes)
      }
      |> Map.merge(block_flags(blocks))
      |> Map.merge(option_fields(task, part.id, blocks))
    end)
  end

  # The question view's correction options, as stored on the unit. Shared by
  # the full build and the refresh after «Übernehmen», which must not touch
  # `doc_json`.
  defp option_fields(task, part_id, blocks) do
    config = Tasks.part_config(task, part_id)
    choice_only? = PartConfig.choice_only_blocks?(blocks)

    %{
      # A question of only ticks is always checked (`Tasky.Tasks.SelfCheck`).
      choice_only: choice_only?,
      auto_correct: choice_only? or PartConfig.flag?(config, "auto_correct"),
      ignore_case: PartConfig.flag?(config, "ignore_case"),
      ignore_spelling: PartConfig.flag?(config, "ignore_spelling"),
      ignore_punctuation: PartConfig.flag?(config, "ignore_punctuation"),
      checkbox_rule: PartConfig.checkbox_rule(config)
    }
  end

  # Answer fields before the first question: neither edited nor checked here.
  defp loose_answer_count(task) do
    preamble = ExamDoc.content_preamble(task.content || %{}, "answer_fields")
    %{"content" => preamble} |> AnswerKey.block_ids() |> MapSet.size()
  end

  defp loose_answers_label(1), do: "1 Antwortfeld steht"
  defp loose_answers_label(n), do: "#{n} Antwortfelder stehen"

  defp part_view(socket, part_id),
    do: Enum.find(socket.assigns.part_views, &(&1.id == part_id))

  # Updates the options of one question view. Deliberately never touches
  # `doc_json` — see build_part_views/1. The question may have been removed
  # while the dialog was open.
  defp refresh_part_options(socket, task, part_id) do
    part_views =
      Enum.map(socket.assigns.part_views, fn pv ->
        if pv.id == part_id, do: Map.merge(pv, option_fields(task, pv.id, pv.blocks)), else: pv
      end)

    assign(socket, :part_views, part_views)
  end

  defp assign_options_draft(socket, nil),
    do: socket |> assign(:options_draft, nil) |> assign(:options_form, nil)

  defp assign_options_draft(socket, draft) do
    params = %{
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

  @impl true
  def handle_event("open_correction_options", %{"part-id" => part_id}, socket) do
    case part_view(socket, part_id) do
      nil ->
        {:noreply, socket}

      pv ->
        draft =
          pv
          |> Map.take([
            :label,
            :blocks,
            :has_text_answers,
            :has_checkboxes,
            :choice_only,
            :auto_correct,
            :ignore_case,
            :ignore_spelling,
            :ignore_punctuation,
            :checkbox_rule
          ])
          |> Map.put(:part_id, pv.id)

        {:noreply, assign_options_draft(socket, draft)}
    end
  end

  def handle_event("close_correction_options", _params, socket) do
    {:noreply, assign_options_draft(socket, nil)}
  end

  def handle_event("change_correction_options", %{"options" => params}, socket) do
    case socket.assigns.options_draft do
      nil -> {:noreply, socket}
      draft -> {:noreply, assign_options_draft(socket, merge_option_flags(draft, params))}
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
        draft = merge_option_flags(draft, params)

        case Tasks.apply_part_options(
               socket.assigns.current_scope,
               socket.assigns.task,
               draft.part_id,
               options_config(draft)
             ) do
          {:ok, task} ->
            {:noreply,
             socket
             |> assign(:task, task)
             |> refresh_part_options(task, draft.part_id)
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

  ## Dateien tab: Lösungsdateien

  def handle_event("validate_solution_file", _params, socket) do
    # auto_upload does the work; this handler just accepts the phx-change.
    {:noreply, socket}
  end

  def handle_event("cancel_solution_file_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :solution_file, ref)}
  end

  def handle_event("delete_solution_file", %{"id" => id}, socket) do
    with file when not is_nil(file) <-
           Tasks.get_task_solution_file(socket.assigns.task, id),
         {:ok, _deleted} <-
           Tasks.delete_task_solution_file(socket.assigns.current_scope, file) do
      {:noreply,
       assign(
         socket,
         :solution_files,
         Tasks.list_task_solution_files(socket.assigns.task)
       )}
    else
      _ -> {:noreply, put_flash(socket, :error, "Lösungsdatei konnte nicht gelöscht werden.")}
    end
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
           Tasks.get_task_attachment(socket.assigns.task, id),
         {:ok, _} <- Tasks.delete_task_attachment(socket.assigns.current_scope, attachment) do
      {:noreply, assign(socket, :attachments, Tasks.list_task_attachments(socket.assigns.task))}
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
    case Tasks.get_task_upload_field(socket.assigns.task, id) do
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
          Tasks.create_task_upload_field(
            socket.assigns.current_scope,
            socket.assigns.task,
            attrs
          )

        id ->
          case Tasks.get_task_upload_field(socket.assigns.task, id) do
            nil -> {:error, :not_found}
            field -> Tasks.update_task_upload_field(socket.assigns.current_scope, field, attrs)
          end
      end

    case result do
      {:ok, _field} ->
        {:noreply,
         socket
         |> assign(:upload_fields, Tasks.list_task_upload_fields(socket.assigns.task))
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
    with field when not is_nil(field) <-
           Tasks.get_task_upload_field(socket.assigns.task, id),
         {:ok, _} <- Tasks.delete_task_upload_field(socket.assigns.current_scope, field) do
      {:noreply,
       assign(socket, :upload_fields, Tasks.list_task_upload_fields(socket.assigns.task))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Upload-Feld konnte nicht gelöscht werden.")}
    end
  end

  defp handle_solution_file_progress(:solution_file, entry, socket) do
    if entry.done? do
      task = socket.assigns.task

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          case Uploads.save_task_solution_file(task.id, path, entry.client_name) do
            {:ok, meta} ->
              {:ok,
               Tasks.create_task_solution_file(
                 socket.assigns.current_scope,
                 task,
                 Map.put(meta, :original_name, entry.client_name)
               )}

            {:error, reason} ->
              {:ok, {:error, reason}}
          end
        end)

      case result do
        {:ok, _file} ->
          {:noreply, assign(socket, :solution_files, Tasks.list_task_solution_files(task))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, file_save_error_message(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  defp handle_attachment_progress(:attachment, entry, socket) do
    if entry.done? do
      task = socket.assigns.task

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          case Uploads.save_task_attachment(task.id, path, entry.client_name) do
            {:ok, meta} ->
              {:ok,
               Tasks.create_task_attachment(
                 socket.assigns.current_scope,
                 task,
                 Map.put(meta, :original_name, entry.client_name)
               )}

            {:error, reason} ->
              {:ok, {:error, reason}}
          end
        end)

      case result do
        {:ok, _attachment} ->
          {:noreply, assign(socket, :attachments, Tasks.list_task_attachments(task))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, file_save_error_message(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  defp tab_label("inhalt"), do: "Inhalt"
  defp tab_label("vorschau"), do: "Vorschau"
  defp tab_label("musterloesung"), do: "Musterlösung"
  defp tab_label("dateien"), do: "Dateien"
end
