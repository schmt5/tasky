defmodule TaskyWeb.ExamLive.Grading do
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
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Korrektur", navigate: ~p"/exams/#{@exam}/correction"},
              %{label: "Benotung"}
            ]} />
          </div>

          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3 mb-3">
              <.back_button
                navigate={~p"/exams/#{@exam}/correction"}
                tooltip="Zurück zur Korrektur"
              />
              <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
                Benotung
              </h1>
            </div>

            <%= if @pdf_enabled do %>
              <button
                type="button"
                phx-click="open_export_modal"
                disabled={@submissions == []}
                class="inline-flex items-center gap-2 text-sm font-semibold text-stone-700 bg-white border border-stone-200 hover:bg-stone-50 hover:border-stone-300 px-4 py-2.5 rounded-lg transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed"
              >
                <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Exportieren
              </button>
            <% else %>
              <div class="tooltip tooltip-bottom tooltip-delayed" data-tip="PDF-Dienst nicht verfügbar">
                <button
                  type="button"
                  disabled
                  class="inline-flex items-center gap-2 text-sm font-semibold text-stone-400 bg-stone-100 border border-stone-200 px-4 py-2.5 rounded-lg cursor-not-allowed"
                >
                  <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Exportieren
                </button>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-4">
        <%!-- Max points config (inline, body) --%>
        <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-5 flex items-center gap-6">
          <div class="w-10 h-10 rounded-[10px] bg-sky-50 flex items-center justify-center shrink-0">
            <.icon name="hero-calculator" class="w-5 h-5 text-sky-500" />
          </div>
          <div class="flex-1">
            <h2 class="text-sm font-semibold text-stone-800">Maximalpunkte für Benotung</h2>
            <p class="text-xs text-stone-500 mt-0.5">
              Standardwert: Summe aller Musterlösungs-Punkte ({format_points(
                @sample_solution_total
              )}). Kann hier angepasst werden, z.B. wenn nicht alle Teile gewertet werden.
            </p>
          </div>
          <div class="shrink-0 inline-flex items-center gap-2">
            <button
              type="button"
              phx-click="adjust_max_points"
              phx-value-direction="down"
              disabled={@effective_max_points <= 0}
              class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
              title="−0.25"
            >
              <.icon name="hero-minus" class="w-4 h-4" />
            </button>
            <form phx-change="set_max_points" phx-submit="set_max_points">
              <input
                id="grading-max-points-input"
                type="number"
                name="max_points"
                value={@effective_max_points}
                step="0.25"
                min="0"
                inputmode="decimal"
                phx-debounce="500"
                class="w-24 font-mono text-base text-right text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-4 focus:ring-sky-600 focus:ring-offset-2"
              />
            </form>
            <button
              type="button"
              phx-click="adjust_max_points"
              phx-value-direction="up"
              class="inline-flex items-center justify-center w-8 h-8 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150"
              title="+0.25"
            >
              <.icon name="hero-plus" class="w-4 h-4" />
            </button>
            <span class="text-sm text-stone-500 ml-1">Punkte</span>
          </div>
        </div>

        <%!-- Table --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <%= if @submissions == [] do %>
            <div class="p-12 text-center text-stone-400">
              <.icon name="hero-user-group" class="w-10 h-10 mx-auto mb-3 text-stone-300" />
              <p class="text-sm font-medium">Keine Teilnehmenden vorhanden.</p>
            </div>
          <% else %>
            <table class="w-full text-left border-collapse">
              <thead class="bg-stone-50 border-b border-stone-100">
                <tr>
                  <th class="px-6 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide">
                    Lernende:r
                  </th>
                  <th class="px-4 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide text-right">
                    Punkte
                  </th>
                  <th class="px-4 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide text-right">
                    Berechnete Note
                  </th>
                  <th class="px-4 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide text-right">
                    Note
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-stone-100">
                <tr :for={row <- @rows} class="hover:bg-stone-50/50">
                  <td class="px-6 py-3">
                    <div class="flex items-center gap-3">
                      <div class="w-9 h-9 rounded-full bg-gradient-to-br from-blue-400 to-indigo-500 flex items-center justify-center text-white text-sm font-bold shadow-sm shrink-0">
                        {String.first(row.submission.firstname)}{String.first(
                          row.submission.lastname
                        )}
                      </div>
                      <span class="text-sm font-semibold text-stone-800">
                        {row.submission.firstname} {row.submission.lastname}
                      </span>
                    </div>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <span class="font-mono text-sm font-semibold text-stone-700">
                      {format_points(row.points)}
                      <span class="text-stone-400 font-normal">
                        / {format_points(@effective_max_points)}
                      </span>
                    </span>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <span class={[
                      "font-mono text-sm font-semibold tabular-nums",
                      mark_color_class(row.calculated_mark)
                    ]}>
                      {format_mark(row.calculated_mark)}
                    </span>
                  </td>
                  <td class="px-4 py-3">
                    <.mark_stepper row={row} />
                  </td>
                </tr>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>

      <%!-- Export modal --%>
      <%= if @show_export_modal do %>
        <dialog
          id="export-modal"
          class="modal modal-open"
          phx-window-keydown="close_export_modal"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_export_modal"></div>
          <div class="modal-box max-w-lg p-0 bg-white rounded-[16px] shadow-2xl">
            <div class="px-6 py-5 border-b border-stone-100 flex items-center justify-between">
              <div class="flex items-center gap-3">
                <div class="w-9 h-9 rounded-xl bg-sky-50 flex items-center justify-center text-sky-600">
                  <.icon name="hero-arrow-down-tray" class="w-5 h-5" />
                </div>
                <h3 class="text-lg font-semibold text-stone-900">Exportieren als PDF</h3>
              </div>
              <button
                type="button"
                phx-click="close_export_modal"
                class="inline-flex items-center justify-center w-8 h-8 rounded-lg text-stone-400 hover:text-stone-600 hover:bg-stone-100 transition-colors duration-150 cursor-pointer"
              >
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <div class="px-6 py-5 space-y-4">
              <p class="text-sm text-stone-500">
                Erstellt eine PDF pro Teilnehmer:in und packt alles in eine ZIP-Datei.
              </p>

              <.export_checkbox
                option="show_content"
                checked={@export_options.show_content}
                label="Inhalt anzeigen"
                description="Die Antworten der Teilnehmer:in werden vollständig im PDF abgebildet."
              />

              <.export_checkbox
                option="show_correction"
                checked={@export_options.show_correction}
                disabled={not @export_options.show_content}
                label="Korrektur anzeigen"
                description="Markiert jeden Antwortblock mit einem 🟢 (richtig), 🟡 (halb richtig) oder 🔴 (falsch) Emoji. Nur verfügbar, wenn Inhalt angezeigt wird."
              />

              <.export_checkbox
                option="show_sample_solution"
                checked={@export_options.show_sample_solution}
                label="Musterlösung anzeigen"
                description="Hängt die vollständige Musterlösung im Anschluss an."
              />
            </div>

            <div class="px-6 py-4 border-t border-stone-100 flex items-center justify-end gap-2">
              <button
                type="button"
                phx-click="close_export_modal"
                class="px-4 py-2 text-sm font-medium text-stone-600 bg-stone-100 rounded-lg hover:bg-stone-200 transition-colors duration-150"
              >
                Abbrechen
              </button>
              <button
                type="button"
                phx-click="start_export"
                class="inline-flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-sky-500 hover:bg-sky-600 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-colors duration-150"
              >
                <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Exportieren
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <%!-- Export progress overlay --%>
      <%= if @export_status do %>
        <div
          id="export-overlay"
          class="fixed inset-0 z-50 bg-stone-900/50 flex items-center justify-center"
        >
          <div class="bg-white rounded-[16px] shadow-2xl p-6 w-full max-w-md mx-4">
            <h3 class="text-lg font-semibold text-stone-900 mb-1">PDFs werden erstellt …</h3>
            <p class="text-sm text-stone-500 mb-4 tabular-nums">
              <span class="font-semibold text-stone-700">{@export_status.done}</span>
              von <span class="font-semibold text-stone-700">{@export_status.total}</span>
              Teilnehmer:innen verarbeitet
            </p>
            <div class="h-2 bg-stone-100 rounded-full overflow-hidden">
              <div
                class="h-full bg-gradient-to-r from-sky-500 to-indigo-500 transition-all duration-500"
                style={"width: #{export_percent(@export_status)}%"}
              >
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  attr :option, :string, required: true
  attr :checked, :boolean, required: true
  attr :disabled, :boolean, default: false
  attr :label, :string, required: true
  attr :description, :string, required: true

  defp export_checkbox(assigns) do
    ~H"""
    <label class={[
      "flex items-start gap-3 p-3 rounded-lg border transition-colors duration-150",
      if(@disabled,
        do: "border-stone-100 bg-stone-50/50 cursor-not-allowed opacity-60",
        else: "border-stone-200 hover:bg-stone-50/60 cursor-pointer"
      )
    ]}>
      <input
        type="checkbox"
        checked={@checked}
        disabled={@disabled}
        phx-click="toggle_export_option"
        phx-value-option={@option}
        class="w-[18px] h-[18px] mt-0.5 rounded-md border-stone-300 text-sky-500 focus:ring-sky-500/30 focus:ring-offset-0 cursor-pointer disabled:cursor-not-allowed"
      />
      <div class="flex-1 min-w-0">
        <p class="text-sm font-semibold text-stone-800">{@label}</p>
        <p class="text-xs text-stone-500 mt-0.5 leading-relaxed">{@description}</p>
      </div>
    </label>
    """
  end

  attr :row, :map, required: true

  defp mark_stepper(assigns) do
    assigns =
      assign(assigns,
        can_dec: not is_nil(assigns.row.effective_mark) and assigns.row.effective_mark > 1.0,
        can_inc: not is_nil(assigns.row.effective_mark) and assigns.row.effective_mark < 6.0
      )

    ~H"""
    <div class="inline-flex items-center justify-end gap-1.5 w-full">
      <button
        type="button"
        phx-click="adjust_mark"
        phx-value-submission-id={@row.submission.id}
        phx-value-direction="down"
        disabled={not @can_dec}
        class="inline-flex items-center justify-center w-7 h-7 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
        title="−0.25"
      >
        <.icon name="hero-minus" class="w-3.5 h-3.5" />
      </button>
      <form
        phx-change="set_mark"
        phx-submit="set_mark"
        class="inline-flex"
      >
        <input type="hidden" name="submission_id" value={@row.submission.id} />
        <input
          type="number"
          name="mark"
          value={format_mark(@row.effective_mark)}
          step="0.25"
          min="1"
          max="6"
          inputmode="decimal"
          phx-debounce="500"
          class="w-16 font-mono text-sm font-semibold text-center text-stone-700 bg-stone-50 border border-stone-200 rounded-md px-1.5 py-1 focus:outline-none focus:ring-4 focus:ring-sky-600 focus:ring-offset-2"
        />
      </form>
      <button
        type="button"
        phx-click="adjust_mark"
        phx-value-submission-id={@row.submission.id}
        phx-value-direction="up"
        disabled={not @can_inc}
        class="inline-flex items-center justify-center w-7 h-7 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
        title="+0.25"
      >
        <.icon name="hero-plus" class="w-3.5 h-3.5" />
      </button>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    submissions = load_sorted_submissions(exam)
    sample_solution_total = sum_sample_solution_points(exam)
    effective_max_points = exam.grading_max_points || sample_solution_total

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Benotung")
     |> assign(:exam, exam)
     |> assign(:submissions, submissions)
     |> assign(:sample_solution_total, sample_solution_total)
     |> assign(:effective_max_points, effective_max_points)
     |> assign(:rows, build_rows(submissions, effective_max_points))
     |> assign(:pdf_enabled, Tasky.PDF.Gotenberg.enabled?())
     |> assign(:show_export_modal, false)
     |> assign(:export_options, %{
       show_content: true,
       show_correction: false,
       show_sample_solution: false
     })
     |> assign(:export_status, nil)}
  end

  @impl true
  def handle_event("set_max_points", %{"max_points" => raw}, socket) do
    save_max_points(socket, parse_points(raw))
  end

  def handle_event("adjust_max_points", %{"direction" => dir}, socket) do
    delta = if dir == "up", do: 0.25, else: -0.25
    new_value = max((socket.assigns.effective_max_points || 0) + delta, 0)
    save_max_points(socket, new_value)
  end

  def handle_event("set_mark", %{"submission_id" => sub_id, "mark" => raw}, socket) do
    save_mark(socket, sub_id, parse_mark(raw))
  end

  def handle_event(
        "adjust_mark",
        %{"submission-id" => sub_id, "direction" => dir},
        socket
      ) do
    row = Enum.find(socket.assigns.rows, &(to_string(&1.submission.id) == to_string(sub_id)))

    if is_nil(row) or is_nil(row.effective_mark) do
      {:noreply, socket}
    else
      delta = if dir == "up", do: 0.25, else: -0.25
      new_mark = row.effective_mark + delta
      save_mark(socket, sub_id, new_mark |> round_to_quarter() |> clamp_mark())
    end
  end

  def handle_event("open_export_modal", _params, socket) do
    {:noreply, assign(socket, :show_export_modal, true)}
  end

  def handle_event("close_export_modal", _params, socket) do
    {:noreply, assign(socket, :show_export_modal, false)}
  end

  def handle_event("toggle_export_option", %{"option" => option}, socket) do
    key = String.to_existing_atom(option)
    current = socket.assigns.export_options
    updated = Map.put(current, key, not Map.fetch!(current, key))

    # show_correction requires show_content; clear it if content is turned off.
    updated =
      if updated.show_content,
        do: updated,
        else: Map.put(updated, :show_correction, false)

    {:noreply, assign(socket, :export_options, updated)}
  end

  def handle_event("start_export", _params, socket) do
    opts = socket.assigns.export_options
    user_id = socket.assigns.current_scope.user.id
    endpoint = socket.endpoint

    case Tasky.Exams.ExportRunner.start(
           socket.assigns.exam,
           socket.assigns.submissions,
           opts,
           self(),
           user_id,
           endpoint
         ) do
      {:ok, _pid} ->
        {:noreply,
         socket
         |> assign(:show_export_modal, false)
         |> assign(:export_status, %{done: 0, total: length(socket.assigns.submissions)})}

      {:error, :gotenberg_not_configured} ->
        {:noreply,
         socket
         |> assign(:show_export_modal, false)
         |> put_flash(:error, "PDF-Dienst (Gotenberg) ist nicht konfiguriert.")}

      {:error, :callback_url_not_configured} ->
        {:noreply,
         socket
         |> assign(:show_export_modal, false)
         |> put_flash(:error, "GOTENBERG_CALLBACK_URL ist nicht gesetzt.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:show_export_modal, false)
         |> put_flash(:error, "Export konnte nicht gestartet werden: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:export_progress, %{done: done, total: total}}, socket) do
    {:noreply, assign(socket, :export_status, %{done: done, total: total})}
  end

  def handle_info({:export_done, %{download_token: token, filename: filename}}, socket) do
    url = ~p"/exports/download?token=#{token}"

    {:noreply,
     socket
     |> assign(:export_status, nil)
     |> put_flash(:info, "Export bereit: #{filename}")
     |> push_event("download-file", %{url: url})}
  end

  def handle_info({:export_failed, reason}, socket) do
    {:noreply,
     socket
     |> assign(:export_status, nil)
     |> put_flash(:error, "Export fehlgeschlagen: #{inspect(reason)}")}
  end

  # Ignore stray DOWN messages from the Task (async_nolink).
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp save_max_points(socket, value) do
    case Exams.update_grading_max_points(socket.assigns.exam, value) do
      {:ok, updated_exam} ->
        effective = value || socket.assigns.sample_solution_total

        {:noreply,
         socket
         |> assign(:exam, updated_exam)
         |> assign(:effective_max_points, effective)
         |> assign(:rows, build_rows(socket.assigns.submissions, effective))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Maximalpunkte konnten nicht gespeichert werden.")}
    end
  end

  defp save_mark(socket, sub_id, mark) do
    submission = Enum.find(socket.assigns.submissions, &(to_string(&1.id) == to_string(sub_id)))

    if is_nil(submission) do
      {:noreply, socket}
    else
      case Exams.set_submission_mark(submission, mark) do
        {:ok, updated} ->
          submissions =
            Enum.map(socket.assigns.submissions, fn s ->
              if s.id == updated.id, do: updated, else: s
            end)

          {:noreply,
           socket
           |> assign(:submissions, submissions)
           |> assign(:rows, build_rows(submissions, socket.assigns.effective_max_points))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Note konnte nicht gespeichert werden.")}
      end
    end
  end

  defp build_rows(submissions, max_points) do
    Enum.map(submissions, fn s ->
      points = total_points(s)
      calculated = calculate_mark(points, max_points)
      effective_mark = s.mark || calculated

      %{
        submission: s,
        points: points,
        calculated_mark: calculated,
        effective_mark: effective_mark
      }
    end)
  end

  defp total_points(submission) do
    (submission.points_per_part || %{})
    |> Map.values()
    |> Enum.reduce(0, fn
      v, acc when is_number(v) -> acc + v
      _, acc -> acc
    end)
  end

  defp sum_sample_solution_points(exam) do
    (exam.sample_solution_points || %{})
    |> Map.values()
    |> Enum.reduce(0, fn
      v, acc when is_number(v) -> acc + v
      _, acc -> acc
    end)
  end

  # Swiss 1–6 scale: 0 points → 1, max points → 6.
  # Result is rounded to the nearest 0.25 and clamped to [1.0, 6.0].
  defp calculate_mark(_points, max) when max in [nil, 0, 0.0], do: nil

  defp calculate_mark(points, max) when is_number(points) and is_number(max) do
    raw = points / max * 5 + 1
    raw |> round_to_quarter() |> clamp_mark()
  end

  defp calculate_mark(_, _), do: nil

  defp round_to_quarter(n), do: Float.round(n * 4) / 4

  defp clamp_mark(n) when n < 1.0, do: 1.0
  defp clamp_mark(n) when n > 6.0, do: 6.0
  defp clamp_mark(n), do: n

  defp format_mark(nil), do: ""

  defp format_mark(n) when is_number(n) do
    n = n * 1.0

    cond do
      n == trunc(n) -> :erlang.float_to_binary(n, decimals: 1)
      true -> :erlang.float_to_binary(n, decimals: 2)
    end
  end

  defp format_points(nil), do: "—"
  defp format_points(0), do: "0"
  defp format_points(n) when is_integer(n), do: Integer.to_string(n)

  defp format_points(n) when is_float(n) do
    if n == trunc(n),
      do: Integer.to_string(trunc(n)),
      else: :erlang.float_to_binary(n, decimals: 1)
  end

  defp export_percent(%{total: 0}), do: 0
  defp export_percent(%{done: done, total: total}), do: round(done * 100 / total)

  defp mark_color_class(nil), do: "text-stone-400"
  defp mark_color_class(n) when n >= 5.5, do: "text-emerald-600"
  defp mark_color_class(n) when n >= 4.0, do: "text-stone-700"
  defp mark_color_class(_), do: "text-red-600"

  defp parse_points(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        nil

      trimmed ->
        case Float.parse(trimmed) do
          {n, ""} -> n
          _ -> nil
        end
    end
  end

  defp parse_points(_), do: nil

  defp parse_mark(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        nil

      trimmed ->
        case Float.parse(trimmed) do
          {n, ""} -> n |> round_to_quarter() |> clamp_mark()
          _ -> nil
        end
    end
  end

  defp parse_mark(_), do: nil

  defp load_sorted_submissions(exam) do
    exam
    |> Exams.list_exam_submissions()
    |> Enum.sort_by(fn s ->
      {String.downcase(s.firstname || ""), String.downcase(s.lastname || "")}
    end)
  end
end
