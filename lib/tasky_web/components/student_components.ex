defmodule TaskyWeb.StudentComponents do
  @moduledoc """
  Presentational components shared by the two student answer surfaces
  (`TaskyWeb.Guest.ExamLive` and `TaskyWeb.Student.TaskLive`). These views
  operate on different domains (exams vs. tasks) but present the same chrome;
  keeping the shared chrome here stops the two copies from drifting.
  """
  use TaskyWeb, :html

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
end
