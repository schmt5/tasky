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

  attr :audio, :map,
    default: nil,
    doc: """
    Audio-Blöcke der Lernenden: `%{api: url, file: url, plays: audio_plays}`.
    Unter `api/<audioId>/start|progress|finish` zählt der Server die
    Durchgänge, unter `file/<audioId>` liefert er die Datei. Ohne (Vorschau)
    spielt der Player die Datei der Lehrperson ohne Limite.
    """

  def answer_sheet(assigns) do
    ~H"""
    <div
      id={@id}
      class="exam-doc-sheet"
      phx-hook="ExamAnswersForm"
      phx-update="ignore"
      data-save-url={@save_url}
      data-audio-api={@audio && @audio.api}
      data-audio-file={@audio && @audio.file}
    >
      <div class="exam-doc">
        {ExamDocHTML.render(@doc,
          id: @id,
          disabled: @disabled,
          audio_plays: @audio && @audio.plays,
          teacher_audio: is_nil(@audio)
        )}
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
