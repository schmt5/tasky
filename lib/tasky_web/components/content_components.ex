defmodule TaskyWeb.ContentComponents do
  @moduledoc """
  Presentational components and draft helpers shared by the two content-
  management surfaces (`TaskyWeb.ExamLive.Content` and
  `TaskyWeb.TaskLive.Content`). Both build the same "Dateien" tab (upload-field
  editor) and tab navigation over different domains (exams vs. tasks); the
  shared chrome and the pure upload-field-draft helpers live here so the two
  copies can't drift.

  The `handle_event`/domain calls stay in each LiveView (they target different
  contexts); only the domain-agnostic pieces are shared.
  """
  use TaskyWeb, :html

  import TaskyWeb.FileComponents, only: [type_chip_label: 1]

  alias Tasky.Uploads

  @doc """
  A pill-style tab link for the content-management tab bar. Patches to
  `@patch`; the parent LiveView owns the routing.
  """
  attr :label, :string, required: true
  attr :active, :boolean, required: true
  attr :patch, :string, required: true

  def tab_link(assigns) do
    ~H"""
    <.link
      patch={@patch}
      class={[
        "px-3 py-1 rounded-md text-sm font-medium transition-colors",
        if(@active,
          do: "bg-white text-sky-700 shadow-sm",
          else: "text-sky-600/70 hover:text-sky-800"
        )
      ]}
    >
      {@label}
    </.link>
    """
  end

  @doc """
  The upload-field editor form (label, instruction, allowed types, required
  flag). Emits `field_draft_changed`/`save_upload_field`/`toggle_field_type`/
  `cancel_field_edit` to the parent LiveView, which owns the draft state and
  the domain writes.
  """
  attr :draft, :map, required: true
  attr :label_placeholder, :string, default: "z. B. Aufsatz, …"

  def upload_field_form(assigns) do
    ~H"""
    <form phx-change="field_draft_changed" phx-submit="save_upload_field" class="space-y-4">
      <div>
        <label class="block text-sm font-medium text-stone-600 mb-1.5">Bezeichnung</label>
        <input
          type="text"
          name="label"
          value={@draft["label"]}
          placeholder={@label_placeholder}
          maxlength="255"
          class="w-full text-sm text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-sky-300 focus:border-sky-400"
        />
        <p :if={@draft["label_error"]} class="text-xs text-red-600 mt-1">
          {@draft["label_error"]}
        </p>
      </div>

      <div>
        <label class="block text-sm font-medium text-stone-600 mb-1.5">
          Anweisung (optional)
        </label>
        <input
          type="text"
          name="instruction"
          value={@draft["instruction"]}
          placeholder="z. B. Lade deinen Aufsatz als PDF hoch."
          maxlength="1000"
          class="w-full text-sm text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-sky-300 focus:border-sky-400"
        />
      </div>

      <div>
        <label class="block text-sm font-medium text-stone-600 mb-1.5">Erlaubte Dateitypen</label>
        <div class="flex items-center gap-2 flex-wrap">
          <button
            :for={type <- Uploads.answer_type_keys()}
            type="button"
            phx-click="toggle_field_type"
            phx-value-type={type}
            class={[
              "text-sm font-semibold px-3.5 py-2 rounded-lg border transition-all duration-150",
              if(type in @draft["allowed_types"],
                do: "bg-sky-50 border-sky-300 text-sky-700",
                else: "bg-white border-stone-200 text-stone-500 hover:border-stone-300"
              )
            ]}
          >
            {type_chip_label(type)}
          </button>
        </div>
        <p :if={@draft["types_error"]} class="text-xs text-red-600 mt-1">
          {@draft["types_error"]}
        </p>
      </div>

      <label class="flex items-center gap-3 cursor-pointer">
        <input type="hidden" name="required" value="false" />
        <input
          type="checkbox"
          name="required"
          value="true"
          checked={@draft["required"] == "true"}
          class="w-[18px] h-[18px] rounded-md border-stone-300 text-sky-500 focus:ring-sky-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150"
        />
        <span class="text-sm font-medium text-stone-700">Pflichtfeld – Abgabe erforderlich</span>
      </label>

      <div class="flex items-center justify-end gap-3 pt-1">
        <button
          type="button"
          phx-click="cancel_field_edit"
          class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
        >
          Abbrechen
        </button>
        <button
          type="submit"
          class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
        >
          Speichern
        </button>
      </div>
    </form>
    """
  end

  ## Upload-field-draft helpers (pure; shared by both content LiveViews)

  @doc "A blank upload-field draft (PDF selected, optional, not required)."
  def new_field_draft do
    %{"label" => "", "instruction" => "", "required" => "false", "allowed_types" => ["pdf"]}
  end

  @doc "Nil for an empty string, the value otherwise (for optional fields)."
  def presence(""), do: nil
  def presence(value), do: value

  @doc """
  Adds `message` under `key` in the draft when the changeset has an error on
  `field`; leaves the draft untouched otherwise.
  """
  def put_draft_error(draft, changeset, field, key, message) do
    if Keyword.has_key?(changeset.errors, field),
      do: Map.put(draft, key, message),
      else: draft
  end
end
