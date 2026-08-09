defmodule TaskyWeb.Student.FeedbackLive do
  @moduledoc """
  Der Feedback-Briefkasten aus Sicht der Lernenden: Text schreiben, abschicken,
  fertig.

  Nach dem Absenden wird der Text bewusst nicht zurückgespiegelt und es gibt
  keine Liste eigener Nachrichten — der Kanal soll sich nicht wie ein Postfach
  anfühlen, das jemand mitliest.

  Die Erklärtexte sagen, was tatsächlich gilt ("die Lehrperson sieht deinen
  Namen nicht"), und versprechen keine Anonymität, die das Datenmodell nicht
  hergibt.
  """
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Feedback
  alias Tasky.Feedback.Message

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/student/courses/#{@course}/feedback"}
    >
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-4 mb-8">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-center justify-between mb-2">
            <.breadcrumbs crumbs={[
              %{label: "Meine Kurse", navigate: ~p"/student/courses"},
              %{label: @course.name, navigate: ~p"/student/courses/#{@course}"},
              %{label: "Feedback"}
            ]} />
          </div>

          <div class="flex items-center gap-3 mb-2">
            <.back_button
              navigate={~p"/student/courses/#{@course}"}
              tooltip={"Zurück zu #{@course.name}"}
            />
            <h1 class="font-serif text-[36px] text-stone-900 leading-[1.1] font-normal">
              Feedback zum Kurs
            </h1>
          </div>
        </div>
      </div>

      <div class="max-w-3xl mx-auto px-8 pb-8">
        <%= if @sent do %>
          <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] px-8 py-12 text-center">
            <div class="w-14 h-14 rounded-[14px] bg-emerald-50 flex items-center justify-center text-emerald-500 mx-auto mb-5">
              <.icon name="hero-check" class="w-7 h-7" />
            </div>

            <h2 class="text-lg font-semibold text-stone-800 mb-2">Danke für deine Rückmeldung</h2>

            <p class="text-sm text-stone-500 max-w-[400px] mx-auto leading-[1.7]">
              Deine Nachricht ist bei der Lehrperson angekommen – ohne deinen Namen.
            </p>

            <div class="flex items-center justify-center gap-3 mt-7">
              <button
                type="button"
                phx-click="write_another"
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
              >
                Weitere Nachricht schreiben
              </button>

              <.link
                navigate={~p"/student/courses/#{@course}"}
                class="inline-flex items-center gap-2 text-stone-500 text-sm font-medium px-5 py-2.5 rounded-[10px] transition-all duration-150 hover:bg-stone-100 hover:text-stone-700"
              >
                Zurück zum Kurs
              </.link>
            </div>
          </div>
        <% else %>
          <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-start gap-3">
                <div class="w-9 h-9 rounded-[10px] bg-sky-50 flex items-center justify-center text-sky-500 shrink-0">
                  <.icon name="hero-inbox" class="w-5 h-5" />
                </div>
                <div class="text-sm text-stone-600 leading-[1.7]">
                  Schreib der Lehrperson, was in diesem Kurs gut läuft oder was dich stört.
                  <span class="font-semibold text-stone-700">
                    Die Lehrperson sieht deinen Namen nicht
                  </span>
                  – nur den Text und das Datum. Du bekommst keine Antwort auf diesem Weg.
                </div>
              </div>
            </div>

            <div class="p-6">
              <.form for={@form} id="feedback-form" phx-change="validate" phx-submit="save">
                <.input
                  field={@form[:body]}
                  type="textarea"
                  label="Deine Nachricht"
                  placeholder="Zum Beispiel: Das Tempo im Kapitel 3 war zu hoch für mich …"
                  rows="8"
                  maxlength={Message.max_body_chars()}
                  phx-debounce="300"
                />

                <p class="text-xs text-stone-400 mt-2">
                  {@char_count} / {Message.max_body_chars()} Zeichen
                </p>

                <div class="flex items-center gap-3 pt-5 mt-5 border-t border-stone-100">
                  <.button
                    phx-disable-with="Wird gesendet..."
                    class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                  >
                    Anonym abschicken
                  </.button>

                  <.link
                    navigate={~p"/student/courses/#{@course}"}
                    class="inline-flex items-center gap-2 text-stone-500 text-sm font-medium px-5 py-2.5 rounded-[10px] transition-all duration-150 hover:bg-stone-100 hover:text-stone-700"
                  >
                    Abbrechen
                  </.link>
                </div>
              </.form>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    student_id = socket.assigns.current_scope.user.id
    course_id = TaskyWeb.Params.int(id)
    course = course_id && Courses.get_enrolled_course(student_id, course_id)

    case course do
      %{feedback_box_enabled: true} = course ->
        {:ok,
         socket
         |> assign(:page_title, "Feedback zum Kurs")
         |> assign(:course, course)
         |> reset_form()}

      %{} ->
        {:ok,
         socket
         |> put_flash(:error, "Der Feedback-Briefkasten dieses Kurses ist geschlossen.")
         |> push_navigate(to: ~p"/student/courses/#{course}")}

      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Kurs nicht gefunden.")
         |> push_navigate(to: ~p"/student/courses")}
    end
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket) do
    changeset = Feedback.change_message(%Message{}, params)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign(:char_count, String.length(params["body"] || ""))}
  end

  def handle_event("save", %{"message" => params}, socket) do
    scope = socket.assigns.current_scope

    case Feedback.create_message(scope, socket.assigns.course.id, params) do
      {:ok, _message} ->
        {:noreply, assign(socket, :sent, true)}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Du hast gerade mehrere Nachrichten geschickt. Bitte versuche es in ein paar Minuten nochmals."
         )}

      {:error, :disabled} ->
        {:noreply,
         socket
         |> put_flash(:error, "Der Feedback-Briefkasten dieses Kurses ist geschlossen.")
         |> push_navigate(to: ~p"/student/courses/#{socket.assigns.course}")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Kurs nicht gefunden.")
         |> push_navigate(to: ~p"/student/courses")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
    end
  end

  def handle_event("write_another", _params, socket) do
    {:noreply, reset_form(socket)}
  end

  # Private

  defp reset_form(socket) do
    socket
    |> assign(:sent, false)
    |> assign(:char_count, 0)
    |> assign(:form, to_form(Feedback.change_message()))
  end
end
