defmodule TaskyWeb.ExamLive.CorrectionConfig do
  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-4xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Korrektur", navigate: ~p"/exams/#{@exam}/correction"},
              %{label: "Konfiguration"}
            ]} />
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Automatische Korrektur
          </h1>
          <p class="text-sm text-stone-500">
            Konfigurieren Sie für jede Aufgabe, ob sie automatisch korrigiert werden soll.
          </p>
        </div>
      </div>

      <div class="max-w-4xl mx-auto px-8 pb-8">
        <%= if @parts == [] do %>
          <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-12 text-center text-stone-400">
            <.icon name="hero-document" class="w-10 h-10 mx-auto mb-3 text-stone-300" />
            <p class="text-sm font-medium">Keine Aufgaben vorhanden.</p>
          </div>
        <% else %>
          <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
            <div class="overflow-x-auto">
              <table class="w-full text-left">
                <%!-- Header Row --%>
                <thead class="bg-stone-50 border-b border-stone-100">
                  <tr>
                    <th class="px-6 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide w-1/2">
                      Aufgaben
                    </th>
                    <th class="px-6 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide">
                      <div class="flex items-center gap-1.5">
                        <span>Automatisch korrigieren</span>
                        <button
                          type="button"
                          phx-click="show_info"
                          phx-value-topic="auto_correct"
                          class="inline-flex items-center justify-center w-5 h-5 rounded-full text-stone-400 hover:text-stone-600 hover:bg-stone-200 transition-colors duration-150 cursor-pointer"
                          title="Info"
                        >
                          <.icon name="hero-information-circle" class="w-4 h-4" />
                        </button>
                      </div>
                    </th>
                    <th class="px-6 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide">
                      <div class="flex items-center gap-1.5">
                        <span>Rechtschreibung ignorieren</span>
                        <button
                          type="button"
                          phx-click="show_info"
                          phx-value-topic="ignore_spelling"
                          class="inline-flex items-center justify-center w-5 h-5 rounded-full text-stone-400 hover:text-stone-600 hover:bg-stone-200 transition-colors duration-150 cursor-pointer"
                          title="Info"
                        >
                          <.icon name="hero-information-circle" class="w-4 h-4" />
                        </button>
                      </div>
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-stone-100">
                  <%!-- Batch Row --%>
                  <tr class="bg-stone-50/50">
                    <td class="px-6 py-3">
                      <span class="text-sm font-medium text-stone-400 italic">Alle Aufgaben</span>
                    </td>
                    <td class="px-6 py-3">
                      <label class="inline-flex items-center cursor-pointer group">
                        <input
                          type="checkbox"
                          checked={all_checked?(@config, @parts, "auto_correct")}
                          phx-click="toggle_all_auto_correct"
                          class="w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150"
                        />
                      </label>
                    </td>
                    <td class="px-6 py-3">
                      <label class={[
                        "inline-flex items-center group",
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
                    </td>
                  </tr>
                  <%!-- Per-Part Rows --%>
                  <tr
                    :for={part <- @parts}
                    class="hover:bg-stone-50/50 transition-colors duration-100"
                  >
                    <td class="px-6 py-3">
                      <div class="flex items-center gap-2.5">
                        <div class="w-7 h-7 rounded-lg bg-gradient-to-br from-amber-400 to-orange-500 flex items-center justify-center text-white text-xs font-bold shadow-sm shrink-0">
                          {part_index(@parts, part)}
                        </div>
                        <span class="text-sm font-medium text-stone-800">{part.label}</span>
                      </div>
                    </td>
                    <td class="px-6 py-3">
                      <label class="inline-flex items-center cursor-pointer group">
                        <input
                          type="checkbox"
                          checked={part_flag(@config, part.id, "auto_correct")}
                          phx-click="toggle_auto_correct"
                          phx-value-part-id={part.id}
                          class="w-[18px] h-[18px] rounded-md border-stone-300 text-amber-500 focus:ring-amber-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150"
                        />
                      </label>
                    </td>
                    <td class="px-6 py-3">
                      <label class={[
                        "inline-flex items-center group",
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
                </tbody>
              </table>
            </div>
          </div>
        <% end %>
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
    parts = Exams.split_content_into_parts(exam.content || %{})
    config = exam.ai_correction_config || %{}

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Korrektur-Konfiguration")
     |> assign(:exam, exam)
     |> assign(:parts, parts)
     |> assign(:config, config)
     |> assign(:show_info_modal, nil)}
  end

  @impl true
  def handle_event("toggle_auto_correct", %{"part-id" => part_id}, socket) do
    {:noreply, toggle_part_flag(socket, part_id, "auto_correct")}
  end

  def handle_event("toggle_ignore_spelling", %{"part-id" => part_id}, socket) do
    {:noreply, toggle_part_flag(socket, part_id, "ignore_spelling")}
  end

  def handle_event("toggle_all_auto_correct", _params, socket) do
    {:noreply, toggle_all_flag(socket, "auto_correct")}
  end

  def handle_event("toggle_all_ignore_spelling", _params, socket) do
    {:noreply, toggle_all_flag(socket, "ignore_spelling")}
  end

  def handle_event("show_info", %{"topic" => topic}, socket) do
    {:noreply, assign(socket, :show_info_modal, topic)}
  end

  def handle_event("close_info_modal", _params, socket) do
    {:noreply, assign(socket, :show_info_modal, nil)}
  end

  defp toggle_part_flag(socket, part_id, key) do
    config = socket.assigns.config
    current_val = part_flag(config, part_id, key)
    new_val = !current_val

    part_config = Map.get(config, part_id, %{})
    updated_part_config = Map.put(part_config, key, new_val)

    # When disabling auto_correct, also reset ignore_spelling
    updated_part_config =
      if key == "auto_correct" and new_val == false do
        Map.put(updated_part_config, "ignore_spelling", false)
      else
        updated_part_config
      end

    {:ok, updated_exam} =
      Exams.update_ai_correction_config(socket.assigns.exam, part_id, updated_part_config)

    socket
    |> assign(:exam, updated_exam)
    |> assign(:config, updated_exam.ai_correction_config || %{})
  end

  defp toggle_all_flag(socket, key) do
    config = socket.assigns.config
    parts = socket.assigns.parts
    new_val = !all_checked?(config, parts, key)

    updates =
      Map.new(parts, fn part ->
        part_config = Map.get(config, part.id, %{})
        updated = Map.put(part_config, key, new_val)

        # When disabling all auto_correct, also reset ignore_spelling for each part
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

    socket
    |> assign(:exam, updated_exam)
    |> assign(:config, updated_exam.ai_correction_config || %{})
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

  defp part_index(parts, part) do
    case Enum.find_index(parts, &(&1.id == part.id)) do
      nil -> "?"
      idx -> idx + 1
    end
  end

  defp info_modal_icon("auto_correct"), do: "hero-sparkles"
  defp info_modal_icon("ignore_spelling"), do: "hero-language"
  defp info_modal_icon(_), do: "hero-information-circle"

  defp info_modal_title("auto_correct"), do: "Automatisch korrigieren"
  defp info_modal_title("ignore_spelling"), do: "Rechtschreibung ignorieren"
  defp info_modal_title(_), do: "Information"
end
