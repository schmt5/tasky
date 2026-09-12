defmodule TaskyWeb.ExamLive.GradingConfig do
  @moduledoc """
  Wie wird benotet: das Notenraster und die Maximalpunkte.

  Doppelrolle wie `ExamLive.CockpitConfig`. Beim ersten Mal ist sie der
  Zwischenschritt in die Benotung — `ExamLive.Grading` schickt jede Prüfung
  ohne gewähltes Raster hierher, damit die Lehrperson einmal entscheidet,
  statt die 0.25er-Schritte als Gegebenheit vorzufinden. Danach ist dieselbe
  Seite die Konfiguration, erreichbar über den Kopf der Benotungstabelle.

  Das Raster wird erst auf Klick auf den Button geschrieben, nicht schon beim
  Anwählen des Radios: `Exams.set_mark_step/3` rundet bestehende manuelle
  Noten mit, und das soll an einem Speichern hängen und nicht am Durchklicken
  der Optionen.
  """
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.Grading
  alias TaskyWeb.ExamComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={@crumbs} />
          </div>
          <div class="flex items-center gap-3 mb-3">
            <.back_button navigate={@back_to} tooltip={@back_tooltip} />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              {@heading}
            </h1>
          </div>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <div class="max-w-3xl">
          <ExamComponents.max_points_card
            value={@effective_max_points}
            sample_solution_total={@sample_solution_total}
            free_document={@free_document}
          />
        </div>

        <%!-- Mark step card --%>
        <div class="max-w-3xl bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6 border-b border-stone-100">
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 rounded-xl bg-sky-50 flex items-center justify-center shrink-0">
                <.icon name="hero-academic-cap" class="w-5 h-5 text-sky-500" />
              </div>
              <div>
                <h2 class="text-lg font-semibold text-stone-800">Notenschritte</h2>
                <p class="text-sm text-stone-500">In welchen Schritten du Noten setzt</p>
              </div>
            </div>
          </div>

          <div class="p-6 space-y-4">
            <div class="space-y-2">
              <label
                :for={{value, title, hint} <- mark_step_options()}
                class="flex items-start gap-3 cursor-pointer"
              >
                <input
                  type="radio"
                  name="mark_step"
                  value={value}
                  checked={@selected_step == value}
                  phx-click="select_step"
                  phx-value-step={value}
                  class="mt-0.5 w-[18px] h-[18px] border-stone-300 text-sky-500 focus:ring-sky-500/30 focus:ring-offset-0 cursor-pointer shrink-0"
                />
                <span class="min-w-0">
                  <span class="block text-sm font-medium text-stone-700">{title}</span>
                  <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                    {hint}
                  </span>
                </span>
              </label>
            </div>
          </div>
        </div>

        <div class="max-w-3xl flex items-center justify-between">
          <.link
            navigate={@back_to}
            class="text-sm font-semibold text-stone-500 hover:text-stone-700 transition-colors"
          >
            ← {@back_tooltip}
          </.link>
          <%= if @pending? do %>
            <button
              type="button"
              id="start-grading-btn"
              phx-click="save"
              class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-xl shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
            >
              <.icon name="hero-academic-cap" class="w-4 h-4" /> Benotung starten
            </button>
          <% else %>
            <button
              type="button"
              id="save-grading-config-btn"
              phx-click="save"
              disabled={@selected_step == @exam.mark_step}
              class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-xl shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-40 disabled:cursor-not-allowed disabled:shadow-none disabled:hover:bg-sky-500 disabled:active:scale-100"
            >
              <.icon name="hero-check" class="w-4 h-4" /> Speichern
            </button>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @doc """
  Die Notenraster zur Auswahl, gröbstes zuerst. Die Werte kommen aus
  `Grading.mark_steps/0`, damit hier nicht eine zweite Liste steht, die vom
  Rundungscode abweichen kann.
  """
  def mark_step_options do
    Enum.map(Grading.mark_steps(), &{&1, step_title(&1), step_hint(&1)})
  end

  defp step_title("0.25"), do: "Viertelnoten (4.25, 4.5, 4.75)"
  defp step_title("0.1"), do: "Zehntelnoten (4.7, 4.8, 4.9)"

  defp step_hint("0.25"),
    do: "Die Schritte der Note sind 0.25."

  defp step_hint("0.1"),
    do: "Die Schritte der Note sind 0.1."

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)
    sample_solution_total = Grading.sum_points(exam.sample_solution_points)

    {:ok,
     socket
     |> assign(:exam, exam)
     |> assign(:pending?, not Exams.mark_step_configured?(exam))
     |> assign(:selected_step, Exams.mark_step(exam))
     |> assign(:free_document, Exams.free_document?(exam))
     |> assign(:sample_solution_total, sample_solution_total)
     |> assign(:effective_max_points, exam.grading_max_points || sample_solution_total)
     |> assign_chrome()}
  end

  # Erstaufruf ist der Zwischenschritt in die Benotung, danach ist es die
  # Konfiguration dazu — dieselbe Achse wie bei CockpitConfig.
  defp assign_chrome(socket) do
    exam = socket.assigns.exam

    if socket.assigns.pending? do
      socket
      |> assign(:page_title, exam.name <> " – Benotung")
      |> assign(:heading, "Benotung")
      |> assign(:back_to, ~p"/exams/#{exam}/correction")
      |> assign(:back_tooltip, "Zurück zur Korrektur")
      |> assign(:crumbs, [
        %{label: "Prüfungen", navigate: ~p"/exams"},
        %{label: exam.name, navigate: ~p"/exams/#{exam}"},
        %{label: "Korrektur", navigate: ~p"/exams/#{exam}/correction"},
        %{label: "Benotung"}
      ])
    else
      socket
      |> assign(:page_title, exam.name <> " – Benotungskonfiguration")
      |> assign(:heading, "Konfiguration")
      |> assign(:back_to, ~p"/exams/#{exam}/correction/grading")
      |> assign(:back_tooltip, "Zurück zur Benotung")
      |> assign(:crumbs, [
        %{label: "Prüfungen", navigate: ~p"/exams"},
        %{label: exam.name, navigate: ~p"/exams/#{exam}"},
        %{label: "Benotung", navigate: ~p"/exams/#{exam}/correction/grading"},
        %{label: "Konfiguration"}
      ])
    end
  end

  @impl true
  def handle_event("select_step", %{"step" => step}, socket) do
    # Whitelist gegen Grading.mark_steps/0: Client-Params dürfen nie
    # ungeprüft in einen Assign wandern, aus dem sie gespeichert werden.
    if Grading.mark_step?(step) do
      {:noreply, assign(socket, :selected_step, step)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save", _params, socket) do
    %{current_scope: scope, exam: exam, selected_step: step} = socket.assigns

    case Exams.set_mark_step(scope, exam, step) do
      {:ok, updated, rounded} ->
        {:noreply, after_save(socket, updated, rounded)}

      {:error, :invalid_mark_step} ->
        {:noreply, put_flash(socket, :error, "Unbekannte Notenschritte.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Notenschritte konnten nicht gespeichert werden.")}
    end
  end

  def handle_event("set_max_points", %{"max_points" => raw}, socket) do
    save_max_points(socket, Grading.parse_points(raw))
  end

  def handle_event("adjust_max_points", %{"direction" => dir}, socket) do
    delta = if dir == "up", do: 0.25, else: -0.25
    # Gleicher Boden wie in der Benotungstabelle: 0 Maximalpunkte hiesse
    # «keine Note für niemanden».
    new_value = max((socket.assigns.effective_max_points || 0) + delta, 0.25)
    save_max_points(socket, new_value)
  end

  defp after_save(socket, updated, rounded) do
    if socket.assigns.pending? do
      socket
      |> put_flash(:info, "Benotung in #{updated.mark_step}er-Schritten.")
      |> push_navigate(to: ~p"/exams/#{updated}/correction/grading")
    else
      socket
      |> assign(:exam, updated)
      |> assign(:selected_step, updated.mark_step)
      |> put_flash(:info, saved_message(updated, rounded))
    end
  end

  defp saved_message(exam, 0), do: "Notenschritte auf #{exam.mark_step} gesetzt."

  defp saved_message(exam, rounded),
    do:
      "Notenschritte auf #{exam.mark_step} gesetzt. " <>
        "#{rounded} #{note_word(rounded)} wurde#{plural_n(rounded)} auf das neue Raster gerundet."

  defp note_word(1), do: "Note"
  defp note_word(_), do: "Noten"

  defp plural_n(1), do: ""
  defp plural_n(_), do: "n"

  defp save_max_points(socket, value) do
    case Exams.update_grading_max_points(socket.assigns.current_scope, socket.assigns.exam, value) do
      {:ok, updated_exam} ->
        # Den effektiven Wert aus der Prüfung zurücklesen, nicht aus dem Feld:
        # der Kontext rundet, was er speichert.
        {:noreply,
         socket
         |> assign(:exam, updated_exam)
         |> assign(
           :effective_max_points,
           updated_exam.grading_max_points || socket.assigns.sample_solution_total
         )}

      {:error, :invalid_max_points} ->
        {:noreply, put_flash(socket, :error, "Maximalpunkte müssen grösser als 0 sein.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Maximalpunkte konnten nicht gespeichert werden.")}
    end
  end
end
