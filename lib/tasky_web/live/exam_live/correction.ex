defmodule TaskyWeb.ExamLive.Correction do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.AI.BulkCorrectionRunner

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-7xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Korrektur"}
            ]} />
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button navigate={~p"/exams/#{@exam}"} tooltip={"Zurück zu #{@exam.name}"} />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              Korrektur
            </h1>
          </div>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-8 pb-8">
        <%= if @parts != [] and @submissions != [] do %>
          <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-5 mb-4 flex items-center gap-6">
            <div class="flex-1 min-w-0">
              <div class="flex items-center justify-between mb-2">
                <span class="text-xs font-semibold text-stone-500 uppercase tracking-wide">
                  Fortschritt
                </span>
                <span class="text-sm font-semibold text-stone-700 tabular-nums">
                  {@summary.corrected} / {@summary.total} Teile erledigt
                </span>
              </div>
              <div class="h-2 bg-stone-100 rounded-full overflow-hidden">
                <div
                  class="h-full bg-green-500 transition-all duration-500"
                  style={"width: #{@summary.percent}%"}
                >
                </div>
              </div>
            </div>

            <div class="shrink-0">
              <%= cond do %>
                <% is_nil(@summary.first_uncorrected) -> %>
                  <span class="inline-flex items-center gap-2 text-sm font-semibold text-green-700">
                    <.icon name="hero-check-circle" class="w-5 h-5" /> Alle Teile korrigiert
                  </span>
                <% @summary.any_auto or @summary.manual_started -> %>
                  <% {sub, part} = @summary.first_uncorrected %>
                  <.link
                    navigate={~p"/exams/#{@exam}/correction/#{sub.id}/parts/#{part.id}"}
                    class="inline-flex items-center gap-2 text-sm font-semibold text-white bg-green-500 hover:bg-green-600 px-4 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(34,197,94,0.25)] transition-all duration-150 focus:outline-none focus:ring-4 focus:ring-green-600 focus:ring-offset-2"
                  >
                    <.icon name="hero-play" class="w-4 h-4" />
                    {if @summary.corrected == 0, do: "Korrektur starten", else: "Korrektur fortsetzen"}
                  </.link>
                <% true -> %>
                  <span class="text-xs text-stone-500">Starte unten mit der KI-Korrektur.</span>
              <% end %>
            </div>
          </div>
        <% end %>

        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <%= if @parts == [] do %>
            <div class="p-12 text-center text-stone-400">
              <.icon name="hero-document" class="w-10 h-10 mx-auto mb-3 text-stone-300" />
              <p class="text-sm font-medium">Kein Inhalt zum Korrigieren vorhanden.</p>
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-left border-collapse">
                <thead>
                  <%!-- AI Header Row: button (left) + info/progress card (right) --%>
                  <tr class="border-b border-stone-100 min-h-[120px]">
                    <th
                      colspan="2"
                      class="px-6 py-5 align-middle bg-white border-r border-stone-100"
                    >
                      <div
                        class="tooltip tooltip-bottom tooltip-delayed"
                        data-tip={
                          cond do
                            match?({:running, _}, @bulk_status) -> "Korrektur läuft bereits"
                            @any_auto_correct -> "Automatische Korrektur starten"
                            true -> "Bitte zuerst eine Aufgabe konfigurieren"
                          end
                        }
                      >
                        <button
                          type="button"
                          phx-click="run_auto_correction"
                          disabled={not @any_auto_correct or match?({:running, _}, @bulk_status)}
                          class={[
                            "inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg shadow-sm transition-all duration-150 normal-case tracking-normal",
                            cond do
                              match?({:running, _}, @bulk_status) ->
                                "text-white bg-gradient-to-r from-purple-300 to-fuchsia-300 opacity-60 cursor-not-allowed"

                              @any_auto_correct ->
                                "text-white bg-gradient-to-r from-purple-500 to-fuchsia-500 hover:from-purple-600 hover:to-fuchsia-600 hover:shadow-md cursor-pointer"

                              true ->
                                "text-stone-400 bg-stone-100 border border-stone-200 cursor-not-allowed"
                            end
                          ]}
                        >
                          <.icon name="hero-sparkles" class="w-4 h-4" /> KI-Korrektur starten
                        </button>
                      </div>
                    </th>
                    <th colspan={1 + length(@parts)} class="px-6 py-5 align-middle bg-white">
                      {render_ai_info(assigns)}
                    </th>
                  </tr>

                  <%!-- Column Labels Row --%>
                  <tr class="bg-stone-50 border-b border-stone-100">
                    <th
                      colspan="2"
                      class="px-6 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide bg-neutral-50 border-r border-stone-100"
                    >
                      KI-Konfiguration
                    </th>
                    <th class="px-4 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide">
                      Punkte
                    </th>
                    <th
                      :for={part <- @parts}
                      scope="col"
                      class="px-3 py-3 text-center text-xs font-semibold text-stone-500 uppercase tracking-wide min-w-[100px] max-w-[160px]"
                    >
                      <span
                        class="line-clamp-2 text-[12px] font-semibold text-stone-700 normal-case tooltip tooltip-bottom tooltip-delayed"
                        data-tip={part.label}
                      >
                        {part.label}
                      </span>
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-stone-100">
                  <%!-- AI Row: KI-Korrektur (auto_correct) --%>
                  <tr class="bg-neutral-50">
                    <td class="px-6 py-3 bg-neutral-50 border-r border-stone-100">
                      <div class="flex items-center gap-1.5">
                        <span class="text-sm font-medium text-stone-700">KI-Korrektur</span>
                        <div class="tooltip tooltip-right tooltip-delayed" data-tip="Info">
                          <button
                            type="button"
                            phx-click="show_info"
                            phx-value-topic="auto_correct"
                            class="inline-flex items-center justify-center w-5 h-5 rounded-full text-stone-400 hover:text-stone-600 hover:bg-stone-200 transition-colors duration-150 cursor-pointer"
                          >
                            <.icon name="hero-information-circle" class="w-4 h-4" />
                          </button>
                        </div>
                      </div>
                    </td>
                    <td class="px-4 py-3 bg-neutral-50 border-r border-stone-100">
                      <div class="tooltip tooltip-delayed" data-tip="Für alle Aufgaben aktivieren">
                        <label class="inline-flex items-center cursor-pointer">
                          <input
                            type="checkbox"
                            checked={all_checked?(@config, @parts, "auto_correct")}
                            phx-click="toggle_all_auto_correct"
                            class="w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150"
                          />
                        </label>
                      </div>
                    </td>
                    <td class="px-4 py-3"></td>
                    <td :for={part <- @parts} class="px-3 py-3 text-center">
                      <label class="inline-flex items-center justify-center cursor-pointer">
                        <input
                          type="checkbox"
                          checked={part_flag(@config, part.id, "auto_correct")}
                          phx-click="toggle_auto_correct"
                          phx-value-part-id={part.id}
                          class="w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150"
                        />
                      </label>
                    </td>
                  </tr>
                  <%!-- AI Row: Rechtschreibung ignorieren (ignore_spelling) --%>
                  <tr class="bg-neutral-50 border-b-2 border-stone-100">
                    <td class="px-6 py-3 bg-neutral-50 border-r border-stone-100">
                      <div class="flex items-center gap-1.5">
                        <span class="text-sm font-medium text-stone-700">
                          Rechtschreibung ignorieren
                        </span>
                        <div class="tooltip tooltip-right tooltip-delayed" data-tip="Info">
                          <button
                            type="button"
                            phx-click="show_info"
                            phx-value-topic="ignore_spelling"
                            class="inline-flex items-center justify-center w-5 h-5 rounded-full text-stone-400 hover:text-stone-600 hover:bg-stone-200 transition-colors duration-150 cursor-pointer"
                          >
                            <.icon name="hero-information-circle" class="w-4 h-4" />
                          </button>
                        </div>
                      </div>
                    </td>
                    <td class="px-4 py-3 bg-neutral-50 border-r border-stone-100">
                      <div class="tooltip tooltip-delayed" data-tip="Für alle Aufgaben aktivieren">
                        <label class={[
                          "inline-flex items-center",
                          if(any_auto_correct?(@config, @parts),
                            do: "cursor-pointer",
                            else: "cursor-not-allowed opacity-40"
                          )
                        ]}>
                          <input
                            type="checkbox"
                            checked={all_checked?(@config, @parts, "ignore_spelling")}
                            disabled={!any_auto_correct?(@config, @parts)}
                            phx-click="toggle_all_ignore_spelling"
                            class="w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 transition-colors duration-150 disabled:cursor-not-allowed"
                          />
                        </label>
                      </div>
                    </td>
                    <td class="px-4 py-3"></td>
                    <td :for={part <- @parts} class="px-3 py-3 text-center">
                      <label class={[
                        "inline-flex items-center justify-center",
                        if(part_flag(@config, part.id, "auto_correct"),
                          do: "cursor-pointer",
                          else: "cursor-not-allowed opacity-40"
                        )
                      ]}>
                        <input
                          type="checkbox"
                          checked={part_flag(@config, part.id, "ignore_spelling")}
                          disabled={!part_flag(@config, part.id, "auto_correct")}
                          phx-click="toggle_ignore_spelling"
                          phx-value-part-id={part.id}
                          class="w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 transition-colors duration-150 disabled:cursor-not-allowed"
                        />
                      </label>
                    </td>
                  </tr>

                  <%!-- Submission Rows --%>
                  <tr :for={submission <- @submissions} class="group hover:bg-stone-50/50">
                    <td colspan="2" class="px-6 py-3">
                      <div class="flex items-center gap-3">
                        <div class="w-9 h-9 rounded-full bg-gradient-to-br from-blue-400 to-indigo-500 flex items-center justify-center text-white text-sm font-bold shadow-sm shrink-0">
                          {String.first(submission.firstname)}{String.first(submission.lastname)}
                        </div>
                        <div class="min-w-0">
                          <p class="text-sm font-semibold text-stone-800 truncate">
                            {submission.firstname} {submission.lastname}
                          </p>
                          <p class="text-xs text-stone-400 mt-0.5">
                            <%= if submission.submitted do %>
                              <span class="text-purple-500 font-medium">Abgegeben</span>
                            <% else %>
                              <span class="text-stone-400">Nicht abgegeben</span>
                            <% end %>
                          </p>
                        </div>
                      </div>
                    </td>
                    <td class="px-4 py-3">
                      <span class="font-mono text-sm font-semibold text-stone-700">
                        {format_points(total_points(submission))}
                        <span class="text-stone-400 font-normal">
                          / {format_points(@total_max_points)}
                        </span>
                      </span>
                    </td>
                    <td :for={part <- @parts} class="px-3 py-3">
                      <div class="flex items-center justify-center gap-2">
                        <div
                          class="w-9 h-9 flex items-center justify-center shrink-0 tooltip tooltip-delayed"
                          data-tip={"#{part.label} ansehen"}
                        >
                          <.link
                            navigate={~p"/exams/#{@exam}/correction/#{submission.id}/parts/#{part.id}"}
                            class="inline-flex items-center justify-center w-9 h-9 rounded-lg text-stone-500 border border-stone-200 opacity-0 group-hover:opacity-100 focus:opacity-100 transition-all duration-150 hover:bg-stone-100 hover:text-stone-700 hover:border-stone-300"
                          >
                            <.icon name="hero-eye" class="w-4 h-4" />
                          </.link>
                        </div>
                        <div class="w-9 h-9 flex items-center justify-center shrink-0">
                          <%= if part.id in (submission.auto_corrected_parts || []) do %>
                            <div
                              class="tooltip tooltip-delayed"
                              data-tip="Automatisch durch KI korrigiert"
                            >
                              <span class="inline-flex items-center justify-center w-7 h-7 rounded-full bg-purple-50 text-purple-500">
                                <.icon name="hero-sparkles" class="w-5 h-5" />
                              </span>
                            </div>
                          <% end %>
                        </div>
                        <div class="w-9 h-9 flex items-center justify-center shrink-0">
                          <%= if part.id in submission.corrected_parts do %>
                            <div class="tooltip tooltip-delayed" data-tip="Als erledigt markiert">
                              <span class="inline-flex items-center justify-center w-7 h-7 rounded-full bg-green-50 text-green-600">
                                <.icon name="hero-check-badge" class="w-5 h-5" />
                              </span>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Info Modal --%>
      <%= if @show_info_modal do %>
        <dialog
          id="info-modal"
          class="modal modal-open"
          phx-window-keydown="close_info_modal"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_info_modal"></div>
          <div class="modal-box max-w-lg p-0 bg-white rounded-[16px] shadow-2xl">
            <div class="px-6 py-5 border-b border-stone-100 flex items-center justify-between">
              <div class="flex items-center gap-3">
                <div class="w-9 h-9 rounded-xl bg-gradient-to-br from-amber-400 to-orange-500 flex items-center justify-center text-white shadow-sm">
                  <.icon name={info_modal_icon(@show_info_modal)} class="w-5 h-5" />
                </div>
                <h3 class="text-lg font-semibold text-stone-900">
                  {info_modal_title(@show_info_modal)}
                </h3>
              </div>
              <button
                type="button"
                phx-click="close_info_modal"
                class="inline-flex items-center justify-center w-8 h-8 rounded-lg text-stone-400 hover:text-stone-600 hover:bg-stone-100 transition-colors duration-150 cursor-pointer"
              >
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>
            <div class="px-6 py-5">
              <div class="text-sm text-stone-600 leading-relaxed space-y-3">
                {info_modal_content(assigns)}
              </div>
            </div>
            <div class="px-6 py-4 border-t border-stone-100 flex justify-end">
              <button
                type="button"
                phx-click="close_info_modal"
                class="px-4 py-2 text-sm font-medium text-stone-600 bg-stone-100 rounded-lg hover:bg-stone-200 transition-colors duration-150 cursor-pointer"
              >
                Verstanden
              </button>
            </div>
          </div>
        </dialog>
      <% end %>
    </Layouts.app>
    """
  end

  # Private helper component that renders the AI correction status/info area.
  # We branch on `assigns.bulk_status` and `assigns.any_auto_correct` directly
  # (rather than via `@` syntax) because this is a plain private function, not a
  # top-level `render/1`. Local assigns like `@done`/`@total` are injected via
  # `Phoenix.Component.assign/3` so the inner HEEx can reference them.
  defp render_ai_info(assigns) do
    case assigns.bulk_status do
      {:running, %{done: done, total: total}} ->
        assigns = assign(assigns, done: done, total: total)

        ~H"""
        <div class="rounded-xl bg-gradient-to-r from-amber-50/60 via-orange-50/50 to-amber-50/60 border border-stone-100 px-5 py-4">
          <div class="flex items-center justify-between gap-4">
            <div class="flex items-center gap-3 min-w-0">
              <span class="relative flex h-2.5 w-2.5 shrink-0">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75">
                </span>
                <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-amber-500"></span>
              </span>
              <div class="min-w-0">
                <p class="text-sm font-medium text-stone-700 animate-pulse normal-case tracking-normal">
                  Am korrigieren...
                </p>
                <p class="text-xs font-normal text-stone-500 mt-0.5 tabular-nums normal-case tracking-normal">
                  <span class="font-semibold text-stone-700">{@done}</span>
                  von <span class="font-semibold text-stone-700">{@total}</span>
                  Aufgaben verarbeitet
                </p>
              </div>
            </div>
            <button
              type="button"
              phx-click="cancel_auto_correction"
              class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-red-600 bg-white border border-red-200 rounded-lg transition-all duration-150 hover:bg-red-50 hover:border-red-300 cursor-pointer shrink-0 normal-case tracking-normal"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" /> Abbrechen
            </button>
          </div>
          <div class="mt-3 h-1.5 w-full bg-white/60 rounded-full overflow-hidden">
            <div
              class="h-full bg-gradient-to-r from-amber-400 to-orange-500 transition-all duration-500 ease-out"
              style={"width: #{progress_percent(@done, @total)}%"}
            >
            </div>
          </div>
        </div>
        """

      _ ->
        if assigns.any_auto_correct do
          ~H"""
          <p class="text-sm font-normal text-stone-500 normal-case tracking-normal leading-relaxed">
            Klicken Sie auf „KI-Korrektur starten", um die automatische Bewertung zu beginnen.
          </p>
          """
        else
          ~H"""
          <p class="text-sm font-normal text-stone-500 normal-case tracking-normal leading-relaxed">
            Aktivieren Sie die KI-Korrektur für mindestens einen Prüfungs-Teil, um die KI-Korrektur starten zu können.
          </p>
          """
        end
    end
  end

  defp info_modal_content(assigns) do
    case assigns.show_info_modal do
      "auto_correct" ->
        ~H"""
        <p>
          Wenn aktiviert, wird diese Aufgabe automatisch durch KI korrigiert.
          Die KI analysiert die Antworten der Teilnehmer und vergleicht sie mit der Musterlösung.
        </p>
        <p>
          Die automatische Korrektur liefert Punktvorschläge und Feedback,
          die Sie anschliessend überprüfen und bei Bedarf anpassen können.
        </p>
        """

      "ignore_spelling" ->
        ~H"""
        <p>
          Wenn aktiviert, werden Rechtschreibfehler bei der automatischen Korrektur
          dieser Aufgabe nicht berücksichtigt.
        </p>
        <p>
          Geeignet für Fächer wie Geschichte oder Geografie, bei denen der Inhalt wichtiger ist als die exakte Schreibweise.
        </p>
        """

      _ ->
        ~H""
    end
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    if connected?(socket) do
      Exams.subscribe_correction(exam.id)
    end

    parts = Exams.split_content_into_parts(exam.content || %{})
    config = exam.ai_correction_config || %{}
    submissions = load_sorted_submissions(exam)

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Korrektur")
     |> assign(:exam, exam)
     |> assign(:parts, parts)
     |> assign(:config, config)
     |> assign(:submissions, submissions)
     |> assign(:summary, correction_summary(parts, submissions))
     |> assign(:any_auto_correct, any_auto_correct?(config, parts))
     |> assign(:bulk_status, :idle)
     |> assign(:bulk_runner_pid, nil)
     |> assign(:total_max_points, total_max_points(exam))
     |> assign(:show_info_modal, nil)}
  end

  @impl true
  def handle_event("run_auto_correction", _params, socket) do
    cond do
      not socket.assigns.any_auto_correct ->
        {:noreply, socket}

      match?({:running, _}, socket.assigns.bulk_status) ->
        {:noreply, socket}

      true ->
        case BulkCorrectionRunner.start(socket.assigns.exam, socket.assigns.current_scope) do
          {:ok, pid} ->
            exam = socket.assigns.exam
            total = length(Exams.list_bulk_correction_jobs(exam))
            skipped = Exams.count_skipped_correction_jobs(exam)

            socket =
              socket
              |> assign(:bulk_runner_pid, pid)
              |> assign(:bulk_status, {:running, %{done: 0, total: total}})
              |> assign(:bulk_skipped, skipped)

            socket =
              if skipped > 0 do
                put_flash(
                  socket,
                  :info,
                  "#{skipped} bereits als erledigt markierte Aufgaben werden übersprungen."
                )
              else
                socket
              end

            {:noreply, socket}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Konnte nicht gestartet werden: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("cancel_auto_correction", _params, socket) do
    case socket.assigns.bulk_runner_pid do
      pid when is_pid(pid) -> BulkCorrectionRunner.cancel(pid)
      _ -> :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_auto_correct", %{"part-id" => part_id}, socket) do
    {:noreply, toggle_part_flag(socket, part_id, "auto_correct")}
  end

  @impl true
  def handle_event("toggle_ignore_spelling", %{"part-id" => part_id}, socket) do
    {:noreply, toggle_part_flag(socket, part_id, "ignore_spelling")}
  end

  @impl true
  def handle_event("toggle_all_auto_correct", _params, socket) do
    {:noreply, toggle_all_flag(socket, "auto_correct")}
  end

  @impl true
  def handle_event("toggle_all_ignore_spelling", _params, socket) do
    {:noreply, toggle_all_flag(socket, "ignore_spelling")}
  end

  @impl true
  def handle_event("show_info", %{"topic" => topic}, socket) do
    {:noreply, assign(socket, :show_info_modal, topic)}
  end

  @impl true
  def handle_event("close_info_modal", _params, socket) do
    {:noreply, assign(socket, :show_info_modal, nil)}
  end

  @impl true
  def handle_info({:submission_corrected_parts_changed, submission}, socket) do
    submissions =
      Enum.map(socket.assigns.submissions, fn s ->
        if s.id == submission.id, do: submission, else: s
      end)

    {:noreply,
     socket
     |> assign(:submissions, submissions)
     |> assign(:summary, correction_summary(socket.assigns.parts, submissions))}
  end

  def handle_info({:bulk_correction_progress, %{done: done, total: total}}, socket) do
    {:noreply, assign(socket, :bulk_status, {:running, %{done: done, total: total}})}
  end

  def handle_info({:bulk_correction_done, %{total: total, errors: errors}}, socket) do
    skipped = Map.get(socket.assigns, :bulk_skipped, 0)
    submissions = load_sorted_submissions(socket.assigns.exam)

    socket =
      socket
      |> assign(:bulk_status, :idle)
      |> assign(:bulk_runner_pid, nil)
      |> assign(:bulk_skipped, 0)
      |> assign(:submissions, submissions)
      |> assign(:summary, correction_summary(socket.assigns.parts, submissions))

    skipped_note =
      if skipped > 0,
        do: " #{skipped} übersprungen (bereits als erledigt markiert).",
        else: ""

    msg =
      case errors do
        [] ->
          "Automatische Korrektur abgeschlossen (#{total}).#{skipped_note}"

        _ ->
          "Korrektur abgeschlossen: #{total - length(errors)}/#{total} ok, #{length(errors)} fehlgeschlagen.#{skipped_note}"
      end

    {:noreply, put_flash(socket, :info, msg)}
  end

  def handle_info({:bulk_correction_cancelled, %{done: done, total: total}}, socket) do
    skipped = Map.get(socket.assigns, :bulk_skipped, 0)
    submissions = load_sorted_submissions(socket.assigns.exam)

    skipped_note =
      if skipped > 0,
        do: " #{skipped} übersprungen (bereits als erledigt markiert).",
        else: ""

    {:noreply,
     socket
     |> assign(:bulk_status, :idle)
     |> assign(:bulk_runner_pid, nil)
     |> assign(:bulk_skipped, 0)
     |> assign(:submissions, submissions)
     |> assign(:summary, correction_summary(socket.assigns.parts, submissions))
     |> put_flash(:info, "Korrektur abgebrochen (#{done}/#{total} verarbeitet).#{skipped_note}")}
  end

  defp toggle_part_flag(socket, part_id, key) do
    config = socket.assigns.config
    current_val = part_flag(config, part_id, key)
    new_val = !current_val

    part_config = Map.get(config, part_id, %{})
    updated_part_config = Map.put(part_config, key, new_val)

    updated_part_config =
      if key == "auto_correct" and new_val == false do
        Map.put(updated_part_config, "ignore_spelling", false)
      else
        updated_part_config
      end

    {:ok, updated_exam} =
      Exams.update_ai_correction_config(socket.assigns.exam, part_id, updated_part_config)

    new_config = updated_exam.ai_correction_config || %{}

    socket
    |> assign(:exam, updated_exam)
    |> assign(:config, new_config)
    |> assign(:any_auto_correct, any_auto_correct?(new_config, socket.assigns.parts))
  end

  defp toggle_all_flag(socket, key) do
    config = socket.assigns.config
    parts = socket.assigns.parts
    new_val = !all_checked?(config, parts, key)

    updates =
      Map.new(parts, fn part ->
        part_config = Map.get(config, part.id, %{})
        updated = Map.put(part_config, key, new_val)

        updated =
          if key == "auto_correct" and new_val == false do
            Map.put(updated, "ignore_spelling", false)
          else
            updated
          end

        {part.id, updated}
      end)

    {:ok, updated_exam} =
      Exams.update_ai_correction_config_bulk(socket.assigns.exam, updates)

    new_config = updated_exam.ai_correction_config || %{}

    socket
    |> assign(:exam, updated_exam)
    |> assign(:config, new_config)
    |> assign(:any_auto_correct, any_auto_correct?(new_config, parts))
  end

  defp part_flag(config, part_id, key) do
    config
    |> Map.get(part_id, %{})
    |> Map.get(key, false)
  end

  defp all_checked?(config, parts, key) do
    parts != [] and Enum.all?(parts, fn part -> part_flag(config, part.id, key) end)
  end

  defp any_auto_correct?(config, parts) do
    Enum.any?(parts, fn part -> part_flag(config, part.id, "auto_correct") end)
  end

  defp info_modal_icon("auto_correct"), do: "hero-sparkles"
  defp info_modal_icon("ignore_spelling"), do: "hero-language"
  defp info_modal_icon(_), do: "hero-information-circle"

  defp info_modal_title("auto_correct"), do: "Automatisch korrigieren"
  defp info_modal_title("ignore_spelling"), do: "Rechtschreibung ignorieren"
  defp info_modal_title(_), do: "Information"

  defp total_points(submission) do
    (submission.points_per_part || %{})
    |> Map.values()
    |> Enum.reduce(0, fn
      v, acc when is_number(v) -> acc + v
      _, acc -> acc
    end)
  end

  defp total_max_points(exam) do
    (exam.sample_solution_points || %{})
    |> Map.values()
    |> Enum.reduce(0, fn
      v, acc when is_number(v) -> acc + v
      _, acc -> acc
    end)
  end

  defp progress_percent(_done, 0), do: 0
  defp progress_percent(done, total), do: round(done * 100 / total)

  defp format_points(0), do: "—"
  defp format_points(n) when is_integer(n), do: Integer.to_string(n)

  defp format_points(n) when is_float(n) do
    if n == trunc(n),
      do: Integer.to_string(trunc(n)),
      else: :erlang.float_to_binary(n, decimals: 1)
  end

  defp correction_summary(parts, submissions) do
    total = length(parts) * length(submissions)

    corrected =
      Enum.reduce(submissions, 0, fn s, acc ->
        done = MapSet.new(s.corrected_parts || [])
        acc + Enum.count(parts, fn p -> p.id in done end)
      end)

    any_auto = Enum.any?(submissions, fn s -> (s.auto_corrected_parts || []) != [] end)
    manual_started = Enum.any?(submissions, fn s -> (s.corrected_parts || []) != [] end)
    first_uncorrected = find_first_uncorrected(parts, submissions)
    percent = if total == 0, do: 0, else: round(corrected * 100 / total)

    %{
      total: total,
      corrected: corrected,
      percent: percent,
      any_auto: any_auto,
      manual_started: manual_started,
      first_uncorrected: first_uncorrected
    }
  end

  defp find_first_uncorrected(parts, submissions) do
    Enum.find_value(parts, fn part ->
      sub = Enum.find(submissions, fn s -> part.id not in (s.corrected_parts || []) end)
      if sub, do: {sub, part}, else: nil
    end)
  end

  defp load_sorted_submissions(exam) do
    exam
    |> Exams.list_exam_submissions()
    |> Enum.sort_by(fn s ->
      {String.downcase(s.firstname || ""), String.downcase(s.lastname || "")}
    end)
  end
end
