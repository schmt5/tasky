defmodule TaskyWeb.ExamLive.Grading do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.Grading
  alias TaskyWeb.ExamComponents
  alias TaskyWeb.ExamSubmissionView

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

            <div class="flex items-center gap-3">
              <%= if @assigned_mode? and @returned? do %>
                <span class="inline-flex items-center gap-1.5 bg-sky-100 text-sky-700 text-[13px] font-semibold px-3 py-1.5 rounded-full">
                  <.icon name="hero-arrow-uturn-right" class="w-4 h-4" />
                  Zurückgegeben am {Calendar.strftime(@exam.returned_at, "%d.%m.%Y")}
                </span>
                <button
                  type="button"
                  id="withdraw-return-btn"
                  phx-click="withdraw_return"
                  data-confirm="Die Teilnehmenden verlieren damit den Zugriff auf ihre korrigierte Prüfung. Rückgabe wirklich zurückziehen?"
                  class="inline-flex items-center gap-2 text-sm font-semibold text-stone-600 bg-white border border-stone-200 hover:bg-stone-50 hover:border-stone-300 px-4 py-2.5 rounded-lg transition-colors duration-150"
                >
                  <.icon name="hero-arrow-uturn-left" class="w-4 h-4" /> Rückgabe zurückziehen
                </button>
              <% end %>

              <.link
                id="grading-config-btn"
                navigate={~p"/exams/#{@exam}/correction/grading/config"}
                class="inline-flex items-center gap-2 text-sm font-semibold text-stone-700 bg-white border border-stone-200 hover:bg-stone-50 hover:border-stone-300 px-4 py-2.5 rounded-lg transition-colors duration-150"
              >
                <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Konfigurieren
              </.link>

              <button
                type="button"
                id="open-export-modal-btn"
                phx-click="open_export_modal"
                disabled={@submissions == []}
                class="inline-flex items-center gap-2 text-sm font-semibold text-stone-700 bg-white border border-stone-200 hover:bg-stone-50 hover:border-stone-300 px-4 py-2.5 rounded-lg transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed"
              >
                <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Exportieren
              </button>

              <%= if @assigned_mode? and not @returned? do %>
                <button
                  type="button"
                  id="open-return-modal-btn"
                  phx-click="open_return_modal"
                  disabled={@submissions == []}
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-40 disabled:cursor-not-allowed disabled:shadow-none disabled:hover:bg-sky-500"
                >
                  <.icon name="hero-arrow-uturn-right" class="w-4 h-4" /> Prüfung zurückgeben
                </button>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-4">
        <.stats_card :if={@submissions != []} stats={@stats} />

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
                  <.sortable_th
                    field={:firstname}
                    label="Vorname"
                    sort={@sort}
                    exam={@exam}
                    class="px-6"
                  />
                  <.sortable_th field={:lastname} label="Nachname" sort={@sort} exam={@exam} />
                  <.sortable_th
                    field={:points}
                    label="Punkte"
                    sort={@sort}
                    exam={@exam}
                    align="right"
                  />
                  <.sortable_th
                    field={:calculated_mark}
                    label="Berechnete Note"
                    sort={@sort}
                    exam={@exam}
                    align="right"
                  />
                  <.sortable_th field={:mark} label="Note" sort={@sort} exam={@exam} align="right" />
                </tr>
              </thead>
              <tbody class="divide-y divide-stone-100">
                <tr :for={row <- @rows} class="hover:bg-stone-50/50">
                  <td class="px-6 py-3">
                    <div class="flex items-center gap-3">
                      <.participant_avatar person={row.submission} />
                      <span class="text-sm font-semibold text-stone-800">
                        {row.submission.firstname}
                      </span>
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <span class="text-sm font-semibold text-stone-800">
                      {row.submission.lastname}
                    </span>
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
                    <.mark_stepper row={row} step={@mark_step} />
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

              <ExamComponents.submission_view_option_checkbox
                :for={option <- ExamComponents.submission_view_options(@exam)}
                option={option}
                checked={Map.fetch!(@export_options, option.key)}
                disabled={option.requires && not Map.fetch!(@export_options, option.requires)}
                event="toggle_export_option"
              />
            </div>

            <div class="px-6 py-4 border-t border-stone-100 flex items-center justify-end gap-2">
              <button
                type="button"
                phx-click="close_export_modal"
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Abbrechen
              </button>
              <button
                type="button"
                id="start-export-btn"
                phx-click="start_export"
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
              >
                <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Exportieren
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <%!-- Return modal --%>
      <%= if @show_return_modal do %>
        <dialog
          id="return-modal"
          class="modal modal-open"
          phx-window-keydown="close_return_modal"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_return_modal"></div>
          <div class="modal-box max-w-lg p-0 bg-white rounded-[16px] shadow-2xl">
            <div class="px-6 py-5 border-b border-stone-100 flex items-center justify-between">
              <div class="flex items-center gap-3">
                <div class="w-9 h-9 rounded-xl bg-sky-50 flex items-center justify-center text-sky-600">
                  <.icon name="hero-arrow-uturn-right" class="w-5 h-5" />
                </div>
                <h3 class="text-lg font-semibold text-stone-900">Prüfung zurückgeben</h3>
              </div>
              <button
                type="button"
                phx-click="close_return_modal"
                class="inline-flex items-center justify-center w-8 h-8 rounded-lg text-stone-400 hover:text-stone-600 hover:bg-stone-100 transition-colors duration-150 cursor-pointer"
              >
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <div class="px-6 py-5 space-y-4">
              <p class="text-sm text-stone-500">
                Alle {length(@submissions)} Teilnehmenden sehen ihre korrigierte Prüfung danach
                auf ihrem Dashboard. Du kannst die Rückgabe jederzeit zurückziehen.
              </p>

              <ExamComponents.submission_view_option_checkbox
                :for={option <- ExamComponents.submission_view_options(@exam)}
                option={option}
                checked={Map.fetch!(@return_options, option.key)}
                disabled={option.requires && not Map.fetch!(@return_options, option.requires)}
                event="toggle_return_option"
              />
            </div>

            <div class="px-6 py-4 border-t border-stone-100 flex items-center justify-end gap-2">
              <button
                type="button"
                phx-click="close_return_modal"
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Abbrechen
              </button>
              <button
                type="button"
                id="confirm-return-btn"
                phx-click="confirm_return"
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
              >
                <.icon name="hero-arrow-uturn-right" class="w-4 h-4" /> Jetzt zurückgeben
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <%!-- Export progress overlay --%>
      <%= if @export_status do %>
        <dialog id="export-overlay" class="modal modal-open">
          <div class="modal-backdrop bg-stone-900/50"></div>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-sky-50 flex items-center justify-center shrink-0">
                  <.icon
                    name="hero-arrow-path"
                    class="w-5 h-5 text-sky-600 motion-safe:animate-spin"
                  />
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-stone-800">PDFs werden erstellt …</h3>
                  <p class="text-xs text-stone-400 mt-0.5">
                    Das Fenster schliesst sich automatisch.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6">
              <div class="flex items-center justify-between text-sm text-stone-600">
                <span>Teilnehmer:innen</span>
                <span class="font-semibold text-stone-800 tabular-nums">
                  {@export_status.done}/{@export_status.total}
                </span>
              </div>
              <div
                class="mt-3 h-2 w-full rounded-full bg-stone-100 overflow-hidden"
                role="progressbar"
                aria-valuemin="0"
                aria-valuemax={@export_status.total}
                aria-valuenow={@export_status.done}
                aria-label="Fortschritt beim Erstellen der PDFs"
              >
                <div
                  class="h-full rounded-full bg-sky-500 transition-[width] duration-300"
                  style={"width: #{export_percent(@export_status)}%"}
                >
                </div>
              </div>
            </div>
          </div>
        </dialog>
      <% end %>
    </Layouts.app>
    """
  end

  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :sort, :any, required: true, doc: "the active {field, direction} pair"
  attr :exam, :map, required: true
  attr :align, :string, default: "left", values: ~w(left right)
  attr :class, :any, default: "px-4"

  defp sortable_th(assigns) do
    {active_field, active_dir} = assigns.sort
    active? = active_field == assigns.field

    assigns =
      assigns
      |> assign(:active?, active?)
      |> assign(:dir, active_dir)
      # A click on the active column flips its direction; every other column
      # starts ascending.
      |> assign(:next_dir, if(active? and active_dir == :asc, do: :desc, else: :asc))

    ~H"""
    <th
      scope="col"
      aria-sort={aria_sort(@active?, @dir)}
      class={[
        "py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide",
        @class,
        @align == "right" && "text-right"
      ]}
    >
      <%!-- A patch link rather than phx-click: the sort lands in the URL and
           so survives a reload and a reconnect. --%>
      <.link
        id={"sort-#{@field}"}
        patch={~p"/exams/#{@exam}/correction/grading?#{[sort: @field, dir: @next_dir]}"}
        class={[
          "group inline-flex items-center gap-1 hover:text-stone-700 transition-colors duration-150",
          @align == "right" && "justify-end",
          @active? && "text-stone-700"
        ]}
      >
        {@label}
        <%!-- Both arrows always show, so every column reads as sortable
             without a hover; the active direction is the blue one. --%>
        <span class="inline-flex flex-col shrink-0 leading-none" aria-hidden="true">
          <.icon
            name="hero-chevron-up-mini"
            class={["w-4 h-4 -mb-1.5", sort_arrow_class(@active? and @dir == :asc)]}
          />
          <.icon
            name="hero-chevron-down-mini"
            class={["w-4 h-4", sort_arrow_class(@active? and @dir == :desc)]}
          />
        </span>
      </.link>
    </th>
    """
  end

  defp aria_sort(true, :desc), do: "descending"
  defp aria_sort(true, _asc), do: "ascending"
  defp aria_sort(_inactive, _dir), do: "none"

  defp sort_arrow_class(true), do: "text-sky-600"

  defp sort_arrow_class(false),
    do: "text-stone-400 group-hover:text-stone-600 transition-colors duration-150"

  attr :stats, :map, required: true, doc: "the result of Grading.mark_stats/2"

  # Key figures and the mark distribution of the class. Pure HEEx: ten bars
  # need no chart library, and the card re-renders with every changed mark.
  defp stats_card(assigns) do
    top = assigns.stats.buckets |> Enum.map(& &1.count) |> Enum.max()

    assigns =
      assigns
      |> assign(:top, top)
      |> assign(:histogram_label, histogram_label(assigns.stats.buckets))

    ~H"""
    <section
      id="grading-stats"
      aria-labelledby="grading-stats-title"
      class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-6"
    >
      <div class="flex flex-col md:flex-row gap-8">
        <div class="md:w-60 shrink-0">
          <h2
            id="grading-stats-title"
            class="text-xs font-semibold text-stone-500 uppercase tracking-wide"
          >
            Durchschnitt
          </h2>
          <p
            id="grading-stats-average"
            class={[
              "text-[52px] font-semibold leading-none mt-2 tabular-nums",
              mark_color_class(@stats.average)
            ]}
          >
            {Grading.format_mark(@stats.average)}
          </p>
          <p class="text-xs text-stone-400 mt-1.5">
            aus {@stats.graded} {if @stats.graded == 1, do: "Note", else: "Noten"}
          </p>

          <dl class="mt-5 grid grid-cols-2 gap-x-4 gap-y-3">
            <div>
              <dt class="text-xs text-stone-500">Median</dt>
              <dd class="font-mono text-sm font-semibold text-stone-800 tabular-nums">
                {Grading.format_mark(@stats.median)}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-stone-500">Genügend (≥ 4)</dt>
              <dd
                id="grading-stats-passed"
                class="font-mono text-sm font-semibold text-stone-800 tabular-nums"
              >
                {@stats.passed}/{@stats.graded}
                <span class="font-sans text-xs text-stone-400 font-normal ml-0.5">
                  {passed_percent(@stats)}
                </span>
              </dd>
            </div>
            <div>
              <dt class="text-xs text-stone-500">Tiefste</dt>
              <dd class="font-mono text-sm font-semibold text-stone-800 tabular-nums">
                {Grading.format_mark(@stats.min)}
              </dd>
            </div>
            <div>
              <dt class="text-xs text-stone-500">Höchste</dt>
              <dd class="font-mono text-sm font-semibold text-stone-800 tabular-nums">
                {Grading.format_mark(@stats.max)}
              </dd>
            </div>
          </dl>

          <p :if={@stats.ungraded > 0} class="mt-4 text-xs text-stone-400">
            {@stats.ungraded} ohne Note — nicht mitgezählt.
          </p>
        </div>

        <div class="flex-1 min-w-0">
          <div class="flex items-center justify-between gap-4">
            <h3 class="text-xs font-semibold text-stone-500 uppercase tracking-wide">
              Notenverteilung
            </h3>
            <div class="flex items-center gap-4 text-xs text-stone-500" aria-hidden="true">
              <span class="inline-flex items-center gap-1.5">
                <span class="w-2.5 h-2.5 rounded-[3px] bg-red-400"></span> unter 4
              </span>
              <span class="inline-flex items-center gap-1.5">
                <span class="w-2.5 h-2.5 rounded-[3px] bg-sky-500"></span> ab 4
              </span>
            </div>
          </div>

          <div id="mark-histogram" role="img" aria-label={@histogram_label} class="mt-4">
            <div class="flex items-end gap-0.5 h-44 border-b border-stone-200">
              <div
                :for={{bucket, idx} <- Enum.with_index(@stats.buckets)}
                id={"mark-bucket-#{idx}"}
                data-count={bucket.count}
                class="tooltip tooltip-top group flex-1 h-full pt-6 flex items-end justify-center"
                data-tip={"#{bucket_label(bucket)}: #{bucket.count} #{learner_word(bucket.count)}"}
              >
                <div
                  class={[
                    "relative w-full max-w-12 rounded-t-[4px] transition-[height,background-color] duration-300 ease-out",
                    if(bucket.from < 4.0,
                      do: "bg-red-400 group-hover:bg-red-500",
                      else: "bg-sky-500 group-hover:bg-sky-600"
                    )
                  ]}
                  style={"height: #{bar_percent(bucket.count, @top)}%"}
                >
                  <span
                    :if={bucket.count > 0}
                    class="absolute -top-5 inset-x-0 text-center text-xs font-semibold text-stone-600 tabular-nums"
                  >
                    {bucket.count}
                  </span>
                </div>
              </div>
            </div>
            <div class="flex gap-0.5 mt-2" aria-hidden="true">
              <span
                :for={bucket <- @stats.buckets}
                class="flex-1 text-center text-[11px] text-stone-500 tabular-nums whitespace-nowrap"
              >
                {Grading.format_mark(bucket.from)}<span class="hidden lg:inline">–{Grading.format_mark(bucket.to)}</span>
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp bar_percent(_count, 0), do: 0
  defp bar_percent(count, top), do: Float.round(count * 100 / top, 1)

  defp passed_percent(%{graded: 0}), do: ""

  defp passed_percent(%{passed: passed, graded: graded}),
    do: "#{round(passed * 100 / graded)} %"

  defp bucket_label(bucket),
    do: "#{Grading.format_mark(bucket.from)}–#{Grading.format_mark(bucket.to)}"

  defp learner_word(1), do: "Lernende:r"
  defp learner_word(_), do: "Lernende"

  # The bars are an image to a screen reader, so the label carries the data.
  defp histogram_label(buckets) do
    "Notenverteilung: " <>
      Enum.map_join(buckets, ", ", &"#{bucket_label(&1)}: #{&1.count}")
  end

  attr :row, :map, required: true
  attr :step, :string, required: true

  defp mark_stepper(assigns) do
    assigns =
      assign(assigns,
        can_dec: not is_nil(assigns.row.effective_mark) and assigns.row.effective_mark > 1.0,
        can_inc: not is_nil(assigns.row.effective_mark) and assigns.row.effective_mark < 6.0,
        dec_label: "Note um #{assigns.step} senken",
        inc_label: "Note um #{assigns.step} erhöhen"
      )

    ~H"""
    <div class="inline-flex items-center justify-end gap-1.5 w-full">
      <div class="tooltip tooltip-left tooltip-delayed" data-tip={@dec_label}>
        <button
          type="button"
          phx-click="adjust_mark"
          phx-value-submission-id={@row.submission.id}
          phx-value-direction="down"
          disabled={not @can_dec}
          aria-label={@dec_label}
          class="inline-flex items-center justify-center w-7 h-7 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
        >
          <.icon name="hero-minus" class="w-3.5 h-3.5" />
        </button>
      </div>
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
          step={@step}
          min="1"
          max="6"
          inputmode="decimal"
          phx-debounce="500"
          class="w-16 font-mono text-sm font-semibold text-center text-stone-700 bg-stone-50 border border-stone-200 rounded-md px-1.5 py-1 focus:outline-none focus:ring-4 focus:ring-sky-600 focus:ring-offset-2"
        />
      </form>
      <div class="tooltip tooltip-left tooltip-delayed" data-tip={@inc_label}>
        <button
          type="button"
          phx-click="adjust_mark"
          phx-value-submission-id={@row.submission.id}
          phx-value-direction="up"
          disabled={not @can_inc}
          aria-label={@inc_label}
          class="inline-flex items-center justify-center w-7 h-7 rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
        >
          <.icon name="hero-plus" class="w-3.5 h-3.5" />
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    if Exams.mark_step_configured?(exam) do
      {:ok, mount_configured(socket, exam, params)}
    else
      # The gate sits here rather than on the two "Zur Benotung" buttons, so a
      # bookmark or a pasted link walks through the decision as well — and
      # there is only one place that knows the rule.
      {:ok, push_navigate(socket, to: ~p"/exams/#{exam}/correction/grading/config")}
    end
  end

  defp mount_configured(socket, exam, params) do
    submissions = Exams.list_exam_submissions(exam)
    sample_solution_total = sum_sample_solution_points(exam)
    effective_max_points = exam.grading_max_points || sample_solution_total

    socket
    |> assign(:page_title, exam.name <> " – Benotung")
    |> assign(:exam, exam)
    |> assign(:mark_step, Exams.mark_step(exam))
    |> assign(:submissions, submissions)
    |> assign(:effective_max_points, effective_max_points)
    # Sorted here and not only in handle_params/3: should that call not
    # happen, :rows and :sort are set all the same.
    |> apply_sort(params)
    |> assign(:show_export_modal, false)
    |> assign(:export_options, %{
      show_points_and_mark: true,
      show_content: true,
      show_correction: false,
      show_sample_solution: false
    })
    |> assign(:export_status, nil)
    |> assign(:show_return_modal, false)
    |> assign_return_state(exam)
  end

  # A returned exam pre-fills the modal with what it was released with, so
  # re-returning does not silently change the flags.
  defp assign_return_state(socket, exam) do
    socket
    |> assign(:assigned_mode?, Exams.assigned_mode?(exam))
    |> assign(:returned?, Exams.returned?(exam))
    |> assign(
      :return_options,
      if Exams.returned?(exam) do
        ExamSubmissionView.options_from_exam(exam)
      else
        %{
          show_points_and_mark: true,
          show_content: true,
          show_correction: true,
          show_sample_solution: false
        }
      end
    )
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # On the redirect path — mark_step not configured — mount/3 loaded
    # nothing, so there is nothing to sort either.
    if Map.has_key?(socket.assigns, :submissions) do
      {:noreply, apply_sort(socket, params)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_mark", %{"submission_id" => sub_id, "mark" => raw}, socket) do
    save_mark(socket, sub_id, parse_mark(raw, socket.assigns.mark_step))
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
      step = socket.assigns.mark_step

      delta =
        if dir == "up", do: Grading.mark_step_size(step), else: -Grading.mark_step_size(step)

      # normalize_mark/2 absorbs the float drift of the addition itself
      # (4.7 + 0.1 == 4.800000000000001) and puts the result back on the grid.
      save_mark(socket, sub_id, Grading.normalize_mark(row.effective_mark + delta, step))
    end
  end

  def handle_event("open_export_modal", _params, socket) do
    {:noreply, assign(socket, :show_export_modal, true)}
  end

  def handle_event("close_export_modal", _params, socket) do
    {:noreply, assign(socket, :show_export_modal, false)}
  end

  def handle_event("toggle_export_option", %{"option" => option}, socket) do
    case view_option_key(option) do
      nil -> {:noreply, socket}
      key -> {:noreply, toggle_view_option(socket, :export_options, key)}
    end
  end

  def handle_event("open_return_modal", _params, socket) do
    {:noreply, assign(socket, :show_return_modal, true)}
  end

  def handle_event("close_return_modal", _params, socket) do
    {:noreply, assign(socket, :show_return_modal, false)}
  end

  def handle_event("toggle_return_option", %{"option" => option}, socket) do
    case view_option_key(option) do
      nil -> {:noreply, socket}
      key -> {:noreply, toggle_view_option(socket, :return_options, key)}
    end
  end

  def handle_event("confirm_return", _params, socket) do
    case Exams.return_exam(
           socket.assigns.current_scope,
           socket.assigns.exam,
           socket.assigns.return_options
         ) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> assign(:exam, exam)
         |> assign(:show_return_modal, false)
         |> assign_return_state(exam)
         |> put_flash(:info, "Prüfung an die Teilnehmenden zurückgegeben.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:show_return_modal, false)
         |> put_flash(:error, "Prüfung konnte nicht zurückgegeben werden.")}
    end
  end

  def handle_event("withdraw_return", _params, socket) do
    case Exams.withdraw_exam_return(socket.assigns.current_scope, socket.assigns.exam) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> assign(:exam, exam)
         |> assign_return_state(exam)
         |> put_flash(:info, "Rückgabe zurückgezogen.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Rückgabe konnte nicht zurückgezogen werden.")}
    end
  end

  def handle_event("start_export", _params, socket) do
    opts = socket.assigns.export_options
    endpoint = socket.endpoint
    # Exam and submissions are reloaded for the PDFs: the assigns can trail a
    # correction or sample solution saved in another tab.
    exam = Exams.get_exam!(socket.assigns.current_scope, socket.assigns.exam.id)

    print_opts =
      Map.take(opts, [
        :show_content,
        :show_correction,
        :show_sample_solution,
        :show_points_and_mark
      ])

    # Rendering and token signing are web concerns — the runner only gets
    # ready-made functions.
    web = %{
      render_pdf: fn submission ->
        submission = Exams.get_submission!(exam, submission.id)
        TaskyWeb.ExamSubmissionPdf.render(exam, submission, print_opts)
      end,
      sign_download: fn export_id, filename ->
        Tasky.Exams.ExportDownloadToken.sign(endpoint, export_id, filename)
      end
    }

    case Tasky.Exams.ExportRunner.start(
           exam,
           socket.assigns.submissions,
           self(),
           web
         ) do
      {:ok, _pid} ->
        {:noreply,
         socket
         |> assign(:show_export_modal, false)
         |> assign(:export_status, %{done: 0, total: length(socket.assigns.submissions)})}

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

  def handle_info({:export_done, %{download_token: token, filename: filename} = payload}, socket) do
    url = ~p"/exports/download?token=#{token}"
    failed = Map.get(payload, :failed, 0)

    {:noreply,
     socket
     |> assign(:export_status, nil)
     |> flash_export_result(filename, failed)
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

  # A partial export used to be announced as a clean success — the only trace of
  # the missing PDFs was FEHLER.txt inside the ZIP.
  defp flash_export_result(socket, filename, 0),
    do: put_flash(socket, :info, "Export bereit: #{filename}")

  defp flash_export_result(socket, filename, failed) do
    put_flash(
      socket,
      :error,
      "Export bereit: #{filename} — #{failed} #{pdf_word(failed)} konnten nicht erstellt werden. " <>
        "Details stehen in FEHLER.txt im ZIP."
    )
  end

  defp pdf_word(1), do: "PDF"
  defp pdf_word(_), do: "PDFs"

  defp save_mark(socket, sub_id, mark) do
    submission = Enum.find(socket.assigns.submissions, &(to_string(&1.id) == to_string(sub_id)))

    if is_nil(submission) do
      {:noreply, socket}
    else
      case Exams.set_submission_mark(socket.assigns.current_scope, submission, mark) do
        {:ok, updated} ->
          submissions =
            Enum.map(socket.assigns.submissions, fn s ->
              if s.id == updated.id, do: updated, else: s
            end)

          {:noreply,
           socket
           |> assign(:submissions, submissions)
           |> assign_rows(build_rows(socket.assigns.exam, submissions))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Note konnte nicht gespeichert werden.")}
      end
    end
  end

  # Points, calculated mark and effective mark all come from
  # Exams.grading_result/2 — the one place that precedence and the exam's
  # mark step live, shared with the PDF export and the learner's view.
  defp build_rows(exam, submissions) do
    Enum.map(submissions, fn s ->
      s
      |> then(&Exams.grading_result(exam, &1))
      |> Map.take([:points, :calculated_mark, :effective_mark])
      |> Map.put(:submission, s)
    end)
  end

  defp sum_sample_solution_points(exam), do: Grading.sum_points(exam.sample_solution_points)

  defp format_mark(mark), do: Grading.format_mark(mark, "")

  defp format_points(n), do: Grading.format_points(n)

  defp export_percent(%{total: 0}), do: 0
  defp export_percent(%{done: done, total: total}), do: round(done * 100 / total)

  defp mark_color_class(nil), do: "text-stone-400"
  defp mark_color_class(n) when n >= 5.5, do: "text-emerald-600"
  defp mark_color_class(n) when n >= 4.0, do: "text-stone-700"
  defp mark_color_class(_), do: "text-red-600"

  # The step matters here too, not just for the ± buttons: a 4.7 typed into
  # an exam that grades on 0.25 has to come back as 4.75.
  defp parse_mark(value, step) when is_binary(value) do
    case String.trim(value) do
      "" ->
        nil

      trimmed ->
        case Float.parse(trimmed) do
          {n, ""} -> Grading.normalize_mark(n, step)
          _ -> nil
        end
    end
  end

  defp parse_mark(_, _step), do: nil

  # Explicit whitelist: client params must never mint or crash on atoms.
  defp view_option_key("show_points_and_mark"), do: :show_points_and_mark
  defp view_option_key("show_content"), do: :show_content
  defp view_option_key("show_correction"), do: :show_correction
  defp view_option_key("show_sample_solution"), do: :show_sample_solution
  defp view_option_key(_), do: nil

  # Shared by the export and the return modal — including the rule that
  # show_correction requires show_content.
  defp toggle_view_option(socket, assign_key, key) do
    current = Map.fetch!(socket.assigns, assign_key)
    updated = Map.put(current, key, not Map.fetch!(current, key))

    updated =
      if updated.show_content,
        do: updated,
        else: Map.put(updated, :show_correction, false)

    assign(socket, assign_key, updated)
  end

  # Sorting happens on the rows, not on the submissions: points and marks
  # only come into being in build_rows/2. @submissions is pulled into the same
  # order because the PDF export iterates over it — the export should come out
  # in the order the teacher sees.
  defp apply_sort(socket, params) do
    sort = {sort_field(params["sort"]), sort_dir(params["dir"])}

    rows =
      socket.assigns.exam
      |> build_rows(socket.assigns.submissions)
      |> sort_rows(sort)

    socket
    |> assign(:sort, sort)
    |> assign_rows(rows)
    |> assign(:submissions, Enum.map(rows, & &1.submission))
  end

  # The one way :rows is written, so the statistics above the table can
  # never trail a mark that was just changed.
  defp assign_rows(socket, rows) do
    marks = Enum.map(rows, & &1.effective_mark)

    socket
    |> assign(:rows, rows)
    |> assign(:stats, Grading.mark_stats(marks, socket.assigns.mark_step))
  end

  defp sort_rows(rows, {field, dir}) do
    # A stable base order (Enum.sort_by/2 is stable): that way the tiebreak
    # within equal point totals or marks is always alphabetical.
    base =
      Enum.sort_by(rows, &{name_key(&1.submission.lastname), name_key(&1.submission.firstname)})

    # Empty values — no mark, no points, a missing name — always land at the
    # end, whichever direction is chosen.
    {present, blank} = Enum.split_with(base, &(sort_value(&1, field) != nil))

    Enum.sort_by(present, &sort_value(&1, field), dir) ++ blank
  end

  defp sort_value(row, :firstname), do: name_value(row.submission.firstname)
  defp sort_value(row, :lastname), do: name_value(row.submission.lastname)
  defp sort_value(row, :points), do: row.points
  defp sort_value(row, :calculated_mark), do: row.calculated_mark
  defp sort_value(row, :mark), do: row.effective_mark

  # A blank name counts as a missing one and sorts to the end; the tiebreak
  # key must never be nil, though, or nil would compare against a string.
  defp name_value(name) do
    case String.trim(name || "") do
      "" -> nil
      trimmed -> String.downcase(trimmed)
    end
  end

  defp name_key(name), do: name_value(name) || ""

  # Explicit whitelist: client params must never mint or crash on atoms.
  defp sort_field("lastname"), do: :lastname
  defp sort_field("points"), do: :points
  defp sort_field("calculated_mark"), do: :calculated_mark
  defp sort_field("mark"), do: :mark
  defp sort_field(_), do: :firstname

  defp sort_dir("desc"), do: :desc
  defp sort_dir(_), do: :asc
end
