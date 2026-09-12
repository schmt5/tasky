defmodule TaskyWeb.TaskLive.Files do
  @moduledoc """
  Teacher view of every file submission for one learning unit: a row per
  student, a column per upload field. Each cell shows what kind of file was
  handed in (the colored type badge), offers a download, and for images an
  "open" action that shows the file in a modal.

  The per-student review modal in `TaskyWeb.TaskLive.Progress` shows the same
  files one student at a time; this page is the across-students view of them.
  """
  use TaskyWeb, :live_view

  import TaskyWeb.FileComponents
  import TaskyWeb.UI, only: [empty_state: 1]

  alias Tasky.Courses
  alias Tasky.Tasks
  alias Tasky.Uploads

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/progress/#{@task.id}"}
    >
      <%!-- Page Header --%>
      <div class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-7xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Kurse", navigate: ~p"/courses"},
              %{label: @task.course.name, navigate: ~p"/courses/#{@task.course_id}"},
              %{label: @task.name, navigate: ~p"/progress/#{@task.id}"},
              %{label: "Datei-Abgaben"}
            ]} />
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button navigate={~p"/progress/#{@task.id}"} tooltip="Zurück zum Fortschritt" />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              Datei-Abgaben
            </h1>
          </div>

          <p class="text-[15px] text-stone-500 leading-[1.7]">
            Alle hochgeladenen Dateien der Lernenden für «{@task.name}»
          </p>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-8 pb-8">
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <%= cond do %>
            <% @upload_fields == [] -> %>
              <.empty_state
                icon_name="hero-paper-clip"
                title="Keine Datei-Abgaben eingerichtet"
                description="Diese Lerneinheit hat keine Upload-Felder. Richten Sie eines ein, damit Lernende Dateien abgeben können."
              >
                <:action>
                  <.link
                    navigate={~p"/tasks/#{@task.id}/content?tab=dateien"}
                    class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-[13px] font-semibold px-4 py-2 rounded-[10px] transition-all duration-150 hover:bg-stone-50 hover:border-stone-300"
                  >
                    <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Upload-Felder einrichten
                  </.link>
                </:action>
              </.empty_state>
            <% @students == [] -> %>
              <.empty_state
                icon_name="hero-users"
                title="Keine Lernenden eingeschrieben"
                description="Schreiben Sie Lernende in den Kurs ein, damit hier Abgaben erscheinen."
              />
            <% true -> %>
              <div class="overflow-x-auto">
                <div class="inline-block min-w-full align-middle">
                  <table class="min-w-full divide-y divide-stone-200">
                    <thead class="bg-stone-50">
                      <tr>
                        <th
                          scope="col"
                          class="sticky left-0 z-10 bg-stone-50 px-6 py-4 text-left text-xs font-semibold text-stone-700 uppercase tracking-wider border-r border-stone-200"
                        >
                          Lernende
                        </th>
                        <th
                          :for={field <- @upload_fields}
                          scope="col"
                          class="px-4 py-4 text-left text-xs font-semibold text-stone-700 uppercase tracking-wider min-w-[320px]"
                        >
                          <div class="flex items-center gap-2">
                            <span>{field.label}</span>
                            <span
                              :if={field.required}
                              class="text-[10px] font-semibold text-amber-600 normal-case"
                            >
                              Pflicht
                            </span>
                          </div>
                          <p class="mt-1 text-[11px] font-normal normal-case tracking-normal text-stone-400">
                            {allowed_types_label(field)}
                          </p>
                        </th>
                      </tr>
                    </thead>

                    <tbody class="bg-white divide-y divide-stone-100">
                      <tr
                        :for={student <- @students}
                        class="hover:bg-stone-50/60 transition-colors duration-150"
                      >
                        <td class="sticky left-0 z-10 bg-white px-6 py-4 whitespace-nowrap border-r border-stone-200">
                          <div class="flex items-center gap-3">
                            <.participant_avatar person={student} />
                            <div class="min-w-0">
                              <p class="text-sm font-semibold text-stone-800 truncate">
                                {student_full_name(student)}
                              </p>
                              <p class="text-xs text-stone-400 truncate">{student.email}</p>
                            </div>
                          </div>
                        </td>

                        <td :for={field <- @upload_fields} class="px-4 py-4 align-middle">
                          <.file_cell
                            entry={Map.get(@files, {student.id, field.id})}
                            field={field}
                            task_id={@task.id}
                          />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
          <% end %>
        </div>
      </div>

      <%!-- Bild-Vorschau --%>
      <%= if @preview do %>
        <dialog
          id="file-preview-modal"
          class="modal modal-open"
          phx-window-keydown="close_preview"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/70" phx-click="close_preview"></div>
          <div class="modal-box max-w-[90vw] max-h-[92vh] p-0 bg-white rounded-[16px] shadow-2xl flex flex-col">
            <div class="flex items-center gap-4 px-6 py-4 border-b border-stone-100">
              <.file_badge filename={@preview.file.stored_filename} />
              <div class="flex-1 min-w-0">
                <p class="text-base font-semibold text-stone-800 truncate">
                  {@preview.file.original_name}
                </p>
                <p class="text-xs text-stone-400 mt-0.5">
                  {@preview.student_name} · {@preview.field_label} · {Uploads.format_size(
                    @preview.file.size
                  )}
                </p>
              </div>
              <a
                href={download_path(@task.id, @preview)}
                target="_blank"
                rel="noopener"
                class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-[13px] font-semibold px-3.5 py-2 rounded-[10px] transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 shrink-0"
              >
                <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Herunterladen
              </a>
              <button
                type="button"
                phx-click="close_preview"
                aria-label="Schliessen"
                class="p-2 rounded-lg text-stone-400 hover:bg-stone-100 hover:text-stone-600 transition-colors shrink-0"
              >
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <div class="flex-1 overflow-auto bg-stone-50 p-6 flex items-center justify-center">
              <img
                src={inline_path(@task.id, @preview)}
                alt={@preview.file.original_name}
                class="max-w-full max-h-[75vh] object-contain rounded-lg shadow-sm"
              />
            </div>
          </div>
        </dialog>
      <% end %>
    </Layouts.app>
    """
  end

  ## Components

  attr :entry, :map, default: nil
  attr :field, :map, required: true
  attr :task_id, :integer, required: true

  defp file_cell(%{entry: nil} = assigns) do
    ~H"""
    <span class={[
      "text-[13px] italic",
      if(@field.required, do: "text-amber-600", else: "text-stone-400")
    ]}>
      Nicht hochgeladen
    </span>
    """
  end

  defp file_cell(assigns) do
    assigns = assign(assigns, :type_key, type_key(assigns.entry.file))

    ~H"""
    <div class="flex items-center gap-3">
      <.file_badge filename={@entry.file.stored_filename} />

      <div class="flex-1 min-w-0">
        <p class="text-sm font-semibold text-stone-800 truncate">{@entry.file.original_name}</p>
        <p class="text-xs text-stone-400 mt-0.5">
          {file_type_label(@entry.file.stored_filename)} · {Uploads.format_size(@entry.file.size)}
        </p>
      </div>

      <div class="flex items-center gap-1 shrink-0">
        <div
          :if={@type_key == "image"}
          class="tooltip tooltip-delayed tooltip-top"
          data-tip="Bild öffnen"
        >
          <button
            type="button"
            phx-click="preview_file"
            phx-value-file-id={@entry.file.id}
            aria-label={"Bild «#{@entry.file.original_name}» öffnen"}
            class="p-2 rounded-lg text-stone-400 hover:bg-sky-50 hover:text-sky-600 transition-colors"
          >
            <.icon name="hero-eye" class="w-4 h-4" />
          </button>
        </div>

        <div
          :if={@type_key == "pdf"}
          class="tooltip tooltip-delayed tooltip-top"
          data-tip="PDF in neuem Tab öffnen"
        >
          <a
            href={
              ~p"/tasks/#{@task_id}/submissions/#{@entry.submission_id}/files/#{@entry.file.id}/inline"
            }
            target="_blank"
            rel="noopener"
            aria-label={"PDF «#{@entry.file.original_name}» öffnen"}
            class="p-2 rounded-lg text-stone-400 hover:bg-sky-50 hover:text-sky-600 transition-colors inline-flex"
          >
            <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
          </a>
        </div>

        <div class="tooltip tooltip-delayed tooltip-top" data-tip="Herunterladen">
          <a
            href={~p"/tasks/#{@task_id}/submissions/#{@entry.submission_id}/files/#{@entry.file.id}"}
            target="_blank"
            rel="noopener"
            aria-label={"«#{@entry.file.original_name}» herunterladen"}
            class="p-2 rounded-lg text-stone-400 hover:bg-stone-100 hover:text-stone-700 transition-colors inline-flex"
          >
            <.icon name="hero-arrow-down-tray" class="w-4 h-4" />
          </a>
        </div>
      </div>
    </div>
    """
  end

  ## Lifecycle

  @impl true
  def mount(%{"task_id" => task_id}, _session, socket) do
    task = Tasks.get_task_with_course!(socket.assigns.current_scope, task_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tasky.PubSub, "course:#{task.course_id}:progress")
    end

    {:ok,
     socket
     |> assign(:page_title, "Datei-Abgaben - #{task.name}")
     |> assign(:task, task)
     |> assign(:upload_fields, Tasks.list_task_upload_fields(task))
     |> assign(:students, Courses.list_enrolled_students(task.course_id))
     |> assign(:preview, nil)
     |> assign(:files, Tasks.submission_files_by_student(task))}
  end

  # A plain file upload does not broadcast, so this only catches status changes
  # (handing in, a verdict). Interim uploads show up on the next page load.
  @impl true
  def handle_info({:submission_updated, submission}, socket) do
    if submission.task_id == socket.assigns.task.id do
      {:noreply, assign(socket, :files, Tasks.submission_files_by_student(socket.assigns.task))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("preview_file", %{"file-id" => file_id}, socket) do
    {:noreply, assign(socket, :preview, build_preview(socket.assigns, file_id))}
  end

  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, :preview, nil)}
  end

  ## Helpers

  # Resolves the client-supplied file id against the files already on the page,
  # so the modal can only ever show something this teacher is already looking
  # at — and only an image, which is also all the inline route will serve.
  # The id arrives as a string; comparing it to the integer primary key
  # directly would silently never match.
  defp build_preview(assigns, file_id) do
    Enum.find_value(assigns.students, fn student ->
      Enum.find_value(assigns.upload_fields, &preview_for(assigns, student, &1, file_id))
    end)
  end

  defp preview_for(assigns, student, field, file_id) do
    with %{file: file, submission_id: submission_id} <-
           Map.get(assigns.files, {student.id, field.id}),
         true <- to_string(file.id) == file_id,
         "image" <- type_key(file) do
      %{
        file: file,
        submission_id: submission_id,
        student_name: student_full_name(student),
        field_label: field.label
      }
    else
      _ -> nil
    end
  end

  defp type_key(file), do: file.stored_filename |> Path.extname() |> Uploads.type_key_for_ext()

  defp allowed_types_label(%{allowed_types: []}), do: "Alle erlaubten Typen"

  defp allowed_types_label(%{allowed_types: types}),
    do: Enum.map_join(types, " · ", &type_chip_label/1)

  defp download_path(task_id, %{submission_id: submission_id, file: file}),
    do: ~p"/tasks/#{task_id}/submissions/#{submission_id}/files/#{file.id}"

  defp inline_path(task_id, %{submission_id: submission_id, file: file}),
    do: ~p"/tasks/#{task_id}/submissions/#{submission_id}/files/#{file.id}/inline"

  defp student_full_name(student) do
    case {student.firstname, student.lastname} do
      {blank, blank2} when blank in [nil, ""] and blank2 in [nil, ""] ->
        student.email |> to_string() |> String.split("@") |> List.first()

      {first, blank} when blank in [nil, ""] ->
        first

      {blank, last} when blank in [nil, ""] ->
        last

      {first, last} ->
        "#{first} #{last}"
    end
  end
end
