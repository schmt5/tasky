defmodule TaskyWeb.ExamLive.Index do
  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams"}>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-amber-500 mb-3">
            Prüfungsverwaltung
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Meine <em class="italic text-amber-500">Prüfungen</em>
          </h1>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Verwalte deine Prüfungen, Inhalte und Musterlösungen.
          </p>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
        <div class="flex items-center justify-between p-6 border-b border-stone-100">
          <div>
            <h2 class="text-lg font-semibold text-stone-800">Alle Prüfungen</h2>

            <p class="text-sm text-stone-500 mt-1">{@exam_count} Prüfungen insgesamt</p>
          </div>

          <.link
            navigate={~p"/exams/new"}
            class="inline-flex items-center gap-2 bg-amber-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(245,158,11,0.25)] transition-all duration-150 hover:bg-amber-600 active:scale-[0.98]"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Neue Prüfung
          </.link>
        </div>

        <ul :if={@has_exams} id="exams" phx-update="stream" class="list-none p-0 m-0">
          <li
            :for={{id, exam} <- @streams.exams}
            id={id}
            class="flex items-start gap-5 px-6 py-5 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 hover:bg-stone-50"
          >
            <.link
              navigate={~p"/exams/#{exam}"}
              class="w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5 bg-amber-100 text-amber-600"
            >
              <.icon name="hero-document-text" class="w-5 h-5" />
            </.link>
            <.link
              navigate={~p"/exams/#{exam}"}
              class="flex-1 min-w-0 flex flex-col gap-1.5"
            >
              <div class="flex items-center gap-2.5 flex-wrap">
                <h3 class="text-[15px] font-semibold text-stone-800 leading-[1.4]">{exam.name}</h3>

                <span class={[
                  "inline-flex items-center text-[11px] font-semibold px-2.5 py-0.5 rounded-full whitespace-nowrap tracking-[0.01em]",
                  exam.status == "draft" && "bg-amber-100 text-amber-700",
                  exam.status == "open" && "bg-sky-100 text-sky-700",
                  exam.status == "running" && "bg-emerald-100 text-emerald-700",
                  exam.status == "finished" && "bg-purple-100 text-purple-700",
                  exam.status == "archived" && "bg-stone-100 text-stone-500"
                ]}>
                  <%= cond do %>
                    <% exam.status == "open" -> %>
                      Offen
                    <% exam.status == "running" -> %>
                      Laufend
                    <% exam.status == "finished" -> %>
                      Beendet
                    <% exam.status == "archived" -> %>
                      Archiviert
                    <% true -> %>
                      Entwurf
                  <% end %>
                </span>
              </div>

              <div class="flex items-center gap-2 mt-1">
                <span class="text-[13px] text-stone-400 flex items-center gap-1">
                  <.icon name="hero-user" class="w-3.5 h-3.5" /> {exam.teacher.email}
                </span>
                <%= if exam.enrollment_token do %>
                  <span class="text-xs text-stone-300">·</span>
                  <span class="text-[13px] text-stone-400 flex items-center gap-1">
                    <.icon name="hero-key" class="w-3.5 h-3.5" /> Token vorhanden
                  </span>
                <% end %>
              </div>
            </.link>
            <div class="flex items-center gap-2 shrink-0 pt-0.5">
              <.link
                navigate={~p"/exams/#{exam}/edit"}
                class="inline-flex items-center gap-2 bg-transparent text-stone-500 text-[13px] font-medium px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-amber-50 hover:text-amber-600"
              >
                <.icon name="hero-pencil-square" class="w-4 h-4" /> Bearbeiten
              </.link>
            </div>
          </li>
        </ul>

        <div :if={!@has_exams} class="flex flex-col items-center text-center px-8 py-16 bg-white">
          <div class="w-14 h-14 rounded-[14px] bg-amber-50 flex items-center justify-center text-amber-400 mb-5">
            <.icon name="hero-document-text" class="w-6 h-6" />
          </div>

          <h3 class="text-base font-semibold text-stone-700 mb-2">Noch keine Prüfungen</h3>

          <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6] mb-6">
            Erstelle deine erste Prüfung, um loszulegen.
          </p>

          <.link
            navigate={~p"/exams/new"}
            class="inline-flex items-center gap-2 bg-amber-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(245,158,11,0.25)] transition-all duration-150 hover:bg-amber-600 active:scale-[0.98]"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Erste Prüfung erstellen
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    exams = Exams.list_exams(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Prüfungen")
     |> assign(:exam_count, length(exams))
     |> assign(:has_exams, length(exams) > 0)
     |> stream(:exams, exams)}
  end
end
