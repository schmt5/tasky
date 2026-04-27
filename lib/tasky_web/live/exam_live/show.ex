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

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            {@exam.name}
          </h1>

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

        <%!-- Sample Solution Section --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6 border-b border-stone-100">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-lg font-semibold text-stone-800">Musterlösung</h2>
                <p class="text-sm text-stone-500 mt-1">
                  Die Musterlösung dieser Prüfung als JSON-Daten
                </p>
              </div>
              <%= if @has_sample_solution do %>
                <.link
                  navigate={~p"/exams/#{@exam}/sample-solution"}
                  class="inline-flex items-center gap-1.5 text-[13px] font-semibold px-3 py-1.5 rounded-[6px] transition-all duration-150 active:scale-[0.98] text-stone-500 border border-stone-200 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-700"
                >
                  <.icon name="hero-pencil" class="w-3.5 h-3.5" /> Bearbeiten
                </.link>
              <% else %>
                <button
                  id="create-sample-solution-btn"
                  type="button"
                  phx-click="show_sample_solution_modal"
                  class="inline-flex items-center gap-1.5 text-[13px] font-semibold px-3 py-1.5 rounded-[6px] transition-all duration-150 active:scale-[0.98] bg-sky-500 text-white shadow-[0_2px_8px_rgba(14,165,233,0.25)] hover:bg-sky-600"
                >
                  <.icon name="hero-plus" class="w-3.5 h-3.5" /> Erstellen
                </button>
              <% end %>
            </div>
          </div>
          <div class="p-6">
            <%= cond do %>
              <% not @has_sample_solution -> %>
                <p class="text-sm text-stone-400">Keine Musterlösung vorhanden</p>
              <% @sample_solution_parts == [] -> %>
                <p class="text-sm text-stone-400 italic">
                  Musterlösung vorhanden, aber keine Teile gefunden.
                </p>
              <% true -> %>
                <ul class="divide-y divide-stone-100 -mx-2">
                  <li :for={part <- @sample_solution_parts}>
                    <.link
                      navigate={~p"/exams/#{@exam}/sample-solution/parts/#{part.id}"}
                      class="flex items-center justify-between gap-4 px-3 py-2.5 rounded-lg transition-colors duration-150 hover:bg-stone-50 group"
                    >
                      <span class="text-sm font-medium text-stone-700 truncate group-hover:text-stone-900">
                        {part.label}
                      </span>
                      <.icon
                        name="hero-chevron-right"
                        class="w-4 h-4 text-stone-300 group-hover:text-stone-500 shrink-0"
                      />
                    </.link>
                  </li>
                </ul>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Sample Solution Confirmation Modal --%>
      <%= if @show_sample_solution_modal do %>
        <dialog
          id="sample-solution-modal"
          class="modal modal-open"
          phx-window-keydown="close_sample_solution_modal"
          phx-key="escape"
        >
          <%!-- Modal backdrop --%>
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_sample_solution_modal"></div>
          <%!-- Modal box --%>
          <div class="modal-box max-w-lg p-0 bg-white rounded-[16px] shadow-2xl flex flex-col">
            <%!-- Modal Header --%>
            <div class="px-6 pt-6 pb-4">
              <div class="flex items-start gap-4">
                <div class="w-10 h-10 rounded-[10px] bg-sky-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-light-bulb" class="w-5 h-5 text-sky-500" />
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-lg font-semibold text-stone-900">
                    Musterlösung erstellen
                  </h3>
                  <p class="text-sm text-stone-500 leading-relaxed mt-2">
                    Die Musterlösung wird basierend auf dem jetzigen Stand des Inhaltes generiert. Nachträgliche Änderungen am Inhalt müssen manuell in der Musterlösung übernommen werden.
                  </p>
                </div>
              </div>
            </div>
            <%!-- Modal Footer --%>
            <div class="px-6 pb-6 pt-2 flex items-center justify-end gap-3">
              <button
                id="cancel-sample-solution-btn"
                type="button"
                phx-click="close_sample_solution_modal"
                class="inline-flex items-center gap-2 text-stone-700 text-sm font-semibold px-4 py-2 rounded-[8px] border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300"
              >
                Abbrechen
              </button>
              <.link
                id="confirm-sample-solution-btn"
                navigate={~p"/exams/#{@exam}/sample-solution"}
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-4 py-2 rounded-[8px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
              >
                Erstellen
              </.link>
            </div>
          </div>
        </dialog>
      <% end %>
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

  defp has_sample_solution?(exam) do
    exam.sample_solution != nil and exam.sample_solution != %{}
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, exam.name)
     |> assign(:exam, exam)
     |> assign(:has_sample_solution, has_sample_solution?(exam))
     |> assign(
       :sample_solution_parts,
       Exams.split_content_into_parts(exam.sample_solution || %{})
     )
     |> assign(:show_sample_solution_modal, false)}
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

  @impl true
  def handle_event("show_sample_solution_modal", _params, socket) do
    {:noreply, assign(socket, :show_sample_solution_modal, true)}
  end

  @impl true
  def handle_event("close_sample_solution_modal", _params, socket) do
    {:noreply, assign(socket, :show_sample_solution_modal, false)}
  end
end
