defmodule TaskyWeb.TaskLive.Content do
  @moduledoc """
  Authoring view for a learning unit (task): the Tiptap content editor
  (tab «Inhalt»), the model answers and their release mode
  (tab «Musterlösung») plus teacher attachments and student upload fields
  (tab «Dateien»). Adapted from `TaskyWeb.ExamLive.Content`.
  """
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

      <%!-- Musterlösung tab: dieselbe Struktur wie «Inhalt», aber gesperrter
           Aufgabentext — die Lehrperson füllt nur die Antwortfelder. Rechts
           daneben die Selbstkontrolle pro Antwortfeld. --%>
      <div :if={@tab == "musterloesung"} class="min-w-0">
        <div :if={@answer_block_count > 0} class="flex items-stretch min-h-[calc(100vh-54px)]">
          <div class="min-w-0 flex-1 bg-stone-100">
            <div
              id={"task-sample-solution-editor-#{@task.id}"}
              phx-hook="TaskSampleSolutionEditor"
              phx-update="ignore"
              data-task-id={@task.id}
              data-content={@solution_json}
            >
            </div>
          </div>

          <aside class="w-[300px] shrink-0 border-l border-stone-200 bg-white">
            <div class="p-5 border-b border-stone-100">
              <h3 class="text-sm font-semibold text-stone-800">Selbstkontrolle</h3>
              <p class="text-xs text-stone-500 mt-1 leading-relaxed">
                Geprüfte Felder vergleicht Tasky nach der Freigabe automatisch mit der
                Musterlösung. Gross-/Kleinschreibung wird ignoriert, mehrere gültige
                Antworten trennst du mit <code class="font-mono">;</code> — Lernenden werden
                sie als „pdf oder .pdf" gezeigt.
              </p>
            </div>

            <div class="p-5 space-y-2">
              <label
                :for={block <- @solution_blocks}
                class="flex items-start gap-3 cursor-pointer rounded-lg border border-stone-200 bg-stone-50/60 px-2.5 py-2 hover:bg-stone-50"
              >
                <input
                  type="checkbox"
                  checked={block.checked}
                  phx-click="toggle_self_check"
                  phx-value-answer-id={block.answer_id}
                  aria-label="Automatisch prüfen"
                  class="mt-0.5 w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150 shrink-0"
                />
                <span class="min-w-0">
                  <span class="block text-xs font-semibold text-stone-700">
                    {block.type_label}
                  </span>
                  <span class="block text-xs text-stone-500 mt-0.5 truncate">
                    {block.snippet}
                  </span>
                </span>
              </label>

              <p class="text-xs text-stone-400 leading-relaxed pt-1">
                Nimm offen formulierte Fragen heraus — dort sieht die/der Lernende nur die
                Musterlösung und vergleicht selbst.
              </p>
            </div>
          </aside>
        </div>

        <div :if={@answer_block_count == 0} class="bg-stone-100 min-h-[calc(100vh-54px)]">
          <div class="max-w-4xl mx-auto px-8 py-16 text-center">
            <.icon name="hero-key" class="w-10 h-10 text-stone-300" />
            <h3 class="mt-3 text-base font-semibold text-stone-700">Noch keine Antwortfelder</h3>
            <p class="mt-1 text-sm text-stone-500">
              Lege zuerst im Tab «Inhalt» ein Antwortfeld an – die Musterlösung wird direkt in
              diesen Feldern erfasst.
            </p>
            <.link
              patch={~p"/tasks/#{@task}/content?tab=inhalt"}
              class="mt-5 inline-flex items-center gap-2 border border-stone-200 text-stone-700 text-sm font-semibold px-4 py-2.5 rounded-xl transition-all duration-150 hover:bg-white hover:border-stone-300"
            >
              <.icon name="hero-pencil-square" class="w-4 h-4" /> Zum Inhalt
            </.link>
          </div>
        </div>
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

    {:ok,
     socket
     |> assign(:task, task)
     |> assign(:course, task.course)
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

  @impl true
  def handle_params(params, _uri, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, socket.assigns.task.id)

    tab =
      case params["tab"] do
        "dateien" -> "dateien"
        "musterloesung" -> "musterloesung"
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

      "musterloesung" ->
        {:noreply,
         socket
         |> assign(:solution_json, Jason.encode!(Tasks.sample_solution_doc(task)))
         |> assign(:answer_block_count, Tasks.answer_block_count(task))
         |> assign_solution_blocks(task)}

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

  ## Musterlösung tab: Selbstkontrolle pro Antwortfeld

  defp assign_solution_blocks(socket, task) do
    blocks =
      task
      |> Tasks.list_solution_blocks()
      |> Enum.map(&Map.put(&1, :type_label, block_type_label(&1.type)))

    assign(socket, :solution_blocks, blocks)
  end

  defp block_type_label("answerBlock"), do: "Antwortfeld"
  defp block_type_label("lueckentext"), do: "Lücke"
  defp block_type_label("taskItem"), do: "Checkbox"
  defp block_type_label(_type), do: "Antwortfeld"

  ## Dateien tab: Lösungsdateien

  @impl true
  def handle_event("toggle_self_check", %{"answer-id" => answer_id}, socket) do
    case Tasks.toggle_self_check(socket.assigns.current_scope, socket.assigns.task, answer_id) do
      {:ok, task} ->
        {:noreply, socket |> assign(:task, task) |> assign_solution_blocks(task)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Konnte nicht gespeichert werden.")}
    end
  end

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
  defp tab_label("musterloesung"), do: "Musterlösung"
  defp tab_label("dateien"), do: "Dateien"
end
