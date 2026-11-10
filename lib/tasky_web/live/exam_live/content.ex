defmodule TaskyWeb.ExamLive.Content do
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

          <%!-- TabAnchor keeps the teacher's place between Inhalt and Musterlösung --%>
          <div
            id="content-tabs"
            phx-hook="TabAnchor"
            class="inline-flex items-center gap-0.5 bg-sky-100/70 rounded-lg p-0.5"
          >
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
              :if={not @free_document}
              label="Vorschau"
              active={@tab == "vorschau"}
              patch={~p"/exams/#{@exam}/content?tab=vorschau"}
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

      <%!-- Vorschau tab: the learner's answer sheet, fields usable but never
          saved (no save_url). Lets the teacher see the plain-HTML view the
          learners get instead of the editor. --%>
      <div :if={@tab == "vorschau"} class="min-w-0">
        <div class="bg-stone-100 px-4 pt-6">
          <p class="max-w-[210mm] mx-auto flex items-center gap-2 text-[13px] text-stone-500">
            <.icon name="hero-eye" class="w-4 h-4 text-sky-500 shrink-0" />
            So sehen Lernende die Prüfung. Du kannst die Felder ausprobieren, gespeichert wird nichts.
          </p>
        </div>
        <.answer_sheet
          id={"exam-preview-#{@exam.id}-#{@preview_rev}"}
          doc={preview_doc(@exam)}
        />
      </div>

      <%!-- Musterlösung tab: one editor per question, shared with learning
           units (TaskyWeb.SampleSolutionComponents) --%>
      <div :if={@tab == "musterloesung"} class="bg-stone-100 min-h-[calc(100vh-54px)]">
        <.solution_toolbar
          :if={@part_views != [] and not @free_document}
          id={"solution-toolbar-#{@exam.id}"}
        />

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

          <%!-- What the exam is worth, and whether the learners see each
               question's share. Scrolls along: header and toolbar already
               stick, a third bar would squeeze the editors. --%>
          <.points_summary
            :if={@part_views != [] and not @free_document}
            exam={@exam}
            part_views={@part_views}
            form={@part_points_form}
          />

          <.part_row
            :for={pv <- @part_views}
            :if={not @free_document}
            id={"sample-solution-part-editor-#{@exam.id}-#{pv.id}"}
            part={pv}
            save_url={~p"/api/exams/#{@exam}/sample-solution/parts/#{pv.id}/content"}
          >
            <:card>
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

              <.options_summary part={pv} />
              <.audio_summary part={pv} content_path={~p"/exams/#{@exam}/content?tab=inhalt"} />
              <.pin_panel id={"pin-panel-#{@exam.id}-#{pv.id}"} part={pv} />
            </:card>
          </.part_row>
        </div>

        <.correction_options_dialog
          :if={@options_draft}
          kind={:exam}
          draft={@options_draft}
          form={@options_form}
        >
          <:points>
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
          </:points>
        </.correction_options_dialog>

        <.alternatives_help_dialog :if={@show_alternatives_help} kind={:exam} />
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

    if connected?(socket), do: Exams.subscribe_exam_content(exam.id)

    {:ok,
     socket
     |> assign(:exam, exam)
     |> assign(:preview_rev, 0)
     # Assigned here rather than in the "musterloesung" branch of
     # handle_params/3 so the flag is defined on every tab.
     |> assign(:show_alternatives_help, false)
     |> assign(:options_draft, nil)
     |> assign(:options_form, nil)
     |> assign(:free_document, ExamComponents.free_document?(exam))
     |> assign_part_points_form(exam)
     |> allow_upload(:attachment,
       accept: Uploads.attachment_accept_exts(),
       max_entries: 3,
       max_file_size: Uploads.max_file_bytes(),
       auto_upload: true,
       progress: &handle_attachment_progress/3
     )}
  end

  # The editor's last autosave lands after the switch to the preview (its
  # unmount flushes it), so the preview re-renders on every save. The answer
  # sheet is phx-update="ignore": only a new id makes it pick up new content.
  @impl true
  def handle_info(:exam_content_saved, %{assigns: %{tab: "vorschau"}} = socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, socket.assigns.exam.id)
    {:noreply, socket |> assign(:exam, exam) |> update(:preview_rev, &(&1 + 1))}
  end

  def handle_info(:exam_content_saved, socket), do: {:noreply, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    # Reload exam each time params change so structure edits made in the
    # Inhalt tab are reflected when the teacher switches to Musterlösung.
    exam = Exams.get_exam!(socket.assigns.current_scope, socket.assigns.exam.id)
    free_document? = ExamComponents.free_document?(exam)

    # A free-document exam has no answer fields: its learners write in the
    # editor itself, so there is nothing to preview.
    tab =
      case params["tab"] do
        "musterloesung" -> "musterloesung"
        "dateien" -> "dateien"
        "vorschau" when not free_document? -> "vorschau"
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

      "vorschau" ->
        {:noreply, socket}

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

      %{
        id: part.id,
        label: part.label,
        doc_json: Jason.encode!(%{"type" => "doc", "content" => nodes}),
        audios: audio_summaries(part.nodes)
      }
      |> Map.merge(block_flags(blocks))
      |> Map.merge(option_fields(exam, part.id, blocks))
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
  def handle_event(
        "set_show_part_points",
        %{"part_points" => %{"show_part_points" => raw}},
        socket
      ) do
    case Exams.set_show_part_points(socket.assigns.current_scope, socket.assigns.exam, raw) do
      {:ok, updated} ->
        {:noreply, socket |> assign(:exam, updated) |> assign_part_points_form(updated)}

      {:error, _} ->
        {:noreply,
         socket
         |> assign_part_points_form(socket.assigns.exam)
         |> put_flash(:error, "Einstellung konnte nicht gespeichert werden.")}
    end
  end

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
            # The question may have been removed while the dialog was open.
            socket =
              case part_view(socket, draft.part_id) do
                nil ->
                  socket

                pv ->
                  update_part_view(
                    socket,
                    draft.part_id,
                    option_fields(updated_exam, pv.id, pv.blocks)
                  )
              end

            {:noreply,
             socket
             |> assign(:exam, updated_exam)
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

    merge_option_flags(
      %{draft | custom_points: custom?, block_points: block_points, max_points: max_points},
      params
    )
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

  attr :exam, :map, required: true
  attr :part_views, :list, required: true
  attr :form, :map, required: true

  defp points_summary(assigns) do
    assigns = assign(assigns, :summary, summarize_points(assigns.exam, assigns.part_views))

    ~H"""
    <div
      id="solution-points-summary"
      class="mb-6 bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] px-5 py-3.5 flex flex-wrap items-center justify-between gap-x-8 gap-y-3"
    >
      <div class="flex flex-wrap items-baseline gap-x-2 gap-y-1 text-sm text-stone-500">
        <span class="text-stone-800 font-semibold">
          Total
          <span id="solution-points-total" class="font-mono tabular-nums">
            {format_block_points(@summary.total)}
          </span>
          {if @summary.total == 1, do: "Punkt", else: "Punkte"}
        </span>
        <span class="text-stone-300" aria-hidden="true">·</span>
        <span>
          {@summary.questions} {if @summary.questions == 1, do: "Aufgabe", else: "Aufgaben"}
        </span>
        <%= if @summary.missing > 0 do %>
          <span class="text-stone-300" aria-hidden="true">·</span>
          <span
            id="solution-points-missing"
            class="inline-flex items-center gap-1 self-center text-amber-700 font-medium"
          >
            <.icon name="hero-exclamation-triangle-mini" class="w-4 h-4" />
            {@summary.missing} ohne Punkte
          </span>
        <% end %>
        <%= if @summary.points_for_six do %>
          <span class="text-stone-300" aria-hidden="true">·</span>
          <span id="solution-points-six">
            Note 6 bei
            <span class="font-mono tabular-nums">
              {format_block_points(@summary.points_for_six)}
            </span>
            Punkten
          </span>
        <% end %>
      </div>

      <div class="flex items-center gap-1.5">
        <.form
          for={@form}
          id={"part-points-display-form-#{@exam.id}"}
          phx-change="set_show_part_points"
        >
          <.input
            field={@form[:show_part_points]}
            type="checkbox"
            label="Punkte pro Aufgabe den Lernenden zeigen"
          />
        </.form>
        <div
          class="tooltip tooltip-delayed tooltip-left"
          data-tip="Gilt auch für die Papierversion. Die Verteilung auf die Antwortfelder bleibt verborgen."
        >
          <.icon name="hero-information-circle" class="w-4 h-4 text-stone-400" />
        </div>
      </div>
    </div>
    """
  end

  # Total over the questions shown, how many still lack points, and the
  # points for a 6 when the teacher set them apart from the total.
  defp summarize_points(exam, part_views) do
    points = exam.sample_solution_points || %{}
    values = Enum.map(part_views, &Map.get(points, &1.id))
    total = values |> Enum.filter(&(is_number(&1) and &1 > 0)) |> Enum.sum()
    six = exam.grading_max_points

    %{
      total: total,
      questions: length(part_views),
      missing: Enum.count(values, &(not is_number(&1) or &1 <= 0)),
      points_for_six: if(is_number(six) and six > 0 and six != total, do: six)
    }
  end

  defp assign_part_points_form(socket, exam) do
    assign(
      socket,
      :part_points_form,
      to_form(%{"show_part_points" => exam.show_part_points}, as: :part_points)
    )
  end

  # The preview shows what the learners get, points per question included —
  # same as Guest.ExamLive.
  defp preview_doc(exam) do
    doc = exam.content || %{}

    case Exams.learner_visible_part_points(exam) do
      nil -> doc
      points -> Tasky.ExamDoc.put_part_points(doc, exam.answer_mode, points)
    end
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
  defp tab_label("vorschau", _free_document?), do: "Vorschau"
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
