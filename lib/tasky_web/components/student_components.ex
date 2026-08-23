defmodule TaskyWeb.StudentComponents do
  @moduledoc """
  Presentational components shared by the two student answer surfaces
  (`TaskyWeb.Guest.ExamLive` and `TaskyWeb.Student.TaskLive`). These views
  operate on different domains (exams vs. tasks) but present the same chrome;
  keeping the shared chrome here stops the two copies from drifting.
  """
  use TaskyWeb, :html

  @success_emojis ["🎉", "🚀", "⭐", "🎊", "✨", "🏆", "🎯", "💫", "🌟", "👏"]

  @doc """
  A pill-style tab button for the student "Aufgabe / Dateien" toggle. Emits
  the `switch_student_tab` event with the given `tab` to the parent LiveView.
  """
  attr :label, :string, required: true
  attr :tab, :string, required: true
  attr :active, :boolean, required: true

  def student_tab_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="switch_student_tab"
      phx-value-tab={@tab}
      class={[
        "px-3 py-1 rounded-md text-sm font-medium transition-colors",
        if(@active,
          do: "bg-white text-sky-700 shadow-sm",
          else: "text-sky-600/70 hover:text-sky-800"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  @doc """
  Pick one of the celebration emojis for a completion screen.

  Call it once per mount and keep the result in an assign — rolling it inside
  `render/1` would hand the participant a different emoji on every diff.
  """
  def success_emoji, do: Enum.random(@success_emojis)

  @doc """
  The screen a participant lands on after finishing something: a big bouncing
  emoji, a serif headline, one calm sentence and a row of ways onward.

  Used for a completed learning unit and for both exam end states, so that the
  moment feels the same wherever it happens.

      <.completion_panel emoji={@success_emoji}>
        <:title>Aufgabe <em class="italic text-emerald-500">eingereicht.</em></:title>
        <:subtitle>Sehr gute Arbeit.</:subtitle>
        <:actions><.link navigate={~p"/"}>Weiter</.link></:actions>
      </.completion_panel>
  """
  attr :emoji, :string, required: true
  attr :class, :any, default: nil

  slot :title, required: true
  slot :subtitle, required: true
  slot :inner_block, doc: "optional extra content between the text and the actions"
  slot :actions

  def completion_panel(assigns) do
    ~H"""
    <div class={["border border-stone-200 rounded-[18px] bg-white shadow-sm overflow-hidden", @class]}>
      <div class="flex flex-col items-center text-center px-10 py-16 bg-white">
        <div class="text-[56px] leading-none mb-1.5 animate-bounce">
          {@emoji}
        </div>

        <div class="w-6 h-[1.5px] bg-stone-200 rounded-sm my-5"></div>

        <h3 class="font-serif text-[34px] font-normal text-stone-900 leading-tight mb-2.5 animate-[fadeUp_0.4s_0.15s_ease_both]">
          {render_slot(@title)}
        </h3>

        <p class="text-[14px] text-stone-400 leading-relaxed max-w-[320px] mb-8 animate-[fadeUp_0.4s_0.2s_ease_both]">
          {render_slot(@subtitle)}
        </p>

        {render_slot(@inner_block)}

        <div
          :if={@actions != []}
          class="flex items-center gap-3 animate-[fadeUp_0.4s_0.25s_ease_both]"
        >
          {render_slot(@actions)}
        </div>
      </div>
    </div>
    """
  end
end
