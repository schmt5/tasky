defmodule TaskyWeb.ExamLive.CorrectionPart do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.Repo
  alias Tasky.Exams.ExamSubmission

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <div class="bg-white min-h-screen">
        <%!-- Compact Header --%>
        <div class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 py-3">
          <div class="max-w-7xl mx-auto flex items-center justify-between gap-4">
            <div class="flex items-center gap-2 min-w-0">
              <.back_button
                navigate={~p"/exams/#{@exam}/correction"}
                tooltip="Zurück zur Korrektur"
                size="sm"
              />
              <.breadcrumbs crumbs={[
                %{label: "Prüfungen", navigate: ~p"/exams"},
                %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
                %{label: "Korrektur", navigate: ~p"/exams/#{@exam}/correction"},
                %{label: "#{@submission.firstname} #{@submission.lastname} – #{@current_part.label}"}
              ]} />
            </div>

            <div class="flex items-center gap-3 shrink-0">
              <div class="inline-flex items-center gap-2 bg-sky-50 border border-sky-200 rounded-lg pl-2.5 pr-1.5 py-1">
                <.icon name="hero-user" class="w-4 h-4 text-sky-700" />
                <span class="text-xs font-semibold text-sky-700 uppercase tracking-wide">
                  Teilnehmer:in
                </span>
                <span class="text-xs font-mono font-semibold text-sky-700">
                  {(@current_submission_index || 0) + 1}/{@total_submissions}
                </span>
                <div class="flex items-center gap-1 ml-1">
                  <.nav_chevron
                    direction="up"
                    target={@prev_submission_path}
                    title="Vorheriger Teilnehmer"
                  />
                  <.nav_chevron
                    direction="down"
                    target={@next_submission_path}
                    title="Nächster Teilnehmer"
                  />
                </div>
              </div>

              <div class="inline-flex items-center gap-2 bg-sky-50 border border-sky-200 rounded-lg pl-2.5 pr-1.5 py-1">
                <.icon name="hero-document-text" class="w-4 h-4 text-sky-700" />
                <span class="text-xs font-semibold text-sky-700 uppercase tracking-wide">Teil</span>
                <span class="text-xs font-mono font-semibold text-sky-700">
                  {(@current_part_index || 0) + 1}/{@total_parts}
                </span>
                <div class="flex items-center gap-1 ml-1">
                  <.nav_chevron direction="left" target={@prev_part_path} title="Vorheriger Teil" />
                  <.nav_chevron direction="right" target={@next_part_path} title="Nächster Teil" />
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="max-w-7xl mx-auto px-8 py-6">
          <div class="grid grid-cols-4 gap-6 items-start">
            <%!-- Editor (3/4) --%>
            <div class="col-span-3 min-w-0">
              <div
                id={"correction-part-editor-#{@submission.id}-#{@current_part.id}"}
                phx-hook="ExamCorrectionEditor"
                phx-update="ignore"
                data-exam-id={@exam.id}
                data-submission-id={@submission.id}
                data-part-id={@current_part.id}
                data-content={@part_doc_json}
              >
              </div>
            </div>

            <%!-- Sidebar (1/4, sticky) --%>
            <aside class="col-span-1 sticky top-[72px]">
              <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
                <div class="p-5 border-b border-stone-100">
                  <h2 class="text-base font-semibold text-stone-800 truncate">
                    {@current_part.label}
                  </h2>
                  <p class="text-sm font-semibold text-stone-700 mt-1">
                    {@submission.firstname} {@submission.lastname}
                  </p>
                  <%= if @current_part.id in (@submission.auto_corrected_parts || []) do %>
                    <div class="mt-2 inline-flex items-center gap-1.5">
                      <span class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-purple-50 text-purple-500 shrink-0">
                        <.icon name="hero-sparkles" class="w-3.5 h-3.5" />
                      </span>
                      <span class="text-xs font-medium text-purple-600">Automatisch korrigiert</span>
                    </div>
                  <% end %>
                </div>

                <div class="p-5 border-b border-stone-100">
                  <form phx-change="set_points" phx-submit="set_points">
                    <div class="flex items-center justify-between mb-2">
                      <label
                        for="part-points-input"
                        class="block text-xs font-semibold text-stone-500 uppercase tracking-wide"
                      >
                        Punkte
                      </label>
                      <%= if @max_points do %>
                        <span class="text-xs text-stone-400">
                          max {format_points(@max_points)}
                        </span>
                      <% end %>
                    </div>
                    <input
                      id="part-points-input"
                      type="number"
                      name="points"
                      value={@points || ""}
                      step="0.5"
                      inputmode="decimal"
                      phx-debounce="500"
                      placeholder="—"
                      class="w-full font-mono text-base text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-4 focus:ring-sky-600 focus:ring-offset-2"
                    />
                  </form>
                  <div class="flex items-center gap-2 mt-3">
                    <div
                      class="flex-1 tooltip tooltip-delayed"
                      data-tip={
                        if is_nil(@max_points),
                          do: "Keine Maximalpunkte in der Musterlösung gesetzt",
                          else: "Maximale Punkte vergeben"
                      }
                    >
                      <button
                        type="button"
                        phx-click="set_points_max"
                        disabled={is_nil(@max_points)}
                        class="w-full inline-flex items-center justify-center gap-1.5 text-xs font-semibold px-3 py-2 rounded-lg transition-all duration-150 active:scale-[0.98] text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent disabled:hover:border-stone-200"
                      >
                        <.icon name="hero-check" class="w-3.5 h-3.5" /> Max
                      </button>
                    </div>
                    <button
                      type="button"
                      phx-click="set_points_zero"
                      class="flex-1 inline-flex items-center justify-center gap-1.5 text-xs font-semibold px-3 py-2 rounded-lg transition-all duration-150 active:scale-[0.98] text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300"
                    >
                      <.icon name="hero-x-mark" class="w-3.5 h-3.5" /> 0
                    </button>
                  </div>
                </div>

                <div class="p-5 space-y-3">
                  <button
                    type="button"
                    phx-click="show_sample_solution_modal"
                    class="w-full inline-flex items-center justify-center gap-2 text-sm font-semibold px-4 py-2.5 rounded-lg transition-all duration-150 active:scale-[0.98] text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300"
                  >
                    <.icon name="hero-light-bulb" class="w-4 h-4" /> Musterlösung anzeigen
                  </button>

                  <%= if @power_blocks_count > 0 do %>
                    <button
                      type="button"
                      phx-click="open_power_view"
                      class="w-full inline-flex items-center justify-center gap-2 text-sm font-semibold px-4 py-2.5 rounded-lg transition-all duration-150 active:scale-[0.98] bg-sky-50 text-sky-700 border border-sky-200 hover:bg-sky-100 hover:border-sky-300"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4" /> Power-Ansicht
                    </button>
                  <% end %>

                  <div class="w-full flex items-center gap-2.5">
                    <.icon
                      name="hero-check-badge"
                      class={[
                        "w-6 h-6 shrink-0 transition-all duration-300 ease-out",
                        if(@is_corrected,
                          do: "text-green-600 scale-110",
                          else: "text-stone-300"
                        )
                      ]}
                    />
                    <button
                      type="button"
                      phx-click="toggle_corrected"
                      aria-pressed={@is_corrected}
                      class={[
                        "flex-1 inline-flex items-center justify-center text-sm font-semibold px-4 py-2.5 rounded-lg border transition-all duration-200 active:scale-[0.98] focus:outline-none focus-visible:ring-4 focus-visible:ring-sky-600 focus-visible:ring-offset-2",
                        if(@is_corrected,
                          do:
                            "bg-stone-100 border-stone-300 text-stone-600 hover:bg-stone-200 hover:border-stone-400",
                          else:
                            "bg-green-50 border-green-500 text-green-700 hover:bg-green-100 hover:border-green-600"
                        )
                      ]}
                    >
                      {if @is_corrected, do: "Erledigt zurück nehmen", else: "Als erledigt markieren"}
                    </button>
                  </div>
                </div>
              </div>
            </aside>
          </div>
        </div>

        <%= if @show_power_view do %>
          <dialog
            id="power-view-modal"
            class="modal modal-open"
            phx-window-keydown="close_power_view"
            phx-key="escape"
          >
            <div class="modal-backdrop bg-stone-900/50" phx-click="close_power_view"></div>
            <div
              id="power-view-container"
              phx-hook="PowerView"
              class="modal-box max-w-3xl w-[min(720px,92vw)] p-0 bg-white rounded-[16px] shadow-2xl flex flex-col max-h-[92vh] h-[92vh]"
            >
              <div class="px-6 pt-5 pb-4 border-b border-stone-100 flex items-start gap-4">
                <div class="w-10 h-10 rounded-[10px] bg-sky-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-bolt" class="w-5 h-5 text-sky-500" />
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-lg font-semibold text-stone-900 truncate">
                    Power-Ansicht – {@current_part.label}
                  </h3>
                  <p class="text-sm text-stone-500 mt-1">
                    {@submission.firstname} {@submission.lastname}
                    <%= if @max_points do %>
                      · Max. Punkte:
                      <span class="font-semibold text-stone-700">{format_points(@max_points)}</span>
                      · {format_points(@power_per_block)} pro Block
                    <% end %>
                  </p>
                </div>
                <div class="tooltip tooltip-left tooltip-delayed" data-tip="Schliessen (Esc)">
                  <button
                    type="button"
                    phx-click="close_power_view"
                    class="text-stone-400 hover:text-stone-700 transition-colors duration-150"
                  >
                    <.icon name="hero-x-mark" class="w-5 h-5" />
                  </button>
                </div>
              </div>

              <div class="px-6 py-4 border-b border-stone-100 flex items-center gap-4 text-xs text-stone-500">
                <span class="font-semibold uppercase tracking-wide">Tastatur</span>
                <span class="inline-flex items-center gap-1">
                  <kbd class="px-1.5 py-0.5 bg-stone-100 border border-stone-200 rounded text-stone-700 font-mono text-[10px]">
                    J
                  </kbd>
                  Richtig
                </span>
                <span class="inline-flex items-center gap-1">
                  <kbd class="px-1.5 py-0.5 bg-stone-100 border border-stone-200 rounded text-stone-700 font-mono text-[10px]">
                    K
                  </kbd>
                  Halb-richtig
                </span>
                <span class="inline-flex items-center gap-1">
                  <kbd class="px-1.5 py-0.5 bg-stone-100 border border-stone-200 rounded text-stone-700 font-mono text-[10px]">
                    L
                  </kbd>
                  Falsch
                </span>
                <span class="inline-flex items-center gap-1">
                  <kbd class="px-1.5 py-0.5 bg-stone-100 border border-stone-200 rounded text-stone-700 font-mono text-[10px]">
                    Tab
                  </kbd>
                  Nächster Block
                </span>
                <span class="inline-flex items-center gap-1">
                  <kbd class="px-1.5 py-0.5 bg-stone-100 border border-stone-200 rounded text-stone-700 font-mono text-[10px]">
                    Leertaste
                  </kbd>
                  Erledigt / Weiter
                </span>
              </div>

              <div class="px-6 py-5 overflow-y-auto flex-1 space-y-2">
                <%= for block <- @power_blocks do %>
                  <div
                    tabindex="0"
                    data-power-row={block.index}
                    class="grid grid-cols-[64px_1fr_auto] items-center gap-4 px-4 py-3 rounded-xl border border-stone-200 bg-white outline-none focus:ring-4 focus:ring-sky-600 focus:ring-offset-2 focus:bg-sky-50/30 transition-all duration-100"
                  >
                    <div class="text-center">
                      <span class={[
                        "inline-flex items-center justify-center min-w-[36px] h-8 px-2 rounded-lg font-mono text-base font-semibold",
                        power_points_class(block.verdict)
                      ]}>
                        {power_row_points(block.verdict, @power_per_block)}
                      </span>
                    </div>

                    <div class="min-w-0">
                      <%= if block.text == "" do %>
                        <span class="text-sm italic text-stone-400">— leer —</span>
                      <% else %>
                        <span class="text-base text-stone-800 break-words">{block.text}</span>
                      <% end %>
                    </div>

                    <div class="flex items-center gap-1.5">
                      <.power_verdict_button
                        verdict="correct"
                        active={block.verdict == "correct"}
                        index={block.index}
                        label="J"
                        icon="hero-check"
                        active_class="bg-green-500 text-white border-green-500 shadow-[0_2px_8px_rgba(34,197,94,0.25)]"
                      />
                      <.power_verdict_button
                        verdict="half"
                        active={block.verdict == "half"}
                        index={block.index}
                        label="K"
                        icon="hero-minus"
                        active_class="bg-yellow-400 text-white border-yellow-400 shadow-[0_2px_8px_rgba(250,204,21,0.3)]"
                      />
                      <.power_verdict_button
                        verdict="wrong"
                        active={block.verdict == "wrong"}
                        index={block.index}
                        label="L"
                        icon="hero-x-mark"
                        active_class="bg-red-500 text-white border-red-500 shadow-[0_2px_8px_rgba(239,68,68,0.25)]"
                      />
                    </div>
                  </div>
                <% end %>

                <div class="w-full flex items-center gap-2.5">
                  <.icon
                    name="hero-check-badge"
                    class={[
                      "w-6 h-6 shrink-0 transition-all duration-300 ease-out",
                      if(@is_corrected,
                        do: "text-green-600 scale-110",
                        else: "text-stone-300"
                      )
                    ]}
                  />
                  <button
                    type="button"
                    data-power-toggle-corrected
                    phx-click="toggle_corrected"
                    aria-pressed={@is_corrected}
                    class={[
                      "flex-1 inline-flex items-center justify-center gap-3 text-sm font-semibold px-4 py-2.5 rounded-lg border transition-all duration-200 active:scale-[0.98] focus:outline-none focus-visible:ring-4 focus-visible:ring-sky-600 focus-visible:ring-offset-2",
                      if(@is_corrected,
                        do:
                          "bg-stone-100 border-stone-300 text-stone-600 hover:bg-stone-200 hover:border-stone-400",
                        else:
                          "bg-green-50 border-green-500 text-green-700 hover:bg-green-100 hover:border-green-600"
                      )
                    ]}
                  >
                    {if @is_corrected, do: "Erledigt zurück nehmen", else: "Als erledigt markieren"}
                    <kbd class="px-1.5 py-0.5 bg-white/60 border border-stone-200 rounded text-stone-500 font-mono text-[10px]">
                      Leertaste
                    </kbd>
                  </button>
                </div>
              </div>

              <div class="px-6 py-4 border-t border-stone-100 flex items-center justify-between gap-4">
                <div class="text-sm text-stone-500">
                  <span class="font-semibold text-stone-700">
                    {format_points(@power_current_total)}
                  </span>
                  <%= if @max_points do %>
                    / {format_points(@max_points)} Punkte
                  <% end %>
                </div>

                <div class="flex items-center gap-2">
                  <button
                    type="button"
                    data-power-next-submission
                    phx-click="goto_next_submission_power"
                    disabled={is_nil(@next_submission_path)}
                    class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-4 py-2 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 focus:outline-none focus:ring-4 focus:ring-sky-600 focus:ring-offset-2 disabled:opacity-40 disabled:cursor-not-allowed disabled:shadow-none"
                  >
                    Zum nächsten Teilnehmenden
                    <kbd class="ml-1 px-1.5 py-0.5 bg-white/20 border border-white/30 rounded text-white/80 font-mono text-[10px]">
                      Leertaste
                    </kbd>
                    <.icon name="hero-arrow-right" class="w-4 h-4" />
                  </button>
                  <button
                    type="button"
                    phx-click="close_power_view"
                    class="inline-flex items-center gap-2 text-stone-700 text-sm font-semibold px-4 py-2 rounded-lg border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300"
                  >
                    Schliessen
                  </button>
                </div>
              </div>
            </div>
          </dialog>
        <% end %>

        <%= if @show_sample_solution_modal do %>
          <dialog
            id="sample-solution-preview-modal"
            class="modal modal-open"
            phx-window-keydown="close_sample_solution_modal"
            phx-key="escape"
          >
            <div class="modal-backdrop bg-stone-900/50" phx-click="close_sample_solution_modal"></div>
            <div class="modal-box max-w-6xl w-[90vw] p-0 bg-white rounded-[16px] shadow-2xl flex flex-col max-h-[90vh]">
              <div class="px-6 pt-6 pb-4 border-b border-stone-100 flex items-start gap-4">
                <div class="w-10 h-10 rounded-[10px] bg-sky-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-light-bulb" class="w-5 h-5 text-sky-500" />
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-lg font-semibold text-stone-900 truncate">
                    Musterlösung – {@current_part.label}
                  </h3>
                  <%= if @max_points do %>
                    <p class="text-sm text-stone-500 mt-1">
                      Max. Punkte:
                      <span class="font-semibold text-stone-700">{format_points(@max_points)}</span>
                    </p>
                  <% end %>
                </div>
                <div class="tooltip tooltip-left tooltip-delayed" data-tip="Schliessen">
                  <button
                    type="button"
                    phx-click="close_sample_solution_modal"
                    class="text-stone-400 hover:text-stone-700 transition-colors duration-150"
                  >
                    <.icon name="hero-x-mark" class="w-5 h-5" />
                  </button>
                </div>
              </div>
              <div class="p-6 overflow-y-auto flex-1">
                <%= if @sample_solution_json do %>
                  <div
                    id={"sample-solution-viewer-#{@current_part.id}"}
                    phx-hook="ExamReadOnlyViewer"
                    phx-update="ignore"
                    data-content={@sample_solution_json}
                  >
                  </div>
                <% else %>
                  <p class="text-sm text-stone-400 italic">
                    Keine Musterlösung für diesen Teil vorhanden.
                  </p>
                <% end %>
              </div>
              <div class="px-6 pb-6 pt-3 flex items-center justify-end border-t border-stone-100">
                <button
                  type="button"
                  phx-click="close_sample_solution_modal"
                  class="inline-flex items-center gap-2 text-stone-700 text-sm font-semibold px-4 py-2 rounded-[8px] border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300"
                >
                  Schliessen
                </button>
              </div>
            </div>
          </dialog>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :verdict, :string, required: true
  attr :active, :boolean, required: true
  attr :index, :integer, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :active_class, :string, required: true

  defp power_verdict_button(assigns) do
    ~H"""
    <button
      type="button"
      tabindex="-1"
      phx-click="set_block_verdict"
      phx-value-index={@index}
      phx-value-verdict={@verdict}
      class={[
        "inline-flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1.5 rounded-lg border transition-all duration-100 focus:outline-none",
        if(@active,
          do: @active_class,
          else: "bg-white text-stone-500 border-stone-200 hover:bg-stone-50 hover:border-stone-300"
        )
      ]}
    >
      <.icon name={@icon} class="w-3.5 h-3.5" />
      <kbd class={[
        "px-1.5 py-0.5 rounded font-mono text-[10px] border",
        if(@active,
          do: "bg-white/25 border-white/40 text-white",
          else: "bg-stone-100 border-stone-200 text-stone-700"
        )
      ]}>
        {@label}
      </kbd>
    </button>
    """
  end

  attr :direction, :string, required: true
  attr :target, :string, default: nil
  attr :title, :string, required: true

  defp nav_chevron(assigns) do
    icon =
      case assigns.direction do
        "up" -> "hero-chevron-up"
        "down" -> "hero-chevron-down"
        "left" -> "hero-chevron-left"
        "right" -> "hero-chevron-right"
      end

    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class="tooltip tooltip-bottom tooltip-delayed" data-tip={@title}>
      <%= if @target do %>
        <.link
          patch={@target}
          class="inline-flex items-center justify-center w-7 h-7 rounded-md text-sky-700 bg-white border border-sky-300 transition-all duration-150 hover:bg-sky-100 hover:border-sky-400 hover:text-sky-800"
        >
          <.icon name={@icon} class="w-4 h-4" />
        </.link>
      <% else %>
        <span class="inline-flex items-center justify-center w-7 h-7 rounded-md text-sky-300 bg-white/60 border border-sky-100 cursor-not-allowed">
          <.icon name={@icon} class="w-4 h-4" />
        </span>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => exam_id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, exam_id)

    submissions =
      exam
      |> Exams.list_exam_submissions()
      |> Enum.sort_by(fn s ->
        {String.downcase(s.firstname || ""), String.downcase(s.lastname || "")}
      end)

    {:ok,
     socket
     |> assign(:exam, exam)
     |> assign(:submissions, submissions)
     |> assign(:show_sample_solution_modal, false)
     |> assign(:sample_solution_json, nil)
     |> assign(:show_power_view, false)}
  end

  @impl true
  def handle_params(
        %{"submission_id" => submission_id, "part_id" => part_id} = params,
        _uri,
        socket
      ) do
    %{exam: exam, submissions: submissions} = socket.assigns

    submission =
      Repo.get_by!(ExamSubmission, id: submission_id, exam_id: exam.id)

    parts =
      submission
      |> Exams.correction_content()
      |> Exams.split_content_into_parts()

    current_part =
      Enum.find(parts, &(&1.id == part_id)) ||
        fallback_part_from_exam(exam, part_id)

    if is_nil(current_part) do
      {:noreply,
       socket
       |> put_flash(:error, "Teil nicht gefunden.")
       |> push_navigate(to: ~p"/exams/#{exam}/correction")}
    else
      part_doc = %{"type" => "doc", "content" => current_part.nodes}
      part_doc_json = Jason.encode!(part_doc)

      part_index = Enum.find_index(parts, &(&1.id == current_part.id))
      submission_index = Enum.find_index(submissions, &(&1.id == submission.id))
      max_points = Map.get(exam.sample_solution_points || %{}, current_part.id)
      open_power = Map.get(params, "power") == "1"

      power_data = build_power_view(submission, current_part.id, max_points)

      {:noreply,
       socket
       |> assign(:page_title, "#{exam.name} – #{current_part.label}")
       |> assign(:submission, submission)
       |> assign(:parts, parts)
       |> assign(:current_part, current_part)
       |> assign(:part_doc_json, part_doc_json)
       |> assign(:is_corrected, current_part.id in (submission.corrected_parts || []))
       |> assign(:points, Map.get(submission.points_per_part || %{}, current_part.id))
       |> assign(:max_points, max_points)
       |> assign(:show_sample_solution_modal, false)
       |> assign(:sample_solution_json, nil)
       |> assign(:current_part_index, part_index)
       |> assign(:total_parts, length(parts))
       |> assign(:current_submission_index, submission_index)
       |> assign(:total_submissions, length(submissions))
       |> assign(:prev_part_path, sibling_part_path(exam, submission, parts, part_index, -1))
       |> assign(:next_part_path, sibling_part_path(exam, submission, parts, part_index, +1))
       |> assign(
         :prev_submission_path,
         sibling_submission_path(exam, submissions, submission_index, current_part.id, -1)
       )
       |> assign(
         :next_submission_path,
         sibling_submission_path(exam, submissions, submission_index, current_part.id, +1)
       )
       |> assign(:power_blocks, power_data.blocks)
       |> assign(:power_blocks_count, power_data.count)
       |> assign(:power_per_block, power_data.per_block)
       |> assign(:power_current_total, power_data.current_total)
       |> assign(:show_power_view, open_power and power_data.count > 0)}
    end
  end

  defp build_power_view(submission, part_id, max_points) do
    blocks = Exams.list_part_answer_blocks(submission, part_id)
    count = length(blocks)
    per_block = if count > 0 and is_number(max_points), do: max_points / count, else: nil

    current_total =
      Enum.reduce(blocks, 0.0, fn b, acc ->
        case b.verdict do
          "correct" -> acc + (per_block || 0)
          "half" -> acc + (per_block || 0) / 2
          _ -> acc
        end
      end)
      |> normalize_points()

    %{blocks: blocks, count: count, per_block: per_block, current_total: current_total}
  end

  defp refresh_power_view(socket) do
    %{submission: submission, current_part: part, max_points: max_points} = socket.assigns
    data = build_power_view(submission, part.id, max_points)

    socket
    |> assign(:power_blocks, data.blocks)
    |> assign(:power_blocks_count, data.count)
    |> assign(:power_per_block, data.per_block)
    |> assign(:power_current_total, data.current_total)
    |> assign(:points, Map.get(submission.points_per_part || %{}, part.id))
  end

  defp normalize_points(n) when is_float(n) do
    rounded = Float.round(n * 2) / 2
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end

  defp normalize_points(n), do: n

  @impl true
  def handle_event("set_points_max", _params, socket) do
    case socket.assigns.max_points do
      nil -> {:noreply, socket}
      max -> save_points(socket, max)
    end
  end

  def handle_event("set_points_zero", _params, socket) do
    save_points(socket, 0)
  end

  def handle_event("show_sample_solution_modal", _params, socket) do
    %{exam: exam, current_part: part} = socket.assigns

    nodes =
      exam.sample_solution
      |> Kernel.||(%{})
      |> Exams.split_content_into_parts()
      |> Enum.find(&(&1.id == part.id))
      |> case do
        nil -> []
        p -> p.nodes
      end

    doc = %{"type" => "doc", "content" => nodes}
    sample_solution_json = Jason.encode!(doc)

    {:noreply,
     socket
     |> assign(:show_sample_solution_modal, true)
     |> assign(:sample_solution_json, sample_solution_json)}
  end

  def handle_event("close_sample_solution_modal", _params, socket) do
    {:noreply, assign(socket, :show_sample_solution_modal, false)}
  end

  def handle_event("set_points", %{"points" => raw}, socket) do
    save_points(socket, parse_points(raw))
  end

  def handle_event("open_power_view", _params, socket) do
    {:noreply, assign(socket, :show_power_view, true)}
  end

  def handle_event("close_power_view", _params, socket) do
    {:noreply, assign(socket, :show_power_view, false)}
  end

  def handle_event("set_block_verdict", %{"index" => index, "verdict" => verdict}, socket) do
    %{submission: submission, current_part: part} = socket.assigns
    index_int = parse_index(index)

    current =
      Map.get(
        submission.block_verdicts || %{},
        "#{part.id}:#{index_int}"
      )

    new_verdict = if current == verdict, do: nil, else: verdict

    case Exams.set_block_verdict(submission, part.id, index_int, new_verdict) do
      {:ok, updated} ->
        updated_part =
          updated
          |> Exams.correction_content()
          |> Exams.split_content_into_parts()
          |> Enum.find(&(&1.id == part.id))

        part_doc_json =
          case updated_part do
            nil -> nil
            p -> Jason.encode!(%{"type" => "doc", "content" => p.nodes})
          end

        socket =
          socket
          |> assign(:submission, updated)
          |> refresh_power_view()

        socket =
          if part_doc_json,
            do: push_event(socket, "reload-content", %{content: part_doc_json}),
            else: socket

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Bewertung konnte nicht gespeichert werden.")}
    end
  end

  def handle_event("goto_next_submission_power", _params, socket) do
    case socket.assigns.next_submission_path do
      nil ->
        {:noreply, socket}

      path ->
        {:noreply,
         socket
         |> push_patch(to: "#{path}?power=1")
         |> push_event("power-view-refocus", %{})}
    end
  end

  def handle_event("toggle_corrected", _params, socket) do
    %{submission: submission, current_part: part} = socket.assigns

    result =
      if part.id in (submission.corrected_parts || []) do
        Exams.unmark_part_corrected(submission, part.id)
      else
        Exams.mark_part_corrected(submission, part.id)
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:submission, updated)
         |> assign(:is_corrected, part.id in (updated.corrected_parts || []))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Status konnte nicht aktualisiert werden.")}
    end
  end

  defp parse_index(i) when is_integer(i), do: i

  defp parse_index(i) when is_binary(i) do
    case Integer.parse(i) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp save_points(socket, points) do
    %{submission: submission, current_part: part} = socket.assigns

    case Exams.set_part_points(submission, part.id, points) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:submission, updated)
         |> assign(:points, points)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Punkte konnten nicht gespeichert werden.")}
    end
  end

  defp format_points(n) when is_integer(n), do: Integer.to_string(n)

  defp format_points(n) when is_float(n) do
    if n == trunc(n),
      do: Integer.to_string(trunc(n)),
      else: :erlang.float_to_binary(n, decimals: 1)
  end

  defp format_points(_), do: "—"

  defp power_row_points(_verdict, nil), do: "—"
  defp power_row_points("correct", per), do: format_points(normalize_points(per * 1.0))
  defp power_row_points("half", per), do: format_points(normalize_points(per * 0.5))
  defp power_row_points("wrong", _per), do: "0"
  defp power_row_points(_, _), do: "—"

  defp power_points_class("correct"), do: "bg-green-50 text-green-700"
  defp power_points_class("half"), do: "bg-yellow-50 text-yellow-700"
  defp power_points_class("wrong"), do: "bg-red-50 text-red-600"
  defp power_points_class(_), do: "bg-stone-50 text-stone-400"

  defp parse_points(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        nil

      trimmed ->
        case Float.parse(trimmed) do
          {n, ""} -> if n == trunc(n), do: trunc(n), else: n
          _ -> nil
        end
    end
  end

  defp parse_points(_), do: nil

  defp sibling_part_path(_exam, _submission, _parts, nil, _delta), do: nil

  defp sibling_part_path(exam, submission, parts, idx, delta) do
    target = idx + delta

    if target < 0 or target >= length(parts) do
      nil
    else
      part = Enum.at(parts, target)
      ~p"/exams/#{exam}/correction/#{submission.id}/parts/#{part.id}"
    end
  end

  defp sibling_submission_path(_exam, _submissions, nil, _part_id, _delta), do: nil

  defp sibling_submission_path(exam, submissions, idx, part_id, delta) do
    target = idx + delta

    if target < 0 or target >= length(submissions) do
      nil
    else
      sub = Enum.at(submissions, target)
      ~p"/exams/#{exam}/correction/#{sub.id}/parts/#{part_id}"
    end
  end

  # If a submission has no nodes for the requested part_id (e.g. never opened
  # or content out-of-sync), fall back to the exam's canonical part so the
  # editor still renders the question structure.
  defp fallback_part_from_exam(exam, part_id) do
    exam.content
    |> Kernel.||(%{})
    |> Exams.split_content_into_parts()
    |> Enum.find(&(&1.id == part_id))
  end
end
