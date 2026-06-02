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
      <div
        id="content-page-header"
        phx-hook="StickyShadow"
        class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 h-[54px] flex items-center transition-shadow duration-200"
      >
        <div class="max-w-7xl mx-auto w-full flex items-center justify-between gap-4">
          <div class="flex items-center gap-2 min-w-0">
            <.back_button
              navigate={~p"/exams/#{@exam}"}
              tooltip={"Zurück zu #{@exam.name}"}
              size="sm"
            />
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Bearbeiten"}
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
              patch={~p"/exams/#{@exam}/content?tab=musterloesung"}
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
      <div :if={@tab == "musterloesung"} class="bg-stone-100 min-h-[calc(100vh-54px)]">
        <%!-- Shared toolbar: one bar bound to the focused part editor --%>
        <div
          :if={@part_views != []}
          id={"solution-toolbar-#{@exam.id}"}
          phx-hook="SolutionToolbar"
          phx-update="ignore"
          class="sticky top-[54px] z-30"
        >
        </div>

        <div class="max-w-7xl mx-auto px-8 py-6">
          <div
            :if={@part_views == []}
            class="flex flex-col items-center justify-center text-center py-24"
          >
            <div class="flex items-center justify-center w-14 h-14 rounded-2xl bg-stone-100 text-stone-400 mb-4">
              <.icon name="hero-document-text" class="w-7 h-7" />
            </div>
            <h3 class="text-base font-semibold text-stone-700">Noch keine Frage vorhanden</h3>
            <p class="text-sm text-stone-500 mt-1.5 max-w-md leading-relaxed">
              Lege zuerst im Tab <span class="font-medium text-stone-600">„Inhalt“</span>
              eine Frage (Überschrift) an, um hier die Musterlösung zu erfassen.
            </p>
          </div>

          <div :for={pv <- @part_views} class="grid grid-cols-4 gap-6 items-stretch mb-10">
            <div class="col-span-3 min-w-0">
              <div
                id={"sample-solution-part-editor-#{@exam.id}-#{pv.id}"}
                phx-hook="ExamSampleSolutionPartEditor"
                phx-update="ignore"
                data-exam-id={@exam.id}
                data-part-id={pv.id}
                data-content={pv.doc_json}
                class="h-full"
              >
              </div>
            </div>

            <%!-- top offset: 54px header + shared toolbar height --%>
            <aside class="col-span-1 self-start sticky top-[180px]">
              <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
                <div class="p-5 border-b border-stone-100">
                  <h2 class="text-base font-semibold text-stone-800 truncate">{pv.label}</h2>
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
                      phx-value-part-id={pv.id}
                      disabled={is_nil(pv.max_points) or pv.max_points <= 0}
                      class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent shrink-0"
                      title="−0.25"
                    >
                      <.icon name="hero-minus" class="w-4 h-4" />
                    </button>
                    <form phx-change="set_max_points" phx-submit="set_max_points" class="flex-1">
                      <input type="hidden" name="part_id" value={pv.id} />
                      <input
                        type="number"
                        name="points"
                        value={pv.max_points || ""}
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
                      phx-value-part-id={pv.id}
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
                      checked={pv.auto_correct}
                      phx-click="toggle_auto_correct"
                      phx-value-part-id={pv.id}
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
                    if(pv.auto_correct, do: "cursor-pointer", else: "cursor-not-allowed opacity-40")
                  ]}>
                    <input
                      type="checkbox"
                      checked={pv.ignore_case}
                      disabled={!pv.auto_correct}
                      phx-click="toggle_ignore_case"
                      phx-value-part-id={pv.id}
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
                    if(pv.auto_correct, do: "cursor-pointer", else: "cursor-not-allowed opacity-40")
                  ]}>
                    <input
                      type="checkbox"
                      checked={pv.ignore_spelling}
                      disabled={!pv.auto_correct}
                      phx-click="toggle_ignore_spelling"
                      phx-value-part-id={pv.id}
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

    socket =
      socket
      |> assign(:exam, exam)
      |> assign(:tab, tab)
      |> assign(:page_title, "#{exam.name} – #{tab_label(tab)}")

    case tab do
      "inhalt" ->
        {:noreply, assign(socket, :content_json, Jason.encode!(exam.content || %{}))}

      "musterloesung" ->
        {:noreply, assign(socket, :part_views, build_part_views(exam))}
    end
  end

  # One view-model entry per part, rendered as a stacked editor + points card.
  # `doc_json` is only computed here (full navigation) — event handlers must
  # never touch it, so the phx-update="ignore" editor hooks stay untouched.
  defp build_part_views(exam) do
    parts = Exams.split_content_into_parts(exam.content || %{})

    sample_parts =
      exam
      |> Exams.sample_solution_doc()
      |> Exams.split_content_into_parts()
      |> Map.new(&{&1.id, &1})

    Enum.map(parts, fn part ->
      nodes =
        case Map.get(sample_parts, part.id) do
          nil -> part.nodes
          sample -> sample.nodes
        end

      %{
        id: part.id,
        label: part.label,
        doc_json: Jason.encode!(%{"type" => "doc", "content" => nodes}),
        max_points: Map.get(exam.sample_solution_points || %{}, part.id),
        auto_correct: part_config_flag(exam, part.id, "auto_correct"),
        ignore_case: part_config_flag(exam, part.id, "ignore_case"),
        ignore_spelling: part_config_flag(exam, part.id, "ignore_spelling")
      }
    end)
  end

  @impl true
  def handle_event("set_max_points", %{"points" => raw, "part_id" => part_id}, socket) do
    save_max_points(socket, part_id, parse_points(raw))
  end

  def handle_event("adjust_max_points", %{"direction" => dir, "part-id" => part_id}, socket) do
    case part_view(socket, part_id) do
      nil ->
        {:noreply, socket}

      pv ->
        delta = if dir == "up", do: 0.25, else: -0.25
        new_value = max((pv.max_points || 0) + delta, 0)
        save_max_points(socket, part_id, new_value)
    end
  end

  def handle_event("toggle_auto_correct", %{"part-id" => part_id}, socket) do
    case part_view(socket, part_id) do
      nil ->
        {:noreply, socket}

      pv ->
        exam = socket.assigns.exam
        new_val = !pv.auto_correct
        part_config = Map.get(exam.ai_correction_config || %{}, part_id, %{})

        updated_part_config =
          part_config
          |> Map.put("auto_correct", new_val)
          |> then(fn cfg ->
            if new_val,
              do: cfg,
              else: cfg |> Map.put("ignore_spelling", false) |> Map.put("ignore_case", false)
          end)

        case Exams.update_ai_correction_config(exam, part_id, updated_part_config) do
          {:ok, updated_exam} ->
            changes =
              if new_val,
                do: %{auto_correct: true},
                else: %{auto_correct: false, ignore_case: false, ignore_spelling: false}

            {:noreply,
             socket
             |> assign(:exam, updated_exam)
             |> update_part_view(part_id, changes)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Einstellung konnte nicht gespeichert werden.")}
        end
    end
  end

  def handle_event("toggle_ignore_case", %{"part-id" => part_id}, socket) do
    toggle_flag_if_auto(socket, part_id, "ignore_case", :ignore_case)
  end

  def handle_event("toggle_ignore_spelling", %{"part-id" => part_id}, socket) do
    toggle_flag_if_auto(socket, part_id, "ignore_spelling", :ignore_spelling)
  end

  defp toggle_flag_if_auto(socket, part_id, config_key, view_key) do
    pv = part_view(socket, part_id)

    if pv && pv.auto_correct do
      exam = socket.assigns.exam
      new_val = !Map.fetch!(pv, view_key)
      part_config = Map.get(exam.ai_correction_config || %{}, part_id, %{})
      updated = Map.put(part_config, config_key, new_val)

      case Exams.update_ai_correction_config(exam, part_id, updated) do
        {:ok, updated_exam} ->
          {:noreply,
           socket
           |> assign(:exam, updated_exam)
           |> update_part_view(part_id, %{view_key => new_val})}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Einstellung konnte nicht gespeichert werden.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp save_max_points(socket, part_id, points) do
    case part_view(socket, part_id) do
      nil ->
        {:noreply, socket}

      _pv ->
        case Exams.set_sample_solution_part_points(socket.assigns.exam, part_id, points) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:exam, updated)
             |> update_part_view(part_id, %{max_points: points})}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Punkte konnten nicht gespeichert werden.")}
        end
    end
  end

  defp part_view(socket, part_id),
    do: Enum.find(socket.assigns.part_views, &(&1.id == part_id))

  # Merges `changes` into the matching part view. Deliberately never touches
  # `doc_json` — see build_part_views/1.
  defp update_part_view(socket, part_id, changes) do
    part_views =
      Enum.map(socket.assigns.part_views, fn pv ->
        if pv.id == part_id, do: Map.merge(pv, changes), else: pv
      end)

    assign(socket, :part_views, part_views)
  end

  defp tab_label("inhalt"), do: "Inhalt"
  defp tab_label("musterloesung"), do: "Musterlösung"

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
end
