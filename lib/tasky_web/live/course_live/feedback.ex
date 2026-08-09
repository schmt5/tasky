defmodule TaskyWeb.CourseLive.Feedback do
  @moduledoc """
  Der Feedback-Briefkasten eines Kurses aus Sicht der Lehrperson.

  Zeigt Text, Datum und Lesestatus. Die Absender kommen hier gar nicht erst an:
  `Tasky.Feedback.list_messages/2` selektiert die `student_id` nicht.

  Bewusst nur das Datum, keine Uhrzeit — in einer kleinen Klasse verrät ein
  "14:03 Uhr" schnell, wer geschrieben hat.
  """
  use TaskyWeb, :live_view

  # `TaskyWeb.UI` hängt nicht in den globalen html_helpers — lokal importieren.
  import TaskyWeb.UI, only: [card_header: 1, empty_state: 1]

  alias Tasky.Courses
  alias Tasky.Feedback

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/courses/#{@course}/feedback"}
    >
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Kurse", navigate: ~p"/courses"},
              %{label: @course.name, navigate: ~p"/courses/#{@course}"},
              %{label: "Feedback-Briefkasten"}
            ]} />
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button
              navigate={~p"/courses/#{@course}"}
              tooltip={"Zurück zu #{@course.name}"}
            />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              Feedback-Briefkasten
            </h1>
          </div>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Rückmeldungen der Lernenden zu «{@course.name}» – ohne Namen, nur mit Datum.
          </p>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <%!-- Hinweis, solange der Briefkasten geschlossen ist --%>
        <div
          :if={!@course.feedback_box_enabled}
          class="flex items-start gap-3 bg-amber-50 border border-amber-200 rounded-[12px] px-5 py-4"
        >
          <.icon name="hero-lock-closed" class="w-5 h-5 text-amber-500 shrink-0 mt-0.5" />
          <div class="text-sm text-amber-900 leading-relaxed">
            <span class="font-semibold">Der Briefkasten ist geschlossen.</span>
            Lernende können aktuell nichts schreiben. Bereits eingegangene Nachrichten bleiben hier sichtbar.
            <.link
              navigate={~p"/courses/#{@course}/edit?return_to=show"}
              class="font-semibold underline underline-offset-2 hover:text-amber-700"
            >
              Kurs bearbeiten und Briefkasten öffnen
            </.link>
          </div>
        </div>

        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <.card_header
            title="Nachrichten"
            subtitle={message_count_label(@message_count, @unread_count)}
          />

          <ul
            :if={@message_count > 0}
            id="feedback-messages"
            phx-update="stream"
            class="divide-y divide-stone-100"
          >
            <li
              :for={{dom_id, message} <- @streams.messages}
              id={dom_id}
              class={[
                "px-6 py-5 border-l-[3px] transition-colors duration-150",
                if(message.read_at,
                  do: "border-l-transparent",
                  else: "border-l-amber-400 bg-amber-50/30"
                )
              ]}
            >
              <div class="flex items-start justify-between gap-4 mb-2">
                <div class="flex items-center gap-2.5">
                  <span class="text-[13px] font-semibold text-stone-500">
                    {Calendar.strftime(message.inserted_at, "%d.%m.%Y")}
                  </span>
                  <span
                    :if={!message.read_at}
                    class="inline-flex items-center bg-amber-100 text-amber-700 text-[11px] font-semibold px-2 py-0.5 rounded-full"
                  >
                    Neu
                  </span>
                </div>

                <div class="flex items-center gap-1 shrink-0">
                  <button
                    type="button"
                    phx-click="toggle_read"
                    phx-value-id={message.id}
                    class="inline-flex items-center gap-1.5 text-stone-500 text-[13px] font-medium px-2.5 py-1 rounded-[6px] transition-colors duration-150 hover:bg-stone-100 hover:text-stone-700"
                  >
                    <.icon
                      name={if message.read_at, do: "hero-arrow-uturn-left", else: "hero-check"}
                      class="w-4 h-4"
                    />
                    {if message.read_at, do: "Als ungelesen", else: "Als gelesen"}
                  </button>

                  <button
                    type="button"
                    phx-click="delete"
                    phx-value-id={message.id}
                    data-confirm="Diese Nachricht wirklich löschen?"
                    class="inline-flex items-center text-stone-400 p-1.5 rounded-[6px] transition-colors duration-150 hover:bg-red-50 hover:text-red-500"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                </div>
              </div>

              <%!-- Plain text: HEEx escapt, hier wird nie `raw/1` verwendet.
                   `phx-no-format` hält den Ausdruck bündig im Tag — sonst
                   rendert `whitespace-pre-wrap` die Einrückung des Templates
                   als führende Leerzeichen mit. --%>
              <p
                phx-no-format
                class="text-[15px] text-stone-700 leading-[1.7] whitespace-pre-wrap break-words"
              >{message.body}</p>
            </li>
          </ul>

          <.empty_state
            :if={@message_count == 0}
            icon_name="hero-inbox"
            title="Noch keine Rückmeldungen"
            description="Sobald Lernende etwas in den Briefkasten schreiben, erscheint es hier – ohne Namen."
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    course = Courses.get_course!(scope, id)
    {:ok, messages} = Feedback.list_messages(scope, course)

    {:ok,
     socket
     |> assign(:page_title, "Feedback-Briefkasten")
     |> assign(:course, course)
     |> assign(:message_count, length(messages))
     |> assign(:unread_count, Enum.count(messages, &is_nil(&1.read_at)))
     |> stream(:messages, messages)}
  end

  @impl true
  def handle_event("toggle_read", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    with message_id when is_integer(message_id) <- TaskyWeb.Params.int(id),
         {:ok, message} <- Feedback.toggle_read(scope, message_id) do
      {:noreply,
       socket
       |> update(:unread_count, &if(message.read_at, do: &1 - 1, else: &1 + 1))
       |> stream_insert(:messages, message)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Die Nachricht konnte nicht geändert werden.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    message_id = TaskyWeb.Params.int(id)

    case message_id && Feedback.delete_message(scope, message_id) do
      {:ok, message} ->
        {:noreply,
         socket
         |> update(:message_count, &(&1 - 1))
         |> update(:unread_count, &if(message.read_at, do: &1, else: &1 - 1))
         |> stream_delete_by_dom_id(:messages, "messages-#{message_id}")
         |> put_flash(:info, "Nachricht gelöscht.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Die Nachricht konnte nicht gelöscht werden.")}
    end
  end

  # Private

  defp message_count_label(0, _unread), do: "Noch keine Nachrichten"

  defp message_count_label(count, 0),
    do: "#{count} #{pluralize(count)}, alle gelesen"

  defp message_count_label(count, unread),
    do: "#{count} #{pluralize(count)}, davon #{unread} ungelesen"

  defp pluralize(1), do: "Nachricht"
  defp pluralize(_), do: "Nachrichten"
end
