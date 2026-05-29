defmodule TaskyWeb.ExamLive.Show do
  use TaskyWeb, :live_view

  alias Tasky.Exams

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
              %{label: @exam.name}
            ]} />

            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click="delete"
                data-confirm="Bist du sicher, dass du diese Prüfung löschen möchtest?"
                class="inline-flex items-center gap-2 text-stone-400 text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:text-red-600 hover:bg-red-50"
              >
                <.icon name="hero-trash" class="w-4 h-4" /> Löschen
              </button>
              <button
                type="button"
                phx-click="duplicate_exam"
                class="inline-flex items-center gap-2 text-stone-400 text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:text-sky-600 hover:bg-sky-50"
              >
                <.icon name="hero-document-duplicate" class="w-4 h-4" /> Duplizieren
              </button>
              <.link
                navigate={~p"/exams/#{@exam}/edit?return_to=show"}
                class="inline-flex items-center gap-2 text-stone-700 text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300"
              >
                <.icon name="hero-pencil" class="w-4 h-4" /> Bearbeiten
              </.link>
              <%= if @exam.status in ["open", "running"] do %>
                <.link
                  navigate={~p"/exams/#{@exam}/cockpit"}
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-computer-desktop" class="w-4 h-4" /> Cockpit
                </.link>
              <% end %>
            </div>
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button navigate={~p"/exams"} tooltip="Zurück zu Prüfungen" />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              {@exam.name}
            </h1>
          </div>

          <div class="flex items-center gap-3 mt-2">
            <.exam_status_chip status={@exam.status} />
            <span class="text-[13px] text-stone-400 flex items-center gap-1">
              <.icon name="hero-user" class="w-3.5 h-3.5" /> {@exam.teacher.email}
            </span>
          </div>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <%!-- Status Card --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6">
            <div class="flex items-start gap-4">
              <div class={[
                "w-12 h-12 rounded-[12px] flex items-center justify-center shrink-0",
                @exam.status == "draft" && "bg-amber-50 text-amber-500",
                @exam.status == "open" && "bg-blue-50 text-blue-600",
                @exam.status == "running" && "bg-emerald-50 text-emerald-500",
                @exam.status == "finished" && "bg-stone-100 text-stone-500",
                @exam.status == "archived" && "bg-stone-50 text-stone-400"
              ]}>
                <.icon name="hero-signal" class="w-6 h-6" />
              </div>
              <div class="flex-1">
                <h3 class="text-base font-semibold text-stone-800 mb-1.5">
                  Status
                </h3>
                <p class="text-sm text-stone-500 leading-relaxed">
                  <%= cond do %>
                    <% @exam.status == "draft" -> %>
                      Die Prüfung ist ein Entwurf. Sobald du bereit bist, kannst du die Durchführung öffnen, damit sich Lernende einschreiben können.
                    <% @exam.status == "open" -> %>
                      Die Durchführung ist offen. Lernende können sich mit dem Einschreibeschlüssel anmelden und befinden sich im Warteraum.
                    <% @exam.status == "running" -> %>
                      Die Prüfung läuft. Lernende bearbeiten gerade die Prüfung.
                    <% @exam.status == "finished" -> %>
                      Die Prüfung ist beendet. Keine weiteren Abgaben möglich.
                    <% @exam.status == "archived" -> %>
                      Die Prüfung ist archiviert und nicht mehr aktiv.
                  <% end %>
                </p>
                <%= if @exam.status == "draft" do %>
                  <div class="mt-4 flex items-center gap-3">
                    <button
                      type="button"
                      phx-click="open_session"
                      class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                    >
                      Durchführung öffnen
                    </button>
                  </div>
                <% end %>
                <%= if @exam.status in ["open", "running"] do %>
                  <div class="mt-4 flex items-center gap-3">
                    <.link
                      navigate={~p"/exams/#{@exam}/cockpit"}
                      class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                    >
                      <.icon name="hero-computer-desktop" class="w-4 h-4" /> Zum Cockpit
                    </.link>
                  </div>
                <% end %>
                <%= if @exam.status == "finished" do %>
                  <div class="mt-4 flex items-center gap-3">
                    <.link
                      navigate={~p"/exams/#{@exam}/correction"}
                      class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                    >
                      <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4" /> Zur Korrektur
                    </.link>
                    <.link
                      :if={@grading_available}
                      navigate={~p"/exams/#{@exam}/correction/grading"}
                      class="inline-flex items-center gap-2 text-white text-sm font-semibold bg-gradient-to-r from-sky-500 to-indigo-500 hover:from-sky-600 hover:to-indigo-600 hover:shadow-md px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 active:scale-[0.98]"
                    >
                      <.icon name="hero-academic-cap" class="w-4 h-4" /> Zur Benotung
                    </.link>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <%!-- Content Section --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6 border-b border-stone-100">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-lg font-semibold text-stone-800">Inhalt</h2>
                <p class="text-sm text-stone-500 mt-1">Vorschau des Prüfungsinhalts</p>
              </div>
              <.link
                navigate={~p"/exams/#{@exam}/content"}
                class={[
                  "inline-flex items-center gap-1.5 text-[13px] font-semibold px-3 py-1.5 rounded-[6px] transition-all duration-150 active:scale-[0.98]",
                  if(@exam.status == "draft",
                    do:
                      "bg-sky-500 text-white shadow-[0_2px_8px_rgba(14,165,233,0.25)] hover:bg-sky-600",
                    else:
                      "text-stone-500 border border-stone-200 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-700"
                  )
                ]}
              >
                <.icon name="hero-pencil" class="w-3.5 h-3.5" /> Bearbeiten
              </.link>
            </div>
          </div>
          <div class="p-6">
            <%= if @exam.content && @exam.content != %{} do %>
              <% heading_text = extract_first_heading(@exam.content) %>
              <%= if heading_text do %>
                <div class="flex items-start gap-3">
                  <div class="w-1 self-stretch rounded-full bg-stone-200 shrink-0"></div>
                  <div>
                    <p class="text-base text-stone-700 font-medium leading-relaxed">{heading_text}</p>
                    <p class="text-xs text-stone-400 mt-2 tracking-wide uppercase">
                      Auszug aus dem Prüfungsinhalt
                    </p>
                  </div>
                </div>
              <% else %>
                <p class="text-sm text-stone-400 italic">
                  Inhalt vorhanden, aber keine Überschrift gefunden
                </p>
              <% end %>
            <% else %>
              <p class="text-sm text-stone-400">Kein Inhalt vorhanden</p>
            <% end %>
          </div>
        </div>

      </div>
    </Layouts.app>
    """
  end

  defp extract_first_heading(%{"content" => blocks}) when is_list(blocks) do
    Enum.find_value(blocks, fn
      %{"type" => "heading", "content" => children} when is_list(children) ->
        children
        |> Enum.map_join("", fn
          %{"text" => text} -> text
          _ -> ""
        end)
        |> case do
          "" -> nil
          text -> text
        end

      _ ->
        nil
    end)
  end

  defp extract_first_heading(_), do: nil

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, exam.name)
     |> assign(:exam, exam)
     |> assign(:grading_available, grading_available?(exam))}
  end

  defp grading_available?(exam) do
    parts = Exams.split_content_into_parts(exam.content || %{})
    submissions = Exams.list_exam_submissions(exam)

    parts != [] and submissions != [] and
      Enum.all?(submissions, fn s ->
        done = MapSet.new(s.corrected_parts || [])
        Enum.all?(parts, fn p -> p.id in done end)
      end)
  end

  @impl true
  def handle_event("delete", _params, socket) do
    {:ok, _} = Exams.delete_exam(socket.assigns.exam)

    {:noreply,
     socket
     |> put_flash(:info, "Prüfung erfolgreich gelöscht")
     |> push_navigate(to: ~p"/exams")}
  end

  @impl true
  def handle_event("duplicate_exam", _params, socket) do
    case Exams.duplicate_exam(socket.assigns.current_scope, socket.assigns.exam) do
      {:ok, new_exam} ->
        {:noreply, push_navigate(socket, to: ~p"/exams/#{new_exam}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Prüfung konnte nicht kopiert werden.")}
    end
  end

  @impl true
  def handle_event("open_session", _params, socket) do
    case Exams.open_exam_session(socket.assigns.exam) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> put_flash(:info, "Durchführung geöffnet")
         |> push_navigate(to: ~p"/exams/#{exam}/cockpit")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Durchführung konnte nicht geöffnet werden.")}
    end
  end
end
