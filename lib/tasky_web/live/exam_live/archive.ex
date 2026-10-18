defmodule TaskyWeb.ExamLive.Archive do
  @moduledoc """
  The archived exams, as a plain table. Archived exams are done with, so the
  page only has to find one again and bring it back — no cards, no filters.
  """
  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams"}>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-sky-500 mb-3">
            Prüfungsverwaltung
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button navigate={~p"/exams"} tooltip="Zurück zu Prüfungen" />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              Archivierte <em class="italic text-sky-500">Prüfungen</em>
            </h1>
          </div>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Archivierte Prüfungen erscheinen nicht mehr in deiner Liste. Du kannst sie jederzeit wiederherstellen.
          </p>
        </div>
      </div>

      <div class="max-w-6xl mx-auto bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
        <%= if @archived_count == 0 do %>
          <div id="archive-empty" class="flex flex-col items-center text-center px-8 py-16">
            <div class="w-14 h-14 rounded-[14px] bg-stone-50 flex items-center justify-center text-stone-400 mb-5">
              <.icon name="hero-archive-box" class="w-6 h-6" />
            </div>
            <h3 class="text-base font-semibold text-stone-700 mb-2">Keine archivierten Prüfungen</h3>
            <p class="text-sm text-stone-400 max-w-[340px] leading-[1.6]">
              Beendete Prüfungen kannst du in der Prüfungsliste archivieren.
            </p>
          </div>
        <% else %>
          <.table
            id="archived-exams"
            rows={@streams.exams}
            row_click={fn {_id, exam} -> JS.navigate(~p"/exams/#{exam}") end}
          >
            <:col :let={{_id, exam}} label="Name">
              <span class="font-medium text-stone-800">{exam.name}</span>
            </:col>
            <:col :let={{_id, exam}} label="Status">
              <.exam_status_chip status={exam.status} />
            </:col>
            <:col :let={{_id, exam}} label="Lehrperson">{exam.teacher.email}</:col>
            <:col :let={{_id, exam}} label="Erstellt am">{format_date(exam.inserted_at)}</:col>
            <:col :let={{_id, exam}} label="Archiviert am">{format_date(exam.archived_at)}</:col>
            <:action :let={{_id, exam}}>
              <button
                id={"unarchive-#{exam.id}"}
                type="button"
                phx-click="unarchive"
                phx-value-id={exam.id}
                class="inline-flex items-center gap-1.5 whitespace-nowrap text-sm font-medium text-sky-600 transition-colors duration-150 hover:text-sky-700"
              >
                <.icon name="hero-arrow-uturn-left" class="w-4 h-4" /> Wiederherstellen
              </button>
            </:action>
          </.table>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Archivierte Prüfungen")
     |> assign_exams()}
  end

  @impl true
  def handle_event("unarchive", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    exam = Exams.get_exam!(scope, id)

    case Exams.unarchive_exam(scope, exam) do
      {:ok, _exam} ->
        {:noreply,
         socket
         |> put_flash(:info, "„#{exam.name}“ ist wieder in deiner Prüfungsliste.")
         |> assign_exams()}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "Die Prüfung konnte nicht wiederhergestellt werden.")}
    end
  end

  defp assign_exams(socket) do
    exams = Exams.list_exams(socket.assigns.current_scope, archived: true)

    socket
    |> assign(:archived_count, length(exams))
    |> stream(:exams, exams, reset: true)
  end

  defp format_date(%DateTime{} = at), do: Calendar.strftime(at, "%d.%m.%Y")
end
