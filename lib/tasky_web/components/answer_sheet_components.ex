defmodule TaskyWeb.AnswerSheetComponents do
  @moduledoc """
  Das Antwortblatt der Lernenden: Prüfung oder Lerneinheit als normales HTML
  mit nativen Antwortfeldern (`TaskyWeb.ExamDocHTML`), gespeichert vom Hook
  `ExamAnswersForm` über HTTP.

  Lehrpersonen schreiben weiter im Tiptap-Editor; die Lehrervorschau zeigt
  dieselbe Komponente ohne `save_url`.
  """
  use TaskyWeb, :html

  alias TaskyWeb.ExamDocHTML

  @doc """
  Rendert das Antwortblatt.

  Ohne `save_url` wird nichts gespeichert — die Rücklese-Ansicht (`disabled`)
  und die Lehrervorschau. Die Felder liegen in keinem `<.form>`: Gespeichert
  wird über den Hook, nicht über LiveView-Events, damit es auch bei getrenntem
  Socket weitergeht.
  """
  attr :id, :string, required: true
  attr :doc, :map, required: true
  attr :save_url, :string, default: nil
  attr :disabled, :boolean, default: false

  def answer_sheet(assigns) do
    ~H"""
    <div
      id={@id}
      class="exam-doc-sheet"
      phx-hook="ExamAnswersForm"
      phx-update="ignore"
      data-save-url={@save_url}
    >
      <div class="exam-doc">
        {ExamDocHTML.render(@doc, id: @id, disabled: @disabled)}
      </div>
      <div
        :if={@save_url}
        class="exam-doc__status"
        data-save-status
        role="status"
        aria-live="polite"
      >
      </div>
    </div>
    """
  end
end
