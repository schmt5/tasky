defmodule TaskyWeb.ExamLive.Content do
  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/exams/#{@exam}/content"}
    >
      <%!-- Page Header --%>
      <div class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 h-[54px] flex items-center">
        <div class="max-w-7xl mx-auto w-full flex items-center justify-between gap-4">
          <div class="flex items-center gap-2 min-w-0">
            <.back_button
              navigate={~p"/exams/#{@exam}"}
              tooltip={"Zurück zu #{@exam.name}"}
              size="sm"
            />
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"}
            ]} />
          </div>

          <div class="inline-flex items-center gap-0.5 bg-stone-100 rounded-lg p-0.5">
            <.tab_link
              label="Inhalt"
              active={@tab == "inhalt"}
              patch={~p"/exams/#{@exam}/content?tab=inhalt"}
            />
            <.tab_link
              label="Musterlösung"
              active={@tab == "musterloesung"}
              patch={musterloesung_url(@exam, @parts)}
            />
          </div>
        </div>
      </div>

      <%!-- Inhalt tab: full-width editor flush under the header --%>
      <div :if={@tab == "inhalt"} class="min-w-0">
        <div
          id={"exam-content-editor-#{@exam.id}"}
          phx-hook="ExamContentEditor"
          phx-update="ignore"
          data-exam-id={@exam.id}
          data-content={@content_json}
        >
        </div>
      </div>

      <%!-- Musterlösung tab --%>
      <div :if={@tab == "musterloesung"} class="max-w-7xl mx-auto px-8 py-6">
        <%!-- Part navigation --%>
        <div :if={@current_part} class="mb-4 flex justify-end">
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

        <div class="grid grid-cols-4 gap-6 items-start">
          <div class="col-span-3 min-w-0">
            <div :if={@current_part == nil} class="text-sm text-stone-400 italic">
              Lege zuerst im Tab „Inhalt“ eine Frage (Überschrift) an, um die Musterlösung zu erfassen.
            </div>
            <div
              :if={@current_part}
              id={"sample-solution-part-editor-#{@exam.id}-#{@current_part.id}"}
              phx-hook="ExamSampleSolutionPartEditor"
              phx-update="ignore"
              data-exam-id={@exam.id}
              data-part-id={@current_part.id}
              data-content={@part_doc_json}
            >
            </div>
          </div>

          <aside :if={@current_part} class="col-span-1 sticky top-[72px]">
            <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
              <div class="p-5 border-b border-stone-100">
                <h2 class="text-base font-semibold text-stone-800 truncate">{@current_part.label}</h2>
                <p class="text-xs text-stone-500 mt-1">Musterlösung</p>
              </div>

              <div class="p-5">
                <label class="block text-xs font-semibold text-stone-500 uppercase tracking-wide mb-2">
                  Max. Punkte
                </label>
                <div class="flex items-center gap-1.5">
                  <button
                    type="button"
                    phx-click="adjust_max_points"
                    phx-value-direction="down"
                    disabled={is_nil(@max_points) or @max_points <= 0}
                    class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent shrink-0"
                    title="−0.25"
                  >
                    <.icon name="hero-minus" class="w-4 h-4" />
                  </button>
                  <form phx-change="set_max_points" phx-submit="set_max_points" class="flex-1">
                    <input
                      type="number"
                      name="points"
                      value={@max_points || ""}
                      step="0.25"
                      min="0"
                      inputmode="decimal"
                      phx-debounce="500"
                      placeholder="—"
                      class="w-full font-mono text-base text-center text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-purple-300 focus:border-purple-400"
                    />
                  </form>
                  <button
                    type="button"
                    phx-click="adjust_max_points"
                    phx-value-direction="up"
                    class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 shrink-0"
                    title="+0.25"
                  >
                    <.icon name="hero-plus" class="w-4 h-4" />
                  </button>
                </div>
              </div>

              <div class="p-5 border-t border-stone-100 space-y-4">
                <label class="flex items-start gap-3 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={@auto_correct}
                    phx-click="toggle_auto_correct"
                    class="mt-0.5 w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150 shrink-0"
                  />
                  <span class="min-w-0">
                    <span class="block text-sm font-medium text-stone-700">Auto-Korrektur</span>
                    <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                      Diese Aufgabe wird beim Start der Auto-Korrektur automatisch bewertet.
                    </span>
                  </span>
                </label>

                <label class={[
                  "flex items-start gap-3",
                  if(@auto_correct, do: "cursor-pointer", else: "cursor-not-allowed opacity-40")
                ]}>
                  <input
                    type="checkbox"
                    checked={@ignore_case}
                    disabled={!@auto_correct}
                    phx-click="toggle_ignore_case"
                    class="mt-0.5 w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 transition-colors duration-150 shrink-0 disabled:cursor-not-allowed"
                  />
                  <span class="min-w-0">
                    <span class="block text-sm font-medium text-stone-700">
                      Gross-/Kleinschreibung ignorieren
                    </span>
                    <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                      Bei der Auto-Korrektur dieser Aufgabe wird Gross-/Kleinschreibung nicht bewertet.
                    </span>
                  </span>
                </label>

                <label class={[
                  "flex items-start gap-3",
                  if(@auto_correct, do: "cursor-pointer", else: "cursor-not-allowed opacity-40")
                ]}>
                  <input
                    type="checkbox"
                    checked={@ignore_spelling}
                    disabled={!@auto_correct}
                    phx-click="toggle_ignore_spelling"
                    class="mt-0.5 w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 transition-colors duration-150 shrink-0 disabled:cursor-not-allowed"
                  />
                  <span class="min-w-0">
                    <span class="block text-sm font-medium text-stone-700">
                      Rechtschreibung ignorieren
                    </span>
                    <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                      Bei der Auto-Korrektur dieser Aufgabe werden Rechtschreibfehler nicht streng bewertet (Fuzzy-Matching ab Jaro-Ähnlichkeit ≥ 0,85).
                    </span>
                  </span>
                </label>
              </div>
            </div>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :active, :boolean, required: true
  attr :patch, :string, required: true

  defp tab_link(assigns) do
    ~H"""
    <.link
      patch={@patch}
      class={[
        "px-3 py-1 rounded-md text-sm font-medium transition-colors",
        if(@active,
          do: "bg-white text-stone-900 shadow-sm",
          else: "text-stone-500 hover:text-stone-700"
        )
      ]}
    >
      {@label}
    </.link>
    """
  end

  attr :direction, :string, required: true
  attr :target, :string, default: nil
  attr :title, :string, required: true

  defp nav_chevron(assigns) do
    icon =
      case assigns.direction do
        "left" -> "hero-chevron-left"
        "right" -> "hero-chevron-right"
      end

    assigns = assign(assigns, :icon, icon)

    ~H"""
    <%= if @target do %>
      <.link
        patch={@target}
        title={@title}
        class="inline-flex items-center justify-center w-7 h-7 rounded-md text-sky-700 bg-white border border-sky-300 transition-all duration-150 hover:bg-sky-100 hover:border-sky-400 hover:text-sky-800"
      >
        <.icon name={@icon} class="w-4 h-4" />
      </.link>
    <% else %>
      <span
        title={@title}
        class="inline-flex items-center justify-center w-7 h-7 rounded-md text-sky-300 bg-white/60 border border-sky-100 cursor-not-allowed"
      >
        <.icon name={@icon} class="w-4 h-4" />
      </span>
    <% end %>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)
    {:ok, assign(socket, :exam, exam)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Reload exam each time params change so structure edits made in the
    # Inhalt tab are reflected when the teacher switches to Musterlösung.
    exam = Exams.get_exam!(socket.assigns.current_scope, socket.assigns.exam.id)
    tab = if params["tab"] == "musterloesung", do: "musterloesung", else: "inhalt"
    parts = Exams.split_content_into_parts(exam.content || %{})

    socket =
      socket
      |> assign(:exam, exam)
      |> assign(:tab, tab)
      |> assign(:parts, parts)
      |> assign(:page_title, "#{exam.name} – #{tab_label(tab)}")

    case tab do
      "inhalt" ->
        {:noreply, assign(socket, :content_json, Jason.encode!(exam.content || %{}))}

      "musterloesung" ->
        handle_musterloesung_params(socket, exam, parts, params)
    end
  end

  defp handle_musterloesung_params(socket, _exam, [], _params) do
    {:noreply,
     socket
     |> assign(:current_part, nil)
     |> assign(:current_part_index, nil)
     |> assign(:total_parts, 0)
     |> assign(:prev_part_path, nil)
     |> assign(:next_part_path, nil)}
  end

  defp handle_musterloesung_params(socket, exam, parts, params) do
    part_id = params["part"]

    current_part =
      case Enum.find(parts, &(&1.id == part_id)) do
        nil -> hd(parts)
        found -> found
      end

    if part_id != current_part.id do
      {:noreply,
       push_patch(socket,
         to: ~p"/exams/#{exam}/content?tab=musterloesung&part=#{current_part.id}"
       )}
    else
      sample_part =
        exam
        |> Exams.sample_solution_doc()
        |> Exams.split_content_into_parts()
        |> Enum.find(&(&1.id == current_part.id))

      sample_nodes = if sample_part, do: sample_part.nodes, else: current_part.nodes
      part_doc = %{"type" => "doc", "content" => sample_nodes}
      part_index = Enum.find_index(parts, &(&1.id == current_part.id))

      {:noreply,
       socket
       |> assign(:current_part, current_part)
       |> assign(:current_part_index, part_index)
       |> assign(:total_parts, length(parts))
       |> assign(:part_doc_json, Jason.encode!(part_doc))
       |> assign(:max_points, Map.get(exam.sample_solution_points || %{}, current_part.id))
       |> assign(:auto_correct, part_config_flag(exam, current_part.id, "auto_correct"))
       |> assign(:ignore_case, part_config_flag(exam, current_part.id, "ignore_case"))
       |> assign(:ignore_spelling, part_config_flag(exam, current_part.id, "ignore_spelling"))
       |> assign(:prev_part_path, sibling_part_path(exam, parts, part_index, -1))
       |> assign(:next_part_path, sibling_part_path(exam, parts, part_index, +1))}
    end
  end

  @impl true
  def handle_event("set_max_points", %{"points" => raw}, socket) do
    save_max_points(socket, parse_points(raw))
  end

  def handle_event("adjust_max_points", %{"direction" => dir}, socket) do
    delta = if dir == "up", do: 0.25, else: -0.25
    new_value = max((socket.assigns.max_points || 0) + delta, 0)
    save_max_points(socket, new_value)
  end

  def handle_event("toggle_auto_correct", _params, socket) do
    %{exam: exam, current_part: part} = socket.assigns
    new_val = !socket.assigns.auto_correct
    part_config = Map.get(exam.ai_correction_config || %{}, part.id, %{})

    updated_part_config =
      part_config
      |> Map.put("auto_correct", new_val)
      |> then(fn cfg ->
        if new_val,
          do: cfg,
          else: cfg |> Map.put("ignore_spelling", false) |> Map.put("ignore_case", false)
      end)

    case Exams.update_ai_correction_config(exam, part.id, updated_part_config) do
      {:ok, updated_exam} ->
        socket = socket |> assign(:exam, updated_exam) |> assign(:auto_correct, new_val)

        socket =
          if new_val,
            do: socket,
            else: socket |> assign(:ignore_case, false) |> assign(:ignore_spelling, false)

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Einstellung konnte nicht gespeichert werden.")}
    end
  end

  def handle_event("toggle_ignore_case", _params, socket) do
    toggle_flag_if_auto(socket, "ignore_case", :ignore_case)
  end

  def handle_event("toggle_ignore_spelling", _params, socket) do
    toggle_flag_if_auto(socket, "ignore_spelling", :ignore_spelling)
  end

  defp toggle_flag_if_auto(socket, config_key, assign_key) do
    if socket.assigns.auto_correct do
      %{exam: exam, current_part: part} = socket.assigns
      new_val = !Map.fetch!(socket.assigns, assign_key)
      part_config = Map.get(exam.ai_correction_config || %{}, part.id, %{})
      updated = Map.put(part_config, config_key, new_val)

      case Exams.update_ai_correction_config(exam, part.id, updated) do
        {:ok, updated_exam} ->
          {:noreply, socket |> assign(:exam, updated_exam) |> assign(assign_key, new_val)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Einstellung konnte nicht gespeichert werden.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp save_max_points(socket, points) do
    %{exam: exam, current_part: part} = socket.assigns

    case Exams.set_sample_solution_part_points(exam, part.id, points) do
      {:ok, updated} ->
        {:noreply, socket |> assign(:exam, updated) |> assign(:max_points, points)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Punkte konnten nicht gespeichert werden.")}
    end
  end

  defp tab_label("inhalt"), do: "Inhalt"
  defp tab_label("musterloesung"), do: "Musterlösung"

  defp musterloesung_url(exam, []), do: ~p"/exams/#{exam}/content?tab=musterloesung"

  defp musterloesung_url(exam, [first | _]),
    do: ~p"/exams/#{exam}/content?tab=musterloesung&part=#{first.id}"

  defp part_config_flag(exam, part_id, key) do
    (exam.ai_correction_config || %{})
    |> Map.get(part_id, %{})
    |> Map.get(key, false)
  end

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

  defp sibling_part_path(_exam, _parts, nil, _delta), do: nil

  defp sibling_part_path(exam, parts, idx, delta) do
    target = idx + delta

    if target < 0 or target >= length(parts) do
      nil
    else
      part = Enum.at(parts, target)
      ~p"/exams/#{exam}/content?tab=musterloesung&part=#{part.id}"
    end
  end
end
