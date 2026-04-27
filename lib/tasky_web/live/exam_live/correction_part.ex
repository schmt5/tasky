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
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Korrektur", navigate: ~p"/exams/#{@exam}/correction"},
              %{label: "#{@submission.firstname} #{@submission.lastname} – #{@current_part.label}"}
            ]} />

            <div class="flex items-center gap-2 shrink-0">
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
              <span class="w-px h-6 bg-stone-200 mx-1" />
              <.nav_chevron direction="left" target={@prev_part_path} title="Vorheriger Teil" />
              <.nav_chevron direction="right" target={@next_part_path} title="Nächster Teil" />
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
                  <p class="text-xs text-stone-500 mt-1">
                    <span class="font-medium text-stone-700">
                      {@submission.firstname} {@submission.lastname}
                    </span>
                    <span class="text-stone-300 mx-1">·</span>
                    <%= if @submission.submitted do %>
                      <span class="text-purple-500 font-medium">Abgegeben</span>
                    <% else %>
                      <span class="text-stone-400">Nicht abgegeben</span>
                    <% end %>
                  </p>
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
                      class="w-full font-mono text-base text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-purple-300 focus:border-purple-400"
                    />
                  </form>
                  <div class="flex items-center gap-2 mt-3">
                    <button
                      type="button"
                      phx-click="set_points_max"
                      disabled={is_nil(@max_points)}
                      title={
                        if is_nil(@max_points),
                          do: "Keine Maximalpunkte in der Musterlösung gesetzt",
                          else: "Maximale Punkte vergeben"
                      }
                      class="flex-1 inline-flex items-center justify-center gap-1.5 text-xs font-semibold px-3 py-2 rounded-lg transition-all duration-150 active:scale-[0.98] text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent disabled:hover:border-stone-200"
                    >
                      <.icon name="hero-check" class="w-3.5 h-3.5" /> Max
                    </button>
                    <button
                      type="button"
                      phx-click="set_points_zero"
                      class="flex-1 inline-flex items-center justify-center gap-1.5 text-xs font-semibold px-3 py-2 rounded-lg transition-all duration-150 active:scale-[0.98] text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300"
                    >
                      <.icon name="hero-x-mark" class="w-3.5 h-3.5" /> 0
                    </button>
                  </div>
                </div>

                <div class="p-5 border-b border-stone-100">
                  <button
                    type="button"
                    phx-click="show_sample_solution_modal"
                    class="w-full inline-flex items-center justify-center gap-2 text-sm font-semibold px-4 py-2.5 rounded-lg transition-all duration-150 active:scale-[0.98] text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300"
                  >
                    <.icon name="hero-light-bulb" class="w-4 h-4" /> Musterlösung anzeigen
                  </button>
                </div>

                <div class="p-5 border-b border-stone-100 space-y-2">
                  <div class="flex items-center gap-2">
                    <button
                      type="button"
                      phx-click="ai_correct"
                      disabled={@ai_correcting or is_nil(@max_points)}
                      title={
                        cond do
                          @ai_correcting -> "KI korrigiert gerade..."
                          is_nil(@max_points) -> "Keine Maximalpunkte in der Musterlösung gesetzt"
                          true -> "Automatisch mit KI korrigieren"
                        end
                      }
                      class={[
                        "flex-1 inline-flex items-center justify-center gap-2 text-sm font-semibold px-4 py-2.5 rounded-lg transition-all duration-150 active:scale-[0.98]",
                        if(@ai_correcting,
                          do: "bg-indigo-100 text-indigo-400 border border-indigo-200 cursor-wait",
                          else:
                            "text-indigo-600 border border-indigo-200 hover:bg-indigo-50 hover:border-indigo-300 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent disabled:hover:border-indigo-200"
                        )
                      ]}
                    >
                      <%= if @ai_correcting do %>
                        <svg
                          class="animate-spin w-4 h-4"
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                        >
                          <circle
                            class="opacity-25"
                            cx="12"
                            cy="12"
                            r="10"
                            stroke="currentColor"
                            stroke-width="4"
                          >
                          </circle>
                          <path
                            class="opacity-75"
                            fill="currentColor"
                            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                          >
                          </path>
                        </svg>
                        KI korrigiert...
                      <% else %>
                        <.icon name="hero-sparkles" class="w-4 h-4" /> KI korrigieren
                      <% end %>
                    </button>
                    <button
                      type="button"
                      phx-click="show_ai_config_modal"
                      class={[
                        "shrink-0 inline-flex items-center justify-center w-10 h-[42px] rounded-lg border transition-all duration-150 active:scale-[0.98]",
                        if(@ignore_spelling,
                          do: "border-indigo-300 bg-indigo-50 text-indigo-600",
                          else:
                            "border-indigo-200 text-indigo-400 hover:bg-indigo-50 hover:border-indigo-300 hover:text-indigo-600"
                        )
                      ]}
                      title="KI-Korrektur konfigurieren"
                    >
                      <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
                    </button>
                  </div>
                  <%= if @pre_ai_nodes do %>
                    <button
                      type="button"
                      phx-click="undo_ai_correct"
                      class="w-full inline-flex items-center justify-center gap-2 text-xs font-semibold px-3 py-2 rounded-lg transition-all duration-150 active:scale-[0.98] text-amber-600 border border-amber-200 hover:bg-amber-50 hover:border-amber-300"
                    >
                      <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" /> Rückgängig
                    </button>
                  <% end %>
                  <%= if @ai_error do %>
                    <p class="text-xs text-red-500 mt-1">{@ai_error}</p>
                  <% end %>
                </div>

                <div class="p-5">
                  <button
                    type="button"
                    phx-click="toggle_corrected"
                    class={[
                      "w-full inline-flex items-center justify-center gap-2 text-sm font-semibold px-4 py-2.5 rounded-lg transition-all duration-150 active:scale-[0.98]",
                      if(@is_corrected,
                        do:
                          "bg-purple-500 text-white shadow-[0_2px_8px_rgba(168,85,247,0.25)] hover:bg-purple-600",
                        else:
                          "text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300"
                      )
                    ]}
                  >
                    <.icon name="hero-check-badge" class="w-4 h-4" />
                    {if @is_corrected, do: "Korrigiert", else: "Als korrigiert markieren"}
                  </button>
                </div>
              </div>
            </aside>
          </div>
        </div>

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
                <button
                  type="button"
                  phx-click="close_sample_solution_modal"
                  class="text-stone-400 hover:text-stone-700 transition-colors duration-150"
                  title="Schliessen"
                >
                  <.icon name="hero-x-mark" class="w-5 h-5" />
                </button>
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

        <%= if @show_ai_config_modal do %>
          <dialog
            id="ai-config-modal"
            class="modal modal-open"
            phx-window-keydown="close_ai_config_modal"
            phx-key="escape"
          >
            <div class="modal-backdrop bg-stone-900/50" phx-click="close_ai_config_modal"></div>
            <div class="modal-box max-w-md p-0 bg-white rounded-[16px] shadow-2xl">
              <div class="px-6 pt-6 pb-4 border-b border-stone-100 flex items-start gap-4">
                <div class="w-10 h-10 rounded-[10px] bg-indigo-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-cog-6-tooth" class="w-5 h-5 text-indigo-500" />
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-lg font-semibold text-stone-900">KI-Korrektur Einstellungen</h3>
                  <p class="text-sm text-stone-500 mt-0.5">{@current_part.label}</p>
                </div>
                <button
                  type="button"
                  phx-click="close_ai_config_modal"
                  class="text-stone-400 hover:text-stone-700 transition-colors duration-150"
                  title="Schliessen"
                >
                  <.icon name="hero-x-mark" class="w-5 h-5" />
                </button>
              </div>
              <div class="p-6">
                <label class="flex items-start gap-3 cursor-pointer group">
                  <input
                    type="checkbox"
                    checked={@ignore_spelling}
                    phx-click="toggle_ignore_spelling"
                    class="mt-0.5 w-5 h-5 rounded border-stone-300 text-indigo-600 focus:ring-indigo-500 cursor-pointer"
                  />
                  <div>
                    <span class="text-sm font-semibold text-stone-800 group-hover:text-stone-900">
                      Rechtschreibung ignorieren
                    </span>
                    <p class="text-xs text-stone-500 mt-1 leading-relaxed">
                      Wenn aktiviert, werden Rechtschreibfehler bei der KI-Korrektur nicht als falsch gewertet.
                      Geeignet für Fächer wie Geschichte oder Geografie, bei denen der Inhalt wichtiger ist
                      als die exakte Schreibweise. Für Sprachprüfungen (z.B. Englisch, Französisch) sollte
                      diese Option deaktiviert bleiben.
                    </p>
                  </div>
                </label>
              </div>
              <div class="px-6 pb-6 pt-3 flex items-center justify-end border-t border-stone-100">
                <button
                  type="button"
                  phx-click="close_ai_config_modal"
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
    <%= if @target do %>
      <.link
        patch={@target}
        title={@title}
        class="inline-flex items-center justify-center w-9 h-9 rounded-lg text-stone-600 border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-800"
      >
        <.icon name={@icon} class="w-4 h-4" />
      </.link>
    <% else %>
      <span
        title={@title}
        class="inline-flex items-center justify-center w-9 h-9 rounded-lg text-stone-300 border border-stone-100 cursor-not-allowed"
      >
        <.icon name={@icon} class="w-4 h-4" />
      </span>
    <% end %>
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
     |> assign(:sample_solution_json, nil)}
  end

  @impl true
  def handle_params(%{"submission_id" => submission_id, "part_id" => part_id}, _uri, socket) do
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

      {:noreply,
       socket
       |> assign(:page_title, "#{exam.name} – #{current_part.label}")
       |> assign(:submission, submission)
       |> assign(:parts, parts)
       |> assign(:current_part, current_part)
       |> assign(:part_doc_json, part_doc_json)
       |> assign(:is_corrected, current_part.id in (submission.corrected_parts || []))
       |> assign(:points, Map.get(submission.points_per_part || %{}, current_part.id))
       |> assign(
         :max_points,
         Map.get(exam.sample_solution_points || %{}, current_part.id)
       )
       |> assign(:show_sample_solution_modal, false)
       |> assign(:sample_solution_json, nil)
       |> assign(:show_ai_config_modal, false)
       |> assign(
         :ignore_spelling,
         (exam.ai_correction_config || %{})
         |> Map.get(part_id, %{})
         |> Map.get("ignore_spelling", false)
       )
       |> assign(:ai_correcting, false)
       |> assign(:ai_error, nil)
       |> assign(:pre_ai_nodes, nil)
       |> assign(:prev_part_path, sibling_part_path(exam, submission, parts, part_index, -1))
       |> assign(:next_part_path, sibling_part_path(exam, submission, parts, part_index, +1))
       |> assign(
         :prev_submission_path,
         sibling_submission_path(exam, submissions, submission_index, current_part.id, -1)
       )
       |> assign(
         :next_submission_path,
         sibling_submission_path(exam, submissions, submission_index, current_part.id, +1)
       )}
    end
  end

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

  def handle_event("show_ai_config_modal", _params, socket) do
    {:noreply, assign(socket, :show_ai_config_modal, true)}
  end

  def handle_event("close_ai_config_modal", _params, socket) do
    {:noreply, assign(socket, :show_ai_config_modal, false)}
  end

  def handle_event("toggle_ignore_spelling", _params, socket) do
    new_val = !socket.assigns.ignore_spelling
    part_id = socket.assigns.current_part.id

    {:ok, updated_exam} =
      Exams.update_ai_correction_config(socket.assigns.exam, part_id, %{
        "ignore_spelling" => new_val
      })

    {:noreply,
     socket
     |> assign(:exam, updated_exam)
     |> assign(:ignore_spelling, new_val)}
  end

  def handle_event("ai_correct", _params, socket) do
    %{exam: exam, current_part: part, max_points: max_points} = socket.assigns

    submission_nodes = part.nodes

    sample_solution_nodes =
      exam.sample_solution
      |> Kernel.||(%{})
      |> Exams.split_content_into_parts()
      |> Enum.find(&(&1.id == part.id))
      |> case do
        nil -> []
        p -> p.nodes
      end

    opts = %{ignore_spelling: socket.assigns.ignore_spelling}
    task_ref = make_ref()
    pid = self()

    Task.start(fn ->
      result =
        Tasky.AI.CorrectionClient.correct_part(
          submission_nodes,
          sample_solution_nodes,
          max_points,
          opts
        )

      send(pid, {:ai_correction_result, task_ref, result})
    end)

    {:noreply,
     socket
     |> assign(:ai_correcting, true)
     |> assign(:ai_error, nil)
     |> assign(:ai_task_ref, task_ref)
     |> assign(:pre_ai_nodes, submission_nodes)}
  end

  def handle_event("undo_ai_correct", _params, socket) do
    %{submission: submission, current_part: part, pre_ai_nodes: pre_ai_nodes} = socket.assigns

    if pre_ai_nodes do
      case Exams.update_corrected_part_content(submission, part.id, pre_ai_nodes) do
        {:ok, updated_submission} ->
          part_doc = %{"type" => "doc", "content" => pre_ai_nodes}
          part_doc_json = Jason.encode!(part_doc)

          {:noreply,
           socket
           |> assign(:submission, updated_submission)
           |> assign(:current_part, %{part | nodes: pre_ai_nodes})
           |> assign(:part_doc_json, part_doc_json)
           |> assign(:pre_ai_nodes, nil)
           |> assign(:points, nil)
           |> push_event("reload-content", %{content: part_doc_json})}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Rückgängig machen fehlgeschlagen.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_points", %{"points" => raw}, socket) do
    save_points(socket, parse_points(raw))
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

  @impl true
  def handle_info({:ai_correction_result, ref, result}, socket) do
    if ref == socket.assigns[:ai_task_ref] do
      socket = assign(socket, :ai_correcting, false)

      case result do
        {:ok, %{corrected_nodes: nodes, points: points}} ->
          %{submission: submission, current_part: part, max_points: max_points} = socket.assigns

          # Clamp points to [0, max_points]
          clamped_points =
            if max_points do
              points |> max(0) |> min(max_points)
            else
              max(points, 0)
            end

          case Exams.update_corrected_part_content(submission, part.id, nodes) do
            {:ok, updated_submission} ->
              # Also save the points
              case Exams.set_part_points(updated_submission, part.id, clamped_points) do
                {:ok, updated_submission2} ->
                  part_doc = %{"type" => "doc", "content" => nodes}
                  part_doc_json = Jason.encode!(part_doc)

                  {:noreply,
                   socket
                   |> assign(:submission, updated_submission2)
                   |> assign(:current_part, %{part | nodes: nodes})
                   |> assign(:part_doc_json, part_doc_json)
                   |> assign(:points, clamped_points)
                   |> push_event("reload-content", %{content: part_doc_json})}

                {:error, _} ->
                  # Content saved but points failed — still show updated content
                  part_doc = %{"type" => "doc", "content" => nodes}
                  part_doc_json = Jason.encode!(part_doc)

                  {:noreply,
                   socket
                   |> assign(:submission, updated_submission)
                   |> assign(:current_part, %{part | nodes: nodes})
                   |> assign(:part_doc_json, part_doc_json)
                   |> assign(:ai_error, "Punkte konnten nicht gespeichert werden.")
                   |> push_event("reload-content", %{content: part_doc_json})}
              end

            {:error, _} ->
              {:noreply,
               assign(socket, :ai_error, "Korrigierter Inhalt konnte nicht gespeichert werden.")}
          end

        {:error, reason} ->
          {:noreply, assign(socket, :ai_error, reason)}
      end
    else
      {:noreply, socket}
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
