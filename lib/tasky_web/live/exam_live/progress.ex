defmodule TaskyWeb.ExamLive.Progress do
  @moduledoc """
  Der Fortschritt einer Prüfung als Raster: die Aufgaben untereinander, die
  Teilnehmenden nebeneinander.

  Das Raster fragt selbst nach, statt sich etwas schicken zu lassen. Der
  Autosave der Lernenden (`Exams.update_exam_submission_content/2`) ist der
  heisseste Pfad der App und bleibt unberührt: kein Broadcast, keine
  Berechnung. Alle 5 Sekunden liest diese Ansicht nur `id`, `submitted` und
  `updated_at` und lädt den Inhalt allein der Abgaben nach, die sich geändert
  haben — pro Takt höchstens ein Lesezugriff pro Person, egal wie oft sie
  speichert. Gerechnet wird hier, im Prozess der Lehrperson.
  """
  use TaskyWeb, :live_view

  import TaskyWeb.ExamComponents, only: [participant_name: 1]

  alias Tasky.Exams
  alias Tasky.Exams.Progress

  @tick_ms 5_000
  @polling_statuses ~w(open running)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-7xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Cockpit", navigate: ~p"/exams/#{@exam}/cockpit"},
              %{label: "Fortschritt"}
            ]} />
          </div>

          <div class="flex items-center justify-between gap-6">
            <div class="flex items-center gap-3 mb-3">
              <.back_button
                navigate={~p"/exams/#{@exam}/cockpit"}
                tooltip="Zurück zum Cockpit"
              />
              <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
                Fortschritt
              </h1>
            </div>

            <div
              :if={@exam.status == "running"}
              id="progress-live-indicator"
              class="inline-flex items-center gap-2 bg-emerald-50 text-emerald-700 text-sm font-semibold px-3 py-1.5 rounded-full"
              title="Der Stand wird alle 5 Sekunden aktualisiert."
            >
              <span class="relative flex w-2 h-2">
                <span class="absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75 animate-ping" />
                <span class="relative inline-flex w-2 h-2 rounded-full bg-emerald-500" />
              </span>
              Live
            </div>
          </div>

          <p class="text-[15px] text-stone-500 leading-[1.7]">
            Stand der Aufgaben pro Lernenden – {@exam.name}
          </p>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-8 pb-8">
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <%= if @parts != [] and @rows != [] do %>
            <div class="overflow-x-auto">
              <table id="exam-progress-grid" class="min-w-full divide-y divide-stone-200">
                <thead class="bg-stone-50">
                  <tr>
                    <th
                      scope="col"
                      class="sticky left-0 z-10 bg-stone-50 px-6 py-4 text-left align-bottom border-r border-stone-200 w-[320px] min-w-[320px] max-w-[320px]"
                    >
                      <button
                        type="button"
                        id="toggle-anonymize"
                        phx-click="toggle_anonymize"
                        class="inline-flex items-center gap-2 px-2 py-1 -mx-2 rounded-lg hover:bg-stone-200 transition-colors"
                        title={if @anonymized, do: "Namen anzeigen", else: "Namen ausblenden"}
                      >
                        <.icon
                          name={if @anonymized, do: "hero-eye-slash", else: "hero-eye"}
                          class="w-4 h-4 text-stone-600"
                        />
                        <span class="text-xs font-semibold text-stone-700 uppercase tracking-wider">
                          Aufgaben
                        </span>
                      </button>
                    </th>

                    <th
                      :for={{row, index} <- Enum.with_index(@rows)}
                      id={"participant-#{row.id}"}
                      scope="col"
                      class="px-2 py-4 align-bottom"
                    >
                      <%!-- Opens the participant's whole exam in the correction. --%>
                      <.link
                        navigate={~p"/exams/#{@exam}/correction/#{row.id}"}
                        id={"participant-link-#{row.id}"}
                        class="tooltip tooltip-bottom tooltip-delayed flex flex-col items-center gap-1.5 w-[64px] mx-auto rounded-lg py-1 transition-colors duration-150 hover:bg-stone-100"
                        data-tip={participant_title(row, index, @anonymized)}
                      >
                        <div class="relative">
                          <%= if @anonymized do %>
                            <div class="w-8 h-8 rounded-full flex items-center justify-center bg-sky-100 text-sky-700 text-[11px] font-semibold">
                              ?
                            </div>
                          <% else %>
                            <.participant_avatar person={row} size="sm" />
                          <% end %>
                          <span
                            :if={row.submitted}
                            id={"submitted-#{row.id}"}
                            class="absolute -bottom-1 -right-1 w-4 h-4 rounded-full bg-emerald-500 border-2 border-stone-50 flex items-center justify-center"
                          >
                            <.icon name="hero-check-micro" class="w-2.5 h-2.5 text-white" />
                          </span>
                        </div>
                        <span class="block w-full truncate text-center text-[11px] font-medium text-stone-600 normal-case">
                          {short_name(row, index, @anonymized)}
                        </span>
                      </.link>
                    </th>
                    <%!-- Takes up the slack, so a short class does not stretch the task column. --%>
                    <th aria-hidden="true" class="w-full"></th>
                  </tr>
                </thead>

                <tbody class="bg-white divide-y divide-stone-100">
                  <tr
                    :for={part <- @parts}
                    id={"part-#{part.id}"}
                    class="hover:bg-stone-50 transition-colors duration-150"
                  >
                    <th
                      scope="row"
                      class="sticky left-0 z-10 bg-white px-6 py-3 text-left font-normal border-r border-stone-200 w-[320px] min-w-[320px] max-w-[320px]"
                    >
                      <span
                        class="text-[14px] font-medium text-stone-800 line-clamp-2"
                        title={part.label}
                      >
                        {part.label}
                      </span>
                      <span class="block text-[12px] text-stone-400 mt-0.5 tabular-nums">
                        {started_count(@cells, @rows, part.id)} von {length(@rows)} bearbeitet
                      </span>
                    </th>

                    <td :for={{row, index} <- Enum.with_index(@rows)} class="px-2 py-3">
                      <.progress_cell
                        id={"cell-#{row.id}-#{part.id}"}
                        status={Map.get(@cells, {row.id, part.id}, :not_started)}
                        title={"#{short_name(row, index, @anonymized)} · #{part.label}"}
                        path={~p"/exams/#{@exam}/correction/#{row.id}/parts/#{part.id}"}
                      />
                    </td>
                    <td aria-hidden="true" class="w-full"></td>
                  </tr>
                </tbody>
              </table>
            </div>

            <%!-- Legend --%>
            <div class="border-t border-stone-200 bg-stone-50 px-6 py-4 space-y-3">
              <div class="flex items-center justify-center gap-8 flex-wrap">
                <div :for={status <- statuses()} class="flex items-center gap-2">
                  <div class={[
                    "w-6 h-6 rounded-[6px] flex items-center justify-center",
                    status_style(status).bg
                  ]}>
                    <.icon
                      name={status_style(status).icon}
                      class={["w-4 h-4", status_style(status).fg]}
                    />
                  </div>
                  <span class="text-[13px] text-stone-600">{status_style(status).label}</span>
                </div>
              </div>
              <p class="text-center text-[12px] text-stone-400 leading-[1.6]">
                Richtig, teilweise und falsch gibt es nur bei automatisch korrigierten Aufgaben. Die Farben sind ein Zwischenstand, keine Bewertung: Leere Felder zählen als falsch, und ein nicht angekreuztes Kästchen gilt als nicht begonnen.
              </p>
            </div>
          <% else %>
            <div id="progress-empty" class="flex flex-col items-center text-center px-8 py-16">
              <div class="w-14 h-14 rounded-[14px] bg-emerald-50 flex items-center justify-center text-emerald-400 mb-5">
                <.icon name="hero-chart-bar" class="w-6 h-6" />
              </div>

              <h3 class="text-base font-semibold text-stone-700 mb-2">Noch kein Fortschritt</h3>

              <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6]">
                <%= if @parts == [] do %>
                  Diese Prüfung hat noch keine Aufgaben.
                <% else %>
                  Sobald Lernende an der Prüfung teilnehmen, erscheint hier ihr Stand.
                <% end %>
              </p>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :status, :atom, required: true
  attr :title, :string, required: true
  attr :path, :string, required: true, doc: "grading this part of this participant"

  defp progress_cell(assigns) do
    assigns = assign(assigns, :style, status_style(assigns.status))

    ~H"""
    <div class="flex justify-center">
      <div class="tooltip tooltip-delayed" data-tip={"#{@title}: #{@style.label}"}>
        <.link
          navigate={@path}
          id={@id}
          data-status={@status}
          class={[
            "w-10 h-10 rounded-[8px] flex items-center justify-center transition-all duration-300 hover:ring-2 hover:ring-sky-400 hover:ring-offset-1",
            @style.bg,
            @status != :not_started && "shadow-sm"
          ]}
        >
          <.icon name={@style.icon} class={["w-5 h-5", @style.fg]} />
        </.link>
      </div>
    </div>
    """
  end

  defp statuses, do: [:not_started, :answered, :correct, :partial, :wrong]

  defp status_style(:not_started),
    do: %{bg: "bg-stone-200", fg: "text-stone-400", icon: "hero-minus", label: "Nicht begonnen"}

  defp status_style(:answered),
    do: %{
      bg: "bg-sky-500",
      fg: "text-white",
      icon: "hero-ellipsis-horizontal",
      label: "Bearbeitet"
    }

  defp status_style(:correct),
    do: %{bg: "bg-emerald-500", fg: "text-white", icon: "hero-check", label: "Richtig"}

  defp status_style(:partial),
    do: %{
      bg: "bg-amber-400",
      fg: "text-white",
      icon: "hero-adjustments-horizontal",
      label: "Teilweise richtig"
    }

  defp status_style(:wrong),
    do: %{bg: "bg-rose-500", fg: "text-white", icon: "hero-x-mark", label: "Falsch"}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    if connected?(socket) do
      Exams.subscribe_exam(exam.id)
      Phoenix.PubSub.subscribe(Tasky.PubSub, "exam_cockpit:#{exam.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Fortschritt")
     |> assign(:anonymized, false)
     |> assign(:tick_scheduled?, false)
     |> assign_exam(exam)
     |> refresh()
     |> schedule_tick()}
  end

  @impl true
  def handle_event("toggle_anonymize", _params, socket) do
    {:noreply, assign(socket, :anonymized, !socket.assigns.anonymized)}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply,
     socket
     |> assign(:tick_scheduled?, false)
     |> refresh()
     |> schedule_tick()}
  end

  # A status change can come with an edited exam (reopened and changed), so
  # the parts are prepared again and every cell is recomputed.
  def handle_info({:exam_status_changed, exam}, socket) do
    {:noreply,
     socket
     |> assign_exam(exam)
     |> refresh()
     |> schedule_tick()}
  end

  def handle_info({:submission_submitted, _submission}, socket),
    do: {:noreply, refresh(socket)}

  def handle_info({:participant_removed, _submission_id}, socket),
    do: {:noreply, refresh(socket)}

  def handle_info({:seb_exemption_changed, _submission}, socket), do: {:noreply, socket}

  defp assign_exam(socket, exam) do
    prepared = Progress.prepare(exam)

    socket
    |> assign(:exam, exam)
    |> assign(:prepared, prepared)
    |> assign(:parts, prepared.parts)
    |> assign(:cells, %{})
    |> assign(:versions, %{})
    |> assign(:since, nil)
  end

  # `updated_at` has whole seconds only: a save in the same second as the last
  # read would not change it. Rows touched at or after the previous read's
  # second are therefore read once more.
  defp refresh(socket) do
    %{exam: exam, versions: versions, since: since, cells: cells, prepared: prepared} =
      socket.assigns

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    rows = Exams.list_progress_rows(exam)

    changed_ids =
      for row <- rows,
          Map.get(versions, row.id) != row.updated_at or
            (since != nil and DateTime.compare(row.updated_at, since) != :lt),
          do: row.id

    contents = Exams.list_submission_contents(exam, changed_ids)
    present = MapSet.new(rows, & &1.id)

    kept = Map.filter(cells, fn {{id, _part_id}, _status} -> MapSet.member?(present, id) end)

    cells =
      Enum.reduce(contents, kept, fn {id, content}, acc ->
        prepared
        |> Progress.statuses(content)
        |> Enum.reduce(acc, fn {part_id, status}, acc -> Map.put(acc, {id, part_id}, status) end)
      end)

    socket
    |> assign(:rows, rows)
    |> assign(:cells, cells)
    |> assign(:versions, Map.new(rows, &{&1.id, &1.updated_at}))
    |> assign(:since, now)
  end

  defp schedule_tick(socket) do
    if connected?(socket) and not socket.assigns.tick_scheduled? and
         socket.assigns.exam.status in @polling_statuses do
      Process.send_after(self(), :tick, @tick_ms)
      assign(socket, :tick_scheduled?, true)
    else
      socket
    end
  end

  defp started_count(cells, rows, part_id),
    do: Enum.count(rows, &(Map.get(cells, {&1.id, part_id}, :not_started) != :not_started))

  defp short_name(_row, index, true), do: "##{index + 1}"

  defp short_name(row, _index, false) do
    case String.trim(row.firstname || "") do
      "" -> participant_name(row)
      first -> first
    end
  end

  defp participant_title(_row, index, true), do: "Lernende #{index + 1}"
  defp participant_title(row, _index, false), do: participant_name(row)
end
