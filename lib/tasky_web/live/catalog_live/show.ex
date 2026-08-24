defmodule TaskyWeb.CatalogLive.Show do
  @moduledoc """
  Read-only-Vorschau eines Katalog-Kurses samt Übernahme in das eigene Konto.

  Bewusst ohne Status- und Sperr-Chips an den Lerneinheiten: das ist der
  Freigabezustand der Autorin für ihre Klasse und würde hier als Aussage über
  die eigene Kopie gelesen. Der Import legt ohnehin alles als Entwurf an.
  """
  use TaskyWeb, :live_view

  import TaskyWeb.FileComponents, only: [file_badge: 1, file_type_label: 1]

  alias Tasky.Courses
  alias Tasky.Courses.DuplicateRunner
  alias Tasky.Tasks
  alias Tasky.Uploads
  alias TaskyWeb.Params

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/catalog"}>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Katalog", navigate: ~p"/catalog"},
              %{label: @course.name}
            ]} />

            <button
              type="button"
              id="import-catalog-course"
              phx-click="open_import"
              class="inline-flex items-center gap-2 bg-sky-500 text-white text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
            >
              <.icon name="hero-arrow-down-on-square" class="w-4 h-4" /> In meine Kurse übernehmen
            </button>
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button navigate={~p"/catalog"} tooltip="Zurück zum Katalog" />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              {@course.name}
            </h1>
          </div>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            {@course.description || "Keine Beschreibung verfügbar"}
          </p>

          <div class="flex items-center gap-2 mt-4 flex-wrap">
            <span class="text-[13px] text-stone-400 flex items-center gap-1">
              <.icon name="hero-user" class="w-3.5 h-3.5" />{author_name(@course.teacher)}
            </span>
            <span class="text-xs text-stone-300">·</span>
            <span class="text-[13px] text-stone-400 flex items-center gap-1">
              <.icon name="hero-clipboard-document-list" class="w-3.5 h-3.5" />{@unit_count} Lerneinheiten
            </span>
            <span class="text-xs text-stone-300">·</span>
            <span class="text-[13px] text-stone-400 flex items-center gap-1">
              <.icon name="hero-calendar-days" class="w-3.5 h-3.5" />
              Veröffentlicht am {format_date(@course.catalog_published_at)}
            </span>
          </div>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 mb-8">
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div class="flex items-center gap-3">
            <.icon name="hero-eye" class="w-5 h-5 text-blue-600 flex-shrink-0" />
            <div class="flex-1">
              <p class="text-[14px] font-medium text-blue-900">Vorschau</p>
              <p class="text-[13px] text-blue-700">
                Du siehst diesen Kurs nur zum Lesen. Erst beim Übernehmen entsteht eine eigene Kopie in deinen Kursen.
              </p>
            </div>
          </div>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
        <div class="p-6 border-b border-stone-100">
          <h2 class="text-lg font-semibold text-stone-800">Lerneinheiten</h2>
          <p class="text-sm text-stone-500 mt-1">{@unit_count} Einheiten in diesem Kurs</p>
        </div>

        <div
          :for={unit <- @units}
          id={"catalog-unit-#{unit.id}"}
          class="px-6 py-5 border-b border-stone-100 last:border-b-0"
        >
          <div class="flex items-start gap-5">
            <div class="w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5 bg-stone-100 text-stone-500">
              <.icon name="hero-document-text" class="w-5 h-5" />
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2.5 flex-wrap">
                <h3 class="text-[15px] font-semibold text-stone-800 leading-[1.4]">{unit.name}</h3>
                <.extended_chip :if={unit.extended} />
              </div>

              <div class="flex items-center gap-2 mt-1.5 flex-wrap">
                <span
                  :if={unit.attachments != []}
                  class="text-[13px] text-stone-400 flex items-center gap-1"
                >
                  <.icon name="hero-paper-clip" class="w-3.5 h-3.5" />{length(unit.attachments)} Anhänge
                </span>
                <span
                  :if={unit.upload_fields != []}
                  class="text-[13px] text-stone-400 flex items-center gap-1"
                >
                  <.icon name="hero-arrow-up-tray" class="w-3.5 h-3.5" />{length(unit.upload_fields)} Datei-Abgaben
                </span>
              </div>
            </div>
            <button
              type="button"
              id={"toggle-catalog-unit-#{unit.id}"}
              phx-click="toggle_unit"
              phx-value-id={unit.id}
              class="inline-flex items-center gap-2 bg-transparent text-stone-500 text-[13px] font-medium px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-sky-50 hover:text-sky-600 shrink-0"
            >
              <%= if unit.id in @expanded_units do %>
                <.icon name="hero-chevron-up" class="w-4 h-4" /> Inhalt ausblenden
              <% else %>
                <.icon name="hero-chevron-down" class="w-4 h-4" /> Inhalt anzeigen
              <% end %>
            </button>
          </div>

          <div :if={unit.id in @expanded_units} class="mt-4 pl-14">
            <%!-- React owns this subtree, hence phx-update="ignore". --%>
            <div class="bg-white rounded-[12px] border border-stone-200">
              <div
                id={"catalog-unit-viewer-#{unit.id}"}
                phx-hook="ExamReadOnlyViewer"
                phx-update="ignore"
                data-content={Jason.encode!(unit.content || %{})}
              >
              </div>
            </div>

            <div :if={unit.attachments != []} class="mt-4 space-y-2">
              <div
                :for={attachment <- unit.attachments}
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
                  href={~p"/uploads/tasks/#{unit.id}/attachments/#{attachment.stored_filename}"}
                  target="_blank"
                  rel="noopener"
                  class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-sm font-semibold px-3.5 py-2 rounded-lg transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 shrink-0"
                >
                  <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Herunterladen
                </a>
              </div>
            </div>
          </div>
        </div>

        <div :if={@units == []} class="flex flex-col items-center text-center px-8 py-16 bg-white">
          <div class="w-14 h-14 rounded-[14px] bg-stone-50 flex items-center justify-center text-stone-400 mb-5">
            <.icon name="hero-document-text" class="w-6 h-6" />
          </div>

          <h3 class="text-base font-semibold text-stone-700 mb-2">Keine Lerneinheiten</h3>

          <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6]">
            Dieser Kurs enthält im Moment keine Lerneinheiten.
          </p>
        </div>
      </div>

      <%!-- Import Confirmation Modal --%>
      <%= if @importing do %>
        <dialog
          id="import-catalog-course-modal"
          class="modal modal-open"
          phx-window-keydown="close_import"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_import"></div>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-sky-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-arrow-down-on-square" class="w-5 h-5 text-sky-600" />
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-stone-800">In meine Kurse übernehmen</h3>
                  <p class="text-xs text-stone-400 mt-0.5">
                    Es entsteht ein neuer Kurs in deinem Konto.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6">
              <p class="text-sm text-stone-600 leading-relaxed">
                <span class="font-semibold text-stone-800">«{@course.name}»</span>
                mit allen {@unit_count} Lerneinheiten übernehmen?
              </p>
              <div class="bg-amber-50 rounded-lg p-3 mt-4 border border-amber-100">
                <div class="flex items-start gap-2.5">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-4 h-4 text-amber-500 shrink-0 mt-0.5"
                  />
                  <p class="text-xs text-amber-700 leading-relaxed">
                    Alle Lerneinheiten werden als Entwurf und entsperrt angelegt – du gibst sie selbst frei. Lernende und Abgaben werden nicht kopiert.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6 pt-0 flex items-center justify-end gap-3">
              <button
                type="button"
                phx-click="close_import"
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Abbrechen
              </button>
              <button
                type="button"
                id="confirm-import-catalog-course"
                phx-click="import_course"
                phx-disable-with="Wird übernommen…"
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <.icon name="hero-arrow-down-on-square" class="w-4 h-4" /> Übernehmen
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <.duplicate_progress_modal
        :if={@import_status}
        id="import-progress-modal"
        status={@import_status}
        title="Kurs wird übernommen"
        subtitle="Die Dateien werden kopiert."
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    course = Courses.get_catalog_course!(socket.assigns.current_scope, id)
    units = Tasks.list_tasks_for_export(course.id)

    {:ok,
     socket
     |> assign(:page_title, course.name)
     |> assign(:course, course)
     |> assign(:units, units)
     |> assign(:unit_count, length(units))
     |> assign(:expanded_units, [])
     |> assign(:importing, false)
     |> assign(:import_status, nil)}
  end

  @impl true
  def handle_event("toggle_unit", %{"id" => id}, socket) do
    case Params.int(id) do
      nil ->
        {:noreply, socket}

      unit_id ->
        expanded = socket.assigns.expanded_units

        expanded =
          if unit_id in expanded, do: List.delete(expanded, unit_id), else: [unit_id | expanded]

        {:noreply, assign(socket, :expanded_units, expanded)}
    end
  end

  @impl true
  def handle_event("open_import", _params, socket) do
    {:noreply, assign(socket, :importing, true)}
  end

  @impl true
  def handle_event("close_import", _params, socket) do
    {:noreply, assign(socket, :importing, false)}
  end

  @impl true
  def handle_event("import_course", _params, socket) do
    case DuplicateRunner.start_catalog_import(
           socket.assigns.current_scope,
           socket.assigns.course.id,
           socket.assigns.course.name,
           self()
         ) do
      {:ok, course, 0} ->
        {:noreply,
         socket
         |> put_flash(:info, "Kurs wurde in deine Kurse übernommen.")
         |> push_navigate(to: ~p"/courses/#{course}")}

      {:ok, course, total} ->
        {:noreply,
         socket
         |> assign(:importing, false)
         |> assign(:import_status, %{course_id: course.id, done: 0, total: total})}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:importing, false)
         |> put_flash(:error, "Dieser Kurs ist nicht mehr im Katalog.")
         |> push_navigate(to: ~p"/catalog")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:importing, false)
         |> put_flash(:error, "Kurs konnte nicht übernommen werden.")}
    end
  end

  @impl true
  def handle_info({:duplicate_progress, status}, socket) do
    {:noreply, update(socket, :import_status, &(&1 && Map.merge(&1, status)))}
  end

  @impl true
  def handle_info({:duplicate_done, %{course_id: course_id, failed: failed}}, socket) do
    # Die Records sind so oder so committed — ein Kopierfehler wird gemeldet,
    # nicht als gescheiterter Import behandelt, darum reitet die Zahl im
    # :info-Text mit.
    message =
      if failed == 0 do
        "Kurs wurde in deine Kurse übernommen."
      else
        "Kurs übernommen — #{failed} Datei(en) konnten nicht kopiert werden."
      end

    {:noreply,
     socket
     |> assign(:import_status, nil)
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/courses/#{course_id}")}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp author_name(user) do
    case String.trim("#{user.firstname || ""} #{user.lastname || ""}") do
      "" -> user.email || ""
      name -> name
    end
  end

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y")
  defp format_date(_), do: ""
end
