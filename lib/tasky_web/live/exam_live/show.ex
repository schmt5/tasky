defmodule TaskyWeb.ExamLive.Show do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias TaskyWeb.ExamComponents

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
                popovertarget="exam-actions-menu"
                style="anchor-name:--exam-actions-anchor"
                aria-label="Aktionen"
                class="inline-flex items-center justify-center w-9 h-9 rounded-[6px] text-stone-500 border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-700"
              >
                <.icon name="hero-ellipsis-vertical" class="w-5 h-5" />
              </button>
              <ul
                popover
                id="exam-actions-menu"
                style="position-anchor:--exam-actions-anchor"
                class="dropdown dropdown-end menu z-[60] p-2 shadow-lg bg-white rounded-[10px] w-56 border border-stone-100"
              >
                <li>
                  <.link
                    navigate={~p"/exams/#{@exam}/edit?return_to=show"}
                    class="flex items-center gap-2 text-sm text-stone-700"
                  >
                    <.icon name="hero-pencil" class="w-4 h-4 text-stone-400" /> Umbenennen
                  </.link>
                </li>
                <li>
                  <%!-- Here as well as in the cockpit: the paper copies are
                       prepared *before* the session is opened, while the exam
                       is still a draft and the cockpit is not yet the
                       affordance in front of the teacher. --%>
                  <.link
                    navigate={~p"/exams/#{@exam}/paper"}
                    class="flex items-center gap-2 text-sm text-stone-700"
                  >
                    <.icon name="hero-printer" class="w-4 h-4 text-stone-400" /> Papierversion
                  </.link>
                </li>
                <li>
                  <button
                    type="button"
                    phx-click="duplicate_exam"
                    class="flex items-center gap-2 text-sm text-stone-700"
                  >
                    <.icon name="hero-document-duplicate" class="w-4 h-4 text-stone-400" />
                    Duplizieren
                  </button>
                </li>
                <li>
                  <button
                    type="button"
                    phx-click="delete"
                    data-confirm="Bist du sicher, dass du diese Prüfung löschen möchtest?"
                    class="flex items-center gap-2 text-sm text-red-600 hover:bg-red-50"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" /> Löschen
                  </button>
                </li>
              </ul>
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
            <%!-- Beim Erstellen einmal entschieden und danach fix, deshalb hier
                 als Feststellung statt als Bedienelement. --%>
            <span
              class="tooltip tooltip-bottom tooltip-delayed text-[13px] text-stone-400 flex items-center gap-1"
              data-tip={@answer_mode_option.summary}
            >
              <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
              {@answer_mode_option.state_label}
            </span>
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
                      Die Prüfung ist ein Entwurf. Sobald du bereit bist, kannst du die Durchführung öffnen und dabei festlegen, wer teilnimmt.
                    <% @exam.status == "open" && @exam.participation_mode == "assigned" -> %>
                      Die Durchführung ist offen. Die zugewiesenen Lernenden sehen die Prüfung auf ihrem Dashboard und befinden sich im Warteraum.
                    <% @exam.status == "open" -> %>
                      Die Durchführung ist offen. Teilnehmende können sich über den Einschreibelink einschreiben und befinden sich im Warteraum.
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
                    <.link
                      navigate={~p"/exams/#{@exam}/cockpit/config"}
                      class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                    >
                      Durchführung öffnen
                    </.link>
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
                <%!-- One primary action per row: as long as parts are open the
                      correction is the next step; once every part is corrected the
                      grading takes over and the correction becomes a revisit. --%>
                <%= if @exam.status == "finished" do %>
                  <div class="mt-4 flex items-center gap-3">
                    <.link
                      navigate={~p"/exams/#{@exam}/correction"}
                      class={[
                        "inline-flex items-center gap-2 text-sm font-semibold px-5 py-2.5 rounded-[10px] transition-all duration-150 active:scale-[0.98]",
                        if(@grading_available,
                          do:
                            "text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-700",
                          else:
                            "bg-sky-500 text-white shadow-[0_2px_8px_rgba(14,165,233,0.25)] hover:bg-sky-600"
                        )
                      ]}
                    >
                      <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4" /> Zur Korrektur
                    </.link>
                    <.link
                      :if={@grading_available}
                      navigate={~p"/exams/#{@exam}/correction/grading"}
                      class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
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
     |> assign(:answer_mode_option, ExamComponents.answer_mode_option(exam.answer_mode))
     |> assign(:grading_available, grading_available?(exam))}
  end

  defp grading_available?(exam) do
    parts = Exams.split_content_into_parts(exam.content || %{}, exam.answer_mode)
    submissions = Exams.list_exam_submissions(exam)

    parts != [] and submissions != [] and
      Enum.all?(submissions, fn s ->
        done = MapSet.new(s.corrected_parts || [])
        Enum.all?(parts, fn p -> p.id in done end)
      end)
  end

  @impl true
  def handle_event("delete", _params, socket) do
    {:ok, _} = Exams.delete_exam(socket.assigns.current_scope, socket.assigns.exam)

    {:noreply,
     socket
     |> put_flash(:info, "Prüfung erfolgreich gelöscht")
     |> push_navigate(to: ~p"/exams")}
  end

  @impl true
  def handle_event("duplicate_exam", _params, socket) do
    case Exams.duplicate_exam(
           socket.assigns.current_scope,
           socket.assigns.exam,
           "Kopie von — #{socket.assigns.exam.name}"
         ) do
      {:ok, new_exam} ->
        {:noreply, push_navigate(socket, to: ~p"/exams/#{new_exam}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Prüfung konnte nicht kopiert werden.")}
    end
  end
end
