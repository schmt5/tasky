defmodule TaskyWeb.ExamLive.CorrectionPartBulk do
  use TaskyWeb, :live_view

  alias Tasky.Correction.CheckboxPatterns
  alias Tasky.Exams
  alias Tasky.Grading

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/exams/#{@exam}/correction"}
    >
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-7xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Korrektur", navigate: ~p"/exams/#{@exam}/correction"},
              %{label: @current_part.label}
            ]} />
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button
              navigate={~p"/exams/#{@exam}/correction"}
              tooltip="Zurück zur Übersicht"
            />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              Korrektur – {@current_part.label}
            </h1>
          </div>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-8 pb-12">
        <%= if @answer_blocks == [] do %>
          <div class="bg-white rounded-[14px] border border-stone-100 p-12 text-center text-stone-400 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
            <.icon name="hero-document" class="w-10 h-10 mx-auto mb-3 text-stone-300" />
            <p class="text-sm font-medium">Keine Antwortfelder in diesem Teil.</p>
          </div>
        <% else %>
          {render_part_nav(assigns)}
          {render_question_card(assigns)}

          <div class="mt-4">
            {render_summary(assigns)}
          </div>

          <div id="bulk-power-keys" phx-hook="BulkPowerKeys">
            <div class="mt-4">
              <%= if @is_multi_input do %>
                <div class="space-y-4">
                  <%= for section <- block_sections(@answer_blocks) do %>
                    <%= if section.kind == :checkboxes do %>
                      {render_checkbox_section(assigns, section)}
                    <% else %>
                      {render_block_section(assigns, section.block)}
                    <% end %>
                  <% end %>
                </div>
              <% else %>
                <div class="space-y-4">
                  <%= for block <- @answer_blocks do %>
                    {render_groups_card(assigns, block)}
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="mt-6">
              <div class="bg-white border border-stone-200 rounded-2xl shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] px-5 py-3 flex items-center justify-end gap-3">
                <.icon
                  name="hero-check-badge"
                  class={[
                    "w-6 h-6 shrink-0 transition-all duration-300 ease-out",
                    if(@is_corrected, do: "text-green-600 scale-110", else: "text-stone-300")
                  ]}
                />
                <button
                  type="button"
                  data-bulk-power-toggle
                  phx-click="toggle_part_corrected"
                  aria-pressed={@is_corrected}
                  class={[
                    "inline-flex items-center justify-center gap-2 text-sm font-semibold px-5 py-2.5 rounded-lg border transition-all duration-200 active:scale-[0.98] focus:outline-none focus-visible:ring-4 focus-visible:ring-sky-600 focus-visible:ring-offset-2",
                    if(@is_corrected,
                      do:
                        "bg-stone-100 border-stone-300 text-stone-600 hover:bg-stone-200 hover:border-stone-400",
                      else:
                        "bg-green-50 border-green-500 text-green-700 hover:bg-green-100 hover:border-green-600"
                    )
                  ]}
                >
                  {if @is_corrected,
                    do: "Erledigt zurücknehmen",
                    else: "Als erledigt markieren"}
                  <kbd class="px-1.5 py-0.5 rounded font-mono text-[10px] border bg-white/60 border-stone-200 text-stone-500">
                    Enter
                  </kbd>
                </button>
                <.link
                  navigate={
                    case @next_part_id do
                      nil -> ~p"/exams/#{@exam}/correction"
                      next -> ~p"/exams/#{@exam}/correction/bulk/#{next}"
                    end
                  }
                  class="inline-flex items-center justify-center gap-2 text-sm font-semibold px-5 py-2.5 rounded-lg border border-sky-600 bg-white text-sky-700 transition-all duration-200 active:scale-[0.98] hover:bg-sky-50 focus:outline-none focus-visible:ring-4 focus-visible:ring-sky-600 focus-visible:ring-offset-2"
                >
                  {if @next_part_id, do: "Nächste Frage", else: "Zur Übersicht"}
                  <kbd class="px-1.5 py-0.5 rounded font-mono text-[10px] border bg-sky-50 border-sky-200 text-sky-600">
                    Enter
                  </kbd>
                  <.icon name="hero-arrow-right" class="w-4 h-4" />
                </.link>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp render_part_nav(assigns) do
    ~H"""
    <div class="overflow-x-auto -mx-1 px-1 mb-4">
      <ol class="flex items-stretch gap-2 whitespace-nowrap">
        <li
          :for={{part, idx} <- Enum.with_index(@parts)}
          class="tooltip tooltip-bottom tooltip-delayed"
          data-tip={part.label}
        >
          <.link
            navigate={~p"/exams/#{@exam}/correction/bulk/#{part.id}"}
            class={[
              "inline-flex items-center gap-3 px-3 py-2 rounded-[10px] border-2 transition-all duration-150 max-w-[14rem]",
              part_chip_classes(
                idx == @current_part_index,
                MapSet.member?(@parts_done, part.id)
              )
            ]}
          >
            <span class="font-mono text-xs tabular-nums opacity-60 shrink-0">
              {String.pad_leading(Integer.to_string(idx + 1), 2, "0")}
            </span>
            <span class="flex flex-col min-w-0">
              <span class="text-sm font-semibold truncate">{part.label}</span>
              <span class={[
                "text-xs inline-flex items-center gap-1 mt-0.5",
                part_chip_status_classes(
                  idx == @current_part_index,
                  MapSet.member?(@parts_done, part.id)
                )
              ]}>
                <%= if MapSet.member?(@parts_done, part.id) do %>
                  <.icon name="hero-check-badge" class="w-4 h-4" /> Erledigt
                <% else %>
                  <span class="w-2 h-2 rounded-full border border-current"></span> Offen
                <% end %>
              </span>
            </span>
          </.link>
        </li>
      </ol>
    </div>
    """
  end

  # (active?, done?)
  defp part_chip_classes(true, true),
    do: "bg-stone-900 border-green-500 text-white"

  defp part_chip_classes(true, false),
    do: "bg-stone-900 border-stone-900 text-white"

  defp part_chip_classes(false, true),
    do: "bg-white border-green-500 text-stone-700 hover:bg-green-50/40"

  defp part_chip_classes(false, false),
    do: "bg-white border-stone-200 text-stone-700 hover:bg-stone-50 hover:border-stone-300"

  defp part_chip_status_classes(true, true), do: "text-green-300"
  defp part_chip_status_classes(true, false), do: "text-stone-400"
  defp part_chip_status_classes(false, true), do: "text-green-600"
  defp part_chip_status_classes(false, false), do: "text-stone-400"

  defp render_question_card(assigns) do
    ~H"""
    <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] mb-4">
      <div class="px-5 py-4 border-b border-stone-100 flex items-center justify-between gap-4">
        <div class="flex items-center gap-2 min-w-0">
          <.icon name="hero-document-text" class="w-4 h-4 text-stone-400 shrink-0" />
          <h2 class="text-lg font-semibold text-stone-800 truncate">Aufgabe</h2>
        </div>
        <div class="flex items-center gap-2 flex-wrap justify-end">
          <span class={[
            "inline-flex items-center gap-1.5 text-xs font-semibold rounded-full px-3 py-1",
            config_chip_classes(not is_nil(@max_points))
          ]}>
            Max. Punkte:
            <span class="font-mono tabular-nums">
              {if @max_points, do: format_max_points(@max_points), else: "—"}
            </span>
          </span>
          <.config_chip active={@auto_correct} label="Auto-Korrektur" />
          <.config_chip active={@ignore_case} label="Gross/Klein ignorieren" />
          <.config_chip active={@ignore_spelling} label="Fuzzy-Matching" />
          <.config_chip active={@ignore_punctuation} label="Satzzeichen ignorieren" />
          <.config_chip
            active={@checkbox_scoring.rule != "per_checkbox"}
            label={checkbox_rule_label(@checkbox_scoring)}
          />
        </div>
      </div>
      <div class="p-5">
        <h3 class="text-xl font-semibold text-stone-800 leading-snug">
          {@current_part.label}
        </h3>
      </div>
    </div>
    """
  end

  attr :active, :boolean, required: true
  attr :label, :string, required: true

  # Declarative function component (instead of a render_* helper building
  # its own assigns) so LiveView change tracking works.
  defp config_chip(assigns) do
    ~H"""
    <span
      :if={@active}
      class="inline-flex items-center text-xs font-semibold rounded-full px-3 py-1 text-stone-600 bg-stone-100 border border-stone-200"
    >
      {@label}
    </span>
    """
  end

  defp checkbox_rule_label(%{rule: "all_or_nothing"}), do: "Checkboxen: alles oder nichts"

  defp checkbox_rule_label(_scoring), do: "Checkboxen: pro Checkbox"

  defp config_chip_classes(true),
    do: "text-stone-600 bg-stone-100 border border-stone-200"

  defp config_chip_classes(false),
    do: "text-stone-400 bg-stone-50 border border-stone-200"

  # Points formatting is centralized in Tasky.Grading (one source of truth for
  # screen + PDF); this thin wrapper keeps the "—" fallback for non-numbers.
  defp format_max_points(n) when is_number(n), do: Grading.format_points(n)
  defp format_max_points(_), do: "—"

  defp render_summary(assigns) do
    ~H"""
    <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-5">
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
          <.icon name="hero-information-circle" class="w-4 h-4 text-stone-400" />
          <h2 class="text-lg font-semibold text-stone-800">Antworten</h2>
        </div>
        <div class="text-xs text-stone-500">
          {length(@answer_blocks)}
          {if length(@answer_blocks) == 1, do: "Antwortfeld", else: "Antwortfelder"} · {@total_submissions} Teilnehmende
        </div>
      </div>

      <div class="h-2 bg-stone-100 rounded-full overflow-hidden flex">
        <div class="h-full bg-green-500" style={"width: #{percent(@totals.correct, @totals.total)}%"}>
        </div>
        <div class="h-full bg-yellow-400" style={"width: #{percent(@totals.half, @totals.total)}%"}>
        </div>
        <div class="h-full bg-red-500" style={"width: #{percent(@totals.wrong, @totals.total)}%"}>
        </div>
      </div>
      <div class="flex items-center gap-6 mt-3 text-sm">
        <span class="inline-flex items-center gap-1.5">
          <span class="w-2 h-2 rounded-full bg-green-500"></span>
          <span class="text-xl font-semibold text-stone-800 tabular-nums">{@totals.correct}</span>
          <span class="text-stone-500">Volle Punkte</span>
        </span>
        <span class="inline-flex items-center gap-1.5">
          <span class="w-2 h-2 rounded-full bg-yellow-400"></span>
          <span class="text-xl font-semibold text-stone-800 tabular-nums">{@totals.half}</span>
          <span class="text-stone-500">Manuell</span>
        </span>
        <span class="inline-flex items-center gap-1.5">
          <span class="w-2 h-2 rounded-full bg-red-500"></span>
          <span class="text-xl font-semibold text-stone-800 tabular-nums">{@totals.wrong}</span>
          <span class="text-stone-500">0 Punkte</span>
        </span>
      </div>
    </div>
    """
  end

  defp render_block_section(assigns, block) do
    assigns = assign(assigns, :block, block)

    ~H"""
    <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-5 space-y-2">
      <div class="pb-1">
        <div class="text-lg font-bold text-stone-900">
          {block_heading(@block)}
        </div>
        <div :if={@block.max_points} class="text-xs font-medium text-stone-500 mt-0.5">
          max. {format_max_points(@block.max_points)} P.
        </div>
      </div>
      <%= for group <- @block.groups do %>
        {render_group_card(assigns, @block, group)}
      <% end %>
    </div>
    """
  end

  # The checkboxes of one list are one question, so they are judged by answer
  # pattern: one card per combination of ticks, whatever each checkbox's
  # verdict is stored as underneath (see `Tasky.Correction.CheckboxPatterns`).
  defp render_checkbox_section(assigns, section) do
    assigns =
      assigns
      |> assign(:section, section)
      |> assign(:patterns, CheckboxPatterns.build(section.blocks, assigns.checkbox_scoring))

    ~H"""
    <div
      id={"bulk-checkbox-group-#{@section.id}"}
      class="rounded-[16px] border border-stone-200 bg-stone-50/60 p-3 space-y-3"
    >
      <div class="flex items-center justify-between gap-4 flex-wrap px-2 pt-1">
        <div class="flex items-center gap-2">
          <.icon name="hero-check-circle" class="w-4 h-4 text-stone-400" />
          <span class="text-xs font-semibold uppercase tracking-wide text-stone-500">
            Checkboxen · {length(@section.blocks)} Optionen · {length(@patterns)} Antwortmuster
          </span>
        </div>
        <div
          :if={Enum.any?(@section.blocks, &(&1.sample_answers != []))}
          id={"bulk-checkbox-solution-#{@section.id}"}
          class="flex items-center gap-3 flex-wrap text-xs text-stone-500"
        >
          <span class="font-semibold uppercase tracking-wide">Musterlösung:</span>
          <span
            :for={block <- @section.blocks}
            class="inline-flex items-center gap-1.5 text-stone-700"
          >
            <.checkbox_mark checked={block.sample_answers == ["angekreuzt"]} />
            {checkbox_label(block)}
          </span>
        </div>
      </div>

      <%= for pattern <- @patterns do %>
        {render_pattern_card(assigns, pattern)}
      <% end %>
    </div>
    """
  end

  defp render_pattern_card(assigns, pattern) do
    # The list id as the client sends it back with a manual input.
    group = to_string(assigns.section.id)
    key = pattern.key

    assigns =
      assigns
      |> assign(:pattern, pattern)
      |> assign(
        :manual_open,
        match?(%{pattern_group: ^group, pattern_key: ^key}, assigns.manual_input)
      )

    ~H"""
    <div
      id={"bulk-pattern-#{@section.id}-#{@pattern.key}"}
      tabindex="0"
      data-bulk-power-row="true"
      data-pattern-group={@section.id}
      data-pattern-key={@pattern.key}
      class="bg-white rounded-[12px] border border-stone-200 p-4 space-y-3 outline-none focus:ring-4 focus:ring-sky-600 focus:ring-offset-2 transition-all duration-100"
    >
      <ul class="space-y-1.5">
        <li :for={option <- @pattern.options}>
          <%!-- The row is the toggle: a click flips this checkbox between
               counted right and counted wrong for the whole pattern. --%>
          <button
            type="button"
            tabindex="-1"
            id={"bulk-pattern-option-#{@section.id}-#{@pattern.key}-#{option.index}"}
            phx-click="toggle_pattern_option"
            phx-value-group={@section.id}
            phx-value-pattern={@pattern.key}
            phx-value-index={option.index}
            data-verdict={option_verdict_key(option_marker_verdict(option))}
            class={[
              "w-full flex items-center gap-3 rounded-xl px-4 py-3 text-left transition-all duration-100 hover:brightness-[0.98] active:scale-[0.995]",
              option_row_class(option_marker_verdict(option))
            ]}
          >
            <.checkbox_mark checked={option.state == :checked} missing={option.state == :missing} />
            <span class="text-base text-stone-800 leading-snug">{checkbox_label(option)}</span>
            <span
              class="ml-auto tooltip tooltip-left tooltip-delayed"
              data-tip={option_tooltip(option)}
            >
              <span class="text-lg leading-none">
                {option_marker(option_marker_verdict(option))}
              </span>
            </span>
          </button>
        </li>
      </ul>

      <div class="flex items-center justify-between gap-4 flex-wrap pt-1">
        <div class="min-w-0 space-y-1">
          <div class="flex items-center gap-2 flex-wrap text-xs text-stone-500">
            <span
              :if={@pattern.matches_solution?}
              class="inline-flex items-center gap-1 text-[11px] font-semibold text-emerald-700 bg-emerald-50 border border-emerald-100 rounded-full px-2.5 py-0.5"
            >
              <.icon name="hero-check" class="w-3.5 h-3.5" /> entspricht der Lösung
            </span>
            <span>
              {@pattern.count}× abgegeben<span :if={@pattern.points != nil and @pattern.max_points}> · {format_max_points(@pattern.points)} / {format_max_points(@pattern.max_points)} P.</span>
            </span>
          </div>
          <div class="text-xs text-stone-500">
            {Enum.map_join(@pattern.students, " · ", &student_name/1)}
          </div>
        </div>

        <div class="shrink-0 flex items-center gap-3">
          <button
            :if={@pattern.verdict == :manual and not @manual_open}
            type="button"
            tabindex="-1"
            id={"bulk-pattern-reset-#{@section.id}-#{@pattern.key}"}
            phx-click="reset_pattern_verdicts"
            phx-value-group={@section.id}
            phx-value-pattern={@pattern.key}
            class="text-xs font-semibold text-stone-500 hover:text-stone-800 underline-offset-2 hover:underline transition-colors duration-100"
          >
            Auf Regel zurücksetzen
          </button>
          <%= if @manual_open do %>
            {render_pattern_manual_input(assigns)}
          <% else %>
            {render_pattern_verdict_pill(assigns)}
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp render_pattern_verdict_pill(assigns) do
    ~H"""
    <div class="inline-flex items-center gap-0 rounded-lg border border-stone-200 bg-white p-0.5">
      <.pattern_verdict_button
        group={@section.id}
        pattern={@pattern.key}
        verdict="correct"
        active={@pattern.verdict == "correct"}
        label={full_points_label(@pattern.max_points)}
        kbd_label="J"
        active_class="bg-green-500 text-white shadow-[0_2px_8px_rgba(34,197,94,0.25)]"
      />
      <button
        :if={@pattern.max_points}
        type="button"
        tabindex="-1"
        id={"bulk-pattern-manual-#{@section.id}-#{@pattern.key}"}
        phx-click="open_pattern_manual_input"
        phx-value-group={@section.id}
        phx-value-pattern={@pattern.key}
        class={[
          "inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-md transition-all duration-100",
          if(@pattern.verdict == :manual,
            do: "bg-yellow-400 text-white shadow-[0_2px_8px_rgba(250,204,21,0.3)]",
            else: "text-stone-500 hover:bg-stone-50 hover:text-stone-700"
          )
        ]}
      >
        <span>
          {if @pattern.verdict == :manual and @pattern.points != nil,
            do: "Manuell (#{format_max_points(@pattern.points)})",
            else: "Manuell"}
        </span>
        <kbd class={[
          "px-1.5 py-0.5 rounded font-mono text-[10px] border",
          if(@pattern.verdict == :manual,
            do: "bg-white/25 border-white/40 text-white",
            else: "bg-stone-100 border-stone-200 text-stone-700"
          )
        ]}>
          K
        </kbd>
      </button>
      <.pattern_verdict_button
        group={@section.id}
        pattern={@pattern.key}
        verdict="wrong"
        active={@pattern.verdict == "wrong"}
        label="0 Punkte"
        kbd_label="L"
        active_class="bg-red-500 text-white shadow-[0_2px_8px_rgba(239,68,68,0.25)]"
      />
    </div>
    """
  end

  defp render_pattern_manual_input(assigns) do
    ~H"""
    <form
      id={"bulk-pattern-manual-form-#{@section.id}-#{@pattern.key}"}
      phx-submit="set_pattern_manual"
      class="inline-flex items-center gap-1.5 rounded-lg border border-yellow-400 bg-yellow-50/60 p-1.5"
    >
      <input type="hidden" name="group" value={@section.id} />
      <input type="hidden" name="pattern" value={@pattern.key} />
      <input
        id={pattern_manual_input_id(@section.id, @pattern.key)}
        type="number"
        name="points"
        value={@manual_input.value}
        step="0.25"
        min="0"
        max={@pattern.max_points}
        inputmode="decimal"
        phx-keydown="cancel_manual_input"
        phx-key="Escape"
        class="w-20 font-mono text-sm text-center text-stone-800 bg-white border border-stone-200 rounded-md px-2 py-1 focus:outline-none focus:ring-2 focus:ring-yellow-400/60 focus:border-yellow-400"
      />
      <span class="text-xs text-stone-500 whitespace-nowrap">
        / {format_max_points(@pattern.max_points)} P.
      </span>
      <button
        type="submit"
        class="inline-flex items-center gap-1 text-xs font-semibold px-2.5 py-1.5 rounded-md bg-yellow-400 text-white hover:bg-yellow-500 transition-colors duration-100"
      >
        OK
        <kbd class="px-1 py-0.5 rounded font-mono text-[10px] border bg-white/25 border-white/40 text-white">
          Enter
        </kbd>
      </button>
      <button
        type="button"
        phx-click="cancel_manual_input"
        aria-label="Abbrechen"
        class="inline-flex items-center justify-center w-7 h-7 rounded-md text-stone-400 hover:bg-stone-100 hover:text-stone-600 transition-colors duration-100"
      >
        <.icon name="hero-x-mark" class="w-4 h-4" />
      </button>
    </form>
    """
  end

  defp pattern_manual_input_id(group, key), do: "pattern-manual-points-#{group}-#{key}"

  attr :checked, :boolean, required: true
  attr :missing, :boolean, default: false

  # A drawn checkbox, so a pattern reads like the question on the sheet.
  defp checkbox_mark(assigns) do
    ~H"""
    <span
      aria-label={
        cond do
          @missing -> "keine Antwort"
          @checked -> "angekreuzt"
          true -> "nicht angekreuzt"
        end
      }
      class={[
        "inline-flex items-center justify-center w-[18px] h-[18px] shrink-0 rounded-[4px] border-[1.5px]",
        cond do
          @missing -> "border-dashed border-stone-300 bg-white"
          @checked -> "border-stone-800 bg-stone-800 text-white"
          true -> "border-stone-400 bg-white"
        end
      ]}
    >
      <.icon :if={@checked and not @missing} name="hero-check-mini" class="w-3.5 h-3.5" />
    </span>
    """
  end

  attr :group, :string, required: true
  attr :pattern, :string, required: true
  attr :verdict, :string, required: true
  attr :active, :boolean, required: true
  attr :label, :string, required: true
  attr :kbd_label, :string, required: true
  attr :active_class, :string, required: true

  defp pattern_verdict_button(assigns) do
    ~H"""
    <button
      type="button"
      tabindex="-1"
      phx-click="set_pattern_verdict"
      phx-value-group={@group}
      phx-value-pattern={@pattern}
      phx-value-verdict={@verdict}
      class={[
        "inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-md transition-all duration-100",
        if(@active, do: @active_class, else: "text-stone-500 hover:bg-stone-50 hover:text-stone-700")
      ]}
    >
      <span>{@label}</span>
      <kbd class={[
        "px-1.5 py-0.5 rounded font-mono text-[10px] border",
        if(@active,
          do: "bg-white/25 border-white/40 text-white",
          else: "bg-stone-100 border-stone-200 text-stone-700"
        )
      ]}>
        {@kbd_label}
      </kbd>
    </button>
    """
  end

  defp checkbox_label(%{label: label, index: index}) when label in [nil, ""],
    do: "Checkbox #{index + 1}"

  defp checkbox_label(%{label: label}), do: label

  defp option_verdict_key(v) when v in ["correct", "wrong"], do: v
  defp option_verdict_key(_partial), do: "partial"

  # Same tints and markers as the corrected exam (✅ / 🟡 / ❌), so a pattern
  # reads like the sheet the student gets back.
  # Manual points read like the markers on the sheet: the full share is a ✅,
  # 0 is a ❌, anything between a 🟡.
  defp option_marker_verdict(%{verdict: :mixed}), do: :mixed

  defp option_marker_verdict(option),
    do: Grading.marker_verdict(option.verdict, option.max_points)

  defp option_row_class("correct"), do: "bg-emerald-50"
  defp option_row_class("wrong"), do: "bg-red-50"
  defp option_row_class(_partial), do: "bg-amber-50"

  defp option_marker("correct"), do: "✅"
  defp option_marker("wrong"), do: "❌"
  defp option_marker(_partial), do: "🟡"

  defp option_tooltip(option) do
    [option_deviation_text(option), option_points_label(option), "Klicken zum Umschalten"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp option_deviation_text(%{deviation: :extra}), do: "zu viel angekreuzt"
  defp option_deviation_text(%{deviation: :missing}), do: "fehlt"
  defp option_deviation_text(%{expected: nil}), do: nil
  defp option_deviation_text(_option), do: "wie in der Lösung"

  defp option_points_label(%{verdict: :mixed}),
    do: "in der Einzelkorrektur uneinheitlich bewertet"

  defp option_points_label(%{verdict: v, max_points: max}) when is_number(max),
    do: "#{format_max_points(Grading.awarded_points(v, max))} / #{format_max_points(max)} P."

  defp option_points_label(%{verdict: "correct"}), do: "zählt als richtig"
  defp option_points_label(_option), do: "zählt als falsch"

  # Consecutive checkboxes of the same list become one section; every other
  # block stands alone.
  defp block_sections(blocks) do
    blocks
    |> Enum.chunk_by(fn b -> (b.type == "taskItem" && b.group) || {:single, b.index} end)
    |> Enum.map(fn
      [%{type: "taskItem", group: group} | _] = items when not is_nil(group) ->
        %{kind: :checkboxes, id: group, blocks: items}

      [block] ->
        %{kind: :single, block: block}
    end)
  end

  # "fliegen → fly" — label and sample answers as one equal-weight heading.
  # For a checkbox: "Option B → angekreuzt", i.e. what the solution expects.
  defp block_heading(%{type: "taskItem"} = block) do
    label = if block.label in [nil, ""], do: "Checkbox #{block.index + 1}", else: block.label

    case block.sample_answers do
      [] -> label
      [expected] -> label <> " → " <> expected
    end
  end

  # For a radio group: "Sanduhr → analog", the option the solution chooses.
  defp block_heading(%{type: "choice"} = block) do
    label = if block.label in [nil, ""], do: "Auswahl #{block.index + 1}", else: block.label

    case block.sample_answers do
      [] -> label
      [expected | _] -> label <> " → " <> expected
    end
  end

  defp block_heading(block) do
    label = block.label || "Antwort #{block.index + 1}"

    case block.sample_answers do
      [] -> label
      samples -> label <> " → " <> Enum.join(samples, " / ")
    end
  end

  defp render_groups_card(assigns, block) do
    assigns = assign(assigns, :block, block)

    ~H"""
    <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-5 space-y-2">
      <%= if @block.sample_answers != [] or @block.max_points do %>
        <div class="flex items-center gap-2 pb-3 mb-2 border-b border-stone-100">
          <span
            :if={@block.max_points}
            class="inline-flex items-center text-xs font-semibold text-stone-600 bg-stone-100 border border-stone-200 rounded-full px-2.5 py-0.5"
          >
            max. {format_max_points(@block.max_points)} P.
          </span>
          <span
            :if={@block.sample_answers != []}
            class="text-xs font-semibold text-stone-500 uppercase tracking-wide"
          >
            Musterlösung:
          </span>
          <%= for sample <- @block.sample_answers do %>
            <span class="inline-flex items-center text-xs font-medium text-emerald-700 bg-emerald-50 border border-emerald-100 rounded-md px-2 py-0.5">
              {sample}
            </span>
          <% end %>
        </div>
      <% end %>
      <%= for group <- @block.groups do %>
        {render_group_card(assigns, @block, group)}
      <% end %>
    </div>
    """
  end

  defp render_group_card(assigns, block, group) do
    effective = effective_verdict(group)

    assigns =
      assigns
      |> assign(:block, block)
      |> assign(:group, group)
      |> assign(:effective, effective)
      |> assign(:awarded, awarded_points(effective, block.max_points))
      |> assign(
        :manual_open,
        match?(
          %{block_index: bi, group_text: gt} when bi == block.index and gt == group.text,
          assigns.manual_input
        )
      )

    ~H"""
    <div
      tabindex="0"
      data-bulk-power-row="true"
      data-block-index={@block.index}
      data-group-text={@group.text || ""}
      class="bg-white rounded-[12px] border border-stone-200 px-5 py-4 flex items-center gap-4 outline-none focus:ring-4 focus:ring-sky-600 focus:ring-offset-2 focus:bg-sky-50/30 transition-all duration-100"
    >
      <div class="flex-1 min-w-0">
        <div class="text-lg text-stone-800">
          <%= if @group.text do %>
            {@group.text}
          <% else %>
            <span class="text-stone-400 italic">— keine Antwort —</span>
          <% end %>
        </div>
        <div class="text-xs text-stone-500 mt-0.5">
          {@group.count}× abgegeben<span :if={@awarded != nil and @block.max_points}> · {format_max_points(@awarded)} / {format_max_points(@block.max_points)} P.</span>
        </div>
        <div class="text-xs text-stone-500 mt-2">
          {Enum.map_join(@group.students, " · ", &student_name/1)}
        </div>
      </div>
      <div class="shrink-0">
        <%= if @manual_open do %>
          {render_manual_input(assigns)}
        <% else %>
          {render_verdict_pill(assigns)}
        <% end %>
      </div>
    </div>
    """
  end

  defp render_verdict_pill(assigns) do
    ~H"""
    <div class="inline-flex items-center gap-0 rounded-lg border border-stone-200 bg-white p-0.5">
      <.verdict_button
        block_index={@block.index}
        group_text={@group.text}
        verdict="correct"
        active={@effective == "correct"}
        label={full_points_label(@block.max_points)}
        kbd_label="J"
        active_class="bg-green-500 text-white shadow-[0_2px_8px_rgba(34,197,94,0.25)]"
      />
      <button
        type="button"
        tabindex="-1"
        phx-click="open_manual_input"
        phx-value-index={@block.index}
        phx-value-text={@group.text || ""}
        class={[
          "inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-md transition-all duration-100",
          if(manual_active?(@effective),
            do: "bg-yellow-400 text-white shadow-[0_2px_8px_rgba(250,204,21,0.3)]",
            else: "text-stone-500 hover:bg-stone-50 hover:text-stone-700"
          )
        ]}
      >
        <span>{manual_label(@effective, @block.max_points)}</span>
        <kbd class={[
          "px-1.5 py-0.5 rounded font-mono text-[10px] border",
          if(manual_active?(@effective),
            do: "bg-white/25 border-white/40 text-white",
            else: "bg-stone-100 border-stone-200 text-stone-700"
          )
        ]}>
          K
        </kbd>
      </button>
      <.verdict_button
        block_index={@block.index}
        group_text={@group.text}
        verdict="wrong"
        active={@effective == "wrong"}
        label="0 Punkte"
        kbd_label="L"
        active_class="bg-red-500 text-white shadow-[0_2px_8px_rgba(239,68,68,0.25)]"
      />
    </div>
    """
  end

  defp render_manual_input(assigns) do
    ~H"""
    <form
      phx-submit="set_group_verdict_manual"
      class="inline-flex items-center gap-1.5 rounded-lg border border-yellow-400 bg-yellow-50/60 p-1.5"
    >
      <input type="hidden" name="index" value={@block.index} />
      <input type="hidden" name="text" value={@group.text || ""} />
      <input
        id={manual_input_id(@block.index, @group.text)}
        type="number"
        name="points"
        value={@manual_input.value}
        step="0.25"
        min="0"
        max={@block.max_points}
        inputmode="decimal"
        phx-keydown="cancel_manual_input"
        phx-key="Escape"
        class="w-20 font-mono text-sm text-center text-stone-800 bg-white border border-stone-200 rounded-md px-2 py-1 focus:outline-none focus:ring-2 focus:ring-yellow-400/60 focus:border-yellow-400"
      />
      <span :if={@block.max_points} class="text-xs text-stone-500 whitespace-nowrap">
        / {format_max_points(@block.max_points)} P.
      </span>
      <button
        type="submit"
        class="inline-flex items-center gap-1 text-xs font-semibold px-2.5 py-1.5 rounded-md bg-yellow-400 text-white hover:bg-yellow-500 transition-colors duration-100"
      >
        OK
        <kbd class="px-1 py-0.5 rounded font-mono text-[10px] border bg-white/25 border-white/40 text-white">
          Enter
        </kbd>
      </button>
      <button
        type="button"
        phx-click="cancel_manual_input"
        aria-label="Abbrechen"
        class="inline-flex items-center justify-center w-7 h-7 rounded-md text-stone-400 hover:bg-stone-100 hover:text-stone-600 transition-colors duration-100"
      >
        <.icon name="hero-x-mark" class="w-4 h-4" />
      </button>
    </form>
    """
  end

  defp manual_input_id(index, text) do
    "manual-points-#{index}-#{:erlang.phash2(text || "")}"
  end

  defp full_points_label(nil), do: "Volle Punkte"
  defp full_points_label(max), do: "Volle Punkte (#{format_max_points(max)})"

  defp manual_active?(v), do: is_number(v) or v == "half"

  defp manual_label(v, _max) when is_number(v), do: "Manuell (#{format_max_points(v)})"

  defp manual_label("half", max) when is_number(max),
    do: "Manuell (#{format_max_points(max * 0.5)})"

  defp manual_label(_v, _max), do: "Manuell"

  # Points a group's members receive for this block under the effective
  # verdict — nil when nothing is configured/decided yet.
  defp awarded_points(_v, nil), do: nil
  defp awarded_points("correct", max), do: max
  defp awarded_points("half", max), do: max * 0.5
  defp awarded_points("wrong", _max), do: 0
  defp awarded_points(v, _max) when is_number(v), do: v
  defp awarded_points(_, _), do: nil

  attr :block_index, :integer, required: true
  attr :group_text, :string, default: nil
  attr :verdict, :string, required: true
  attr :active, :boolean, required: true
  attr :label, :string, required: true
  attr :kbd_label, :string, required: true
  attr :active_class, :string, required: true

  defp verdict_button(assigns) do
    ~H"""
    <button
      type="button"
      tabindex="-1"
      phx-click="set_group_verdict"
      phx-value-index={@block_index}
      phx-value-text={@group_text || ""}
      phx-value-verdict={@verdict}
      class={[
        "inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-md transition-all duration-100",
        if(@active, do: @active_class, else: "text-stone-500 hover:bg-stone-50 hover:text-stone-700")
      ]}
    >
      <span>{@label}</span>
      <kbd class={[
        "px-1.5 py-0.5 rounded font-mono text-[10px] border",
        if(@active,
          do: "bg-white/25 border-white/40 text-white",
          else: "bg-stone-100 border-stone-200 text-stone-700"
        )
      ]}>
        {@kbd_label}
      </kbd>
    </button>
    """
  end

  # ----------------------------------------------------------------- mount/handle

  @impl true
  def mount(%{"id" => exam_id, "part_id" => part_id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, exam_id)

    if connected?(socket) do
      Exams.subscribe_correction(exam.id)
    end

    parts = Exams.split_content_into_parts(exam.content || %{}, exam.answer_mode)

    # Grouping identical answers across submissions needs answer fields to group
    # by. A free-document exam has none, so this view could only ever render its
    # "Keine Antwortfelder" placeholder — send the teacher to the grid instead of
    # to a dead end they have to navigate back out of.
    if Exams.free_document?(exam) do
      {:ok, push_navigate(socket, to: ~p"/exams/#{exam}/correction")}
    else
      mount_part(socket, exam, parts, part_id)
    end
  end

  defp mount_part(socket, exam, parts, part_id) do
    case Enum.find_index(parts, &(&1.id == part_id)) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Teil nicht gefunden.")
         |> push_navigate(to: ~p"/exams/#{exam}/correction")}

      idx ->
        current_part = Enum.at(parts, idx)
        next_part_id = if idx + 1 < length(parts), do: Enum.at(parts, idx + 1).id, else: nil

        submissions = Exams.list_exam_submissions(exam)
        answer_blocks = Exams.list_part_answer_groups(exam, part_id)

        part_config = Map.get(exam.ai_correction_config || %{}, part_id, %{})
        max_points = Map.get(exam.sample_solution_points || %{}, part_id)

        {:ok,
         socket
         |> assign(:page_title, "#{exam.name} – #{current_part.label}")
         |> assign(:exam, exam)
         |> assign(:parts, parts)
         |> assign(:current_part, current_part)
         |> assign(:current_part_index, idx)
         |> assign(:parts_done, compute_parts_done(submissions, parts))
         |> assign(:is_corrected, part_corrected?(submissions, part_id))
         |> assign(:next_part_id, next_part_id)
         |> assign(:answer_blocks, answer_blocks)
         |> assign(:manual_input, nil)
         |> assign(:is_multi_input, length(answer_blocks) > 1)
         |> assign(:total_submissions, length(submissions))
         |> assign(:part_already_done, count_part_done(submissions, part_id))
         |> assign(:totals, compute_totals(answer_blocks))
         |> assign(:max_points, max_points)
         |> assign(:auto_correct, Map.get(part_config, "auto_correct") == true)
         |> assign(:ignore_case, Map.get(part_config, "ignore_case") == true)
         |> assign(:ignore_spelling, Map.get(part_config, "ignore_spelling") == true)
         |> assign(:ignore_punctuation, Map.get(part_config, "ignore_punctuation") == true)
         |> assign(:checkbox_scoring, Exams.checkbox_scoring(exam, part_id))}
    end
  end

  @impl true
  def handle_event(
        "set_group_verdict",
        %{"index" => idx_str, "text" => text, "verdict" => verdict},
        socket
      ) do
    idx = TaskyWeb.Params.int(idx_str)
    part_id = socket.assigns.current_part.id

    group_text =
      case text do
        "" -> nil
        t -> t
      end

    with %{} = block <- Enum.find(socket.assigns.answer_blocks, &(&1.index == idx)),
         %{} = group <- Enum.find(block.groups, &(&1.text == group_text)) do
      effective = effective_verdict(group)
      new_verdict = if effective == verdict, do: nil, else: verdict

      ids = Enum.map(group.students, & &1.submission_id)

      result =
        Exams.set_block_verdict_bulk(
          socket.assigns.current_scope,
          socket.assigns.exam,
          part_id,
          idx,
          new_verdict,
          ids
        )

      {:noreply, socket |> flash_bulk_verdict_result(result) |> refresh_assigns()}
    else
      _ -> {:noreply, socket}
    end
  end

  # J / L on a pattern card, or its buttons: every checkbox of the pattern gets
  # the same verdict; pressing the active one again hands the pattern back to
  # the system's per-checkbox defaults.
  def handle_event(
        "set_pattern_verdict",
        %{"group" => group, "pattern" => key, "verdict" => verdict},
        socket
      )
      when verdict in ["correct", "wrong"] do
    case find_pattern(socket, group, key) do
      nil ->
        {:noreply, socket}

      pattern ->
        new_verdict = if pattern.verdict == verdict, do: nil, else: verdict
        verdicts = Map.new(pattern.options, &{&1.index, new_verdict})

        {:noreply, save_pattern_verdicts(socket, pattern, verdicts)}
    end
  end

  # Drops every verdict of the pattern, so its checkboxes are scored by the
  # system's defaults and the question's rule again.
  def handle_event("reset_pattern_verdicts", %{"group" => group, "pattern" => key}, socket) do
    case find_pattern(socket, group, key) do
      nil ->
        {:noreply, socket}

      pattern ->
        verdicts = Map.new(pattern.options, &{&1.index, nil})
        {:noreply, save_pattern_verdicts(socket, pattern, verdicts)}
    end
  end

  # A click on one checkbox of a pattern flips just that checkbox between
  # counted right and counted wrong, for everyone with this pattern. Landing on
  # the system's default stores no explicit verdict, as with the group cards.
  def handle_event(
        "toggle_pattern_option",
        %{"group" => group, "pattern" => key, "index" => idx_str},
        socket
      ) do
    idx = TaskyWeb.Params.int(idx_str)

    with %{} = pattern <- find_pattern(socket, group, key),
         %{} = option <- Enum.find(pattern.options, &(&1.index == idx)) do
      flipped = if option.verdict == "correct", do: "wrong", else: "correct"
      verdict = if flipped == option.default_verdict, do: nil, else: flipped

      {:noreply, save_pattern_verdicts(socket, pattern, %{idx => verdict})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("open_pattern_manual_input", %{"group" => group, "pattern" => key}, socket) do
    case find_pattern(socket, group, key) do
      %{max_points: max} = pattern when is_number(max) ->
        prefill = if pattern.verdict == :manual, do: pattern.points, else: half_of(max)

        {:noreply,
         socket
         |> assign(:manual_input, %{pattern_group: group, pattern_key: key, value: prefill})
         |> push_event("focus-manual-input", %{id: pattern_manual_input_id(group, key)})}

      _ ->
        {:noreply, socket}
    end
  end

  # Manual points for a pattern are spread over its checkboxes (see
  # `CheckboxPatterns.distribute/2`): verdicts stay per checkbox, and the part
  # total is what the teacher typed.
  def handle_event(
        "set_pattern_manual",
        %{"group" => group, "pattern" => key, "points" => raw},
        socket
      ) do
    with {points, ""} <- Float.parse(String.trim(raw)),
         %{max_points: max} = pattern when is_number(max) <- find_pattern(socket, group, key) do
      verdicts =
        CheckboxPatterns.distribute(pattern, Grading.normalize_manual_points(points, max))

      {:noreply,
       socket
       |> assign(:manual_input, nil)
       |> save_pattern_verdicts(pattern, verdicts)}
    else
      _ -> {:noreply, assign(socket, :manual_input, nil)}
    end
  end

  def handle_event("open_manual_input", %{"index" => idx_str, "text" => text}, socket) do
    idx = TaskyWeb.Params.int(idx_str)
    group_text = if text == "", do: nil, else: text

    with %{} = block <- Enum.find(socket.assigns.answer_blocks, &(&1.index == idx)),
         %{} = group <- Enum.find(block.groups, &(&1.text == group_text)) do
      prefill =
        case effective_verdict(group) do
          v when is_number(v) -> v
          _ -> half_of(block.max_points)
        end

      {:noreply,
       socket
       |> assign(:manual_input, %{block_index: idx, group_text: group_text, value: prefill})
       |> push_event("focus-manual-input", %{id: manual_input_id(idx, group_text)})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_manual_input", _params, socket) do
    {:noreply, assign(socket, :manual_input, nil)}
  end

  def handle_event(
        "set_group_verdict_manual",
        %{"index" => idx_str, "text" => text, "points" => raw},
        socket
      ) do
    idx = TaskyWeb.Params.int(idx_str)
    part_id = socket.assigns.current_part.id
    group_text = if text == "", do: nil, else: text

    with {points, ""} <- Float.parse(String.trim(raw)),
         %{} = block <- Enum.find(socket.assigns.answer_blocks, &(&1.index == idx)),
         %{} = group <- Enum.find(block.groups, &(&1.text == group_text)) do
      ids = Enum.map(group.students, & &1.submission_id)

      result =
        Exams.set_block_verdict_bulk(
          socket.assigns.current_scope,
          socket.assigns.exam,
          part_id,
          idx,
          points,
          ids
        )

      {:noreply,
       socket
       |> assign(:manual_input, nil)
       |> flash_bulk_verdict_result(result)
       |> refresh_assigns()}
    else
      _ -> {:noreply, assign(socket, :manual_input, nil)}
    end
  end

  def handle_event("toggle_part_corrected", _params, socket) do
    exam = socket.assigns.exam
    part_id = socket.assigns.current_part.id
    scope = socket.assigns.current_scope

    if socket.assigns.is_corrected do
      Exams.unmark_part_corrected_bulk(scope, exam, part_id)
    else
      # Default verdicts for blocks the teacher left untouched, so points get
      # tallied even when the system's pre-judgement was never clicked. The
      # context persists them and marks every submission in one transaction.
      defaults =
        Map.new(Exams.list_exam_submissions(exam), fn submission ->
          per_block =
            Enum.reduce(socket.assigns.answer_blocks, %{}, fn block, acc ->
              block.groups
              |> Enum.find(fn g ->
                Enum.any?(g.students, &(&1.submission_id == submission.id))
              end)
              |> case do
                nil -> acc
                group -> Map.put(acc, block.index, group.default_verdict)
              end
            end)

          {submission.id, per_block}
        end)

      Exams.mark_part_corrected_bulk(scope, exam, part_id, defaults)
    end

    {:noreply, refresh_assigns(socket)}
  end

  @impl true
  def handle_info({:submission_corrected_parts_changed, _submission}, socket) do
    {:noreply, refresh_assigns(socket)}
  end

  def handle_info({:bulk_correction_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:bulk_correction_done, _}, socket), do: {:noreply, refresh_assigns(socket)}
  def handle_info({:bulk_correction_cancelled, _}, socket), do: {:noreply, socket}

  defp find_pattern(socket, group, key) do
    socket.assigns.answer_blocks
    # The list id comes back from the client as a string.
    |> Enum.filter(&(&1.type == "taskItem" and to_string(&1.group) == group))
    |> CheckboxPatterns.build(socket.assigns.checkbox_scoring)
    |> Enum.find(&(&1.key == key))
  end

  defp save_pattern_verdicts(socket, pattern, verdicts_by_index) do
    result =
      Exams.set_block_verdicts_bulk(
        socket.assigns.current_scope,
        socket.assigns.exam,
        socket.assigns.current_part.id,
        verdicts_by_index,
        Enum.map(pattern.students, & &1.submission_id)
      )

    socket |> flash_bulk_verdict_result(result) |> refresh_assigns()
  end

  # The return value used to be discarded outright, so a failed batch showed the
  # teacher nothing but a flicker back to the previous state.
  defp flash_bulk_verdict_result(socket, {:ok, _updated}), do: socket

  defp flash_bulk_verdict_result(socket, {:error, reason}) do
    put_flash(socket, :error, "Bewertung konnte nicht gespeichert werden (#{inspect(reason)}).")
  end

  defp refresh_assigns(socket) do
    %{exam: exam, current_part: part, parts: parts} = socket.assigns
    answer_blocks = Exams.list_part_answer_groups(exam, part.id)
    submissions = Exams.list_exam_submissions(exam)

    socket
    |> assign(:answer_blocks, answer_blocks)
    |> assign(:totals, compute_totals(answer_blocks))
    |> assign(:total_submissions, length(submissions))
    |> assign(:part_already_done, count_part_done(submissions, part.id))
    |> assign(:parts_done, compute_parts_done(submissions, parts))
    |> assign(:is_corrected, part_corrected?(submissions, part.id))
  end

  defp compute_parts_done([], _parts), do: MapSet.new()

  defp compute_parts_done(submissions, parts) do
    for p <- parts,
        Enum.all?(submissions, fn s -> p.id in (s.corrected_parts || []) end),
        into: MapSet.new(),
        do: p.id
  end

  defp part_corrected?([], _part_id), do: false

  defp part_corrected?(submissions, part_id) do
    Enum.all?(submissions, fn s -> part_id in (s.corrected_parts || []) end)
  end

  # ----------------------------------------------------------------- helpers

  defp effective_verdict(group) do
    case group.current_verdict do
      v when v in ["correct", "half", "wrong"] -> v
      v when is_number(v) -> v
      _ -> group.default_verdict
    end
  end

  defp half_of(max), do: Tasky.Grading.half_of(max)

  # Manual points go through `Grading.marker_verdict/2` — the same mapping the
  # answer markers use — so a manual 0 lands in "0 Punkte" and a manual full
  # score in "Volle Punkte". They all used to be counted as "Manuell", which put
  # the summary bar at odds with both the awarded points and the block markers.
  defp block_totals(block) do
    Enum.reduce(block.groups, %{correct: 0, half: 0, wrong: 0, total: 0}, fn g, acc ->
      v = g |> effective_verdict() |> Grading.marker_verdict(block.max_points)

      acc
      |> Map.update!(:total, &(&1 + g.count))
      |> Map.update!(verdict_atom(v), &(&1 + g.count))
    end)
  end

  defp compute_totals(blocks) do
    Enum.reduce(blocks, %{correct: 0, half: 0, wrong: 0, total: 0}, fn b, acc ->
      bt = block_totals(b)

      %{
        correct: acc.correct + bt.correct,
        half: acc.half + bt.half,
        wrong: acc.wrong + bt.wrong,
        total: acc.total + bt.total
      }
    end)
  end

  defp verdict_atom("correct"), do: :correct
  defp verdict_atom("half"), do: :half
  # Belt and braces: `marker_verdict/2` only returns a number when it was handed
  # one together with an unknown block maximum.
  defp verdict_atom(v) when is_number(v), do: :half
  defp verdict_atom(_), do: :wrong

  defp percent(_n, 0), do: 0
  defp percent(n, total), do: n * 100 / total

  defp count_part_done(submissions, part_id) do
    Enum.count(submissions, fn s -> part_id in (s.corrected_parts || []) end)
  end

  defp student_name(%{lastname: nil, firstname: nil}), do: "—"
  defp student_name(%{lastname: nil, firstname: f}), do: f
  defp student_name(%{lastname: l}), do: l
end
