defmodule TaskyWeb.Guest.ExamLive do
  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.guest flash={@flash}>
      <%= cond do %>
        <% @exam.status == "open" -> %>
          <%!-- Waiting Room --%>
          <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
            <div class="w-full max-w-lg">
              <div class="text-center mb-8">
                <div class="w-16 h-16 rounded-2xl bg-amber-50 flex items-center justify-center mx-auto mb-4">
                  <.icon name="hero-clock" class="w-8 h-8 text-amber-500 animate-pulse" />
                </div>
                <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
                  Warteraum
                </h1>
                <p class="text-stone-500 text-sm">
                  Hallo <span class="font-semibold text-stone-700">{@submission.firstname} {@submission.lastname}</span>,
                  du bist im Warteraum für die Prüfung.
                </p>
              </div>

              <%!-- Exam Info Card --%>
              <div class="bg-white rounded-2xl border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-6 mb-6">
                <div class="flex items-center gap-3 mb-4">
                  <div class="w-10 h-10 rounded-xl bg-sky-50 flex items-center justify-center shrink-0">
                    <.icon name="hero-academic-cap" class="w-5 h-5 text-sky-500" />
                  </div>
                  <div>
                    <h2 class="text-lg font-semibold text-stone-800">{@exam.name}</h2>
                    <p class="text-xs text-stone-400">Lehrperson: {@exam.teacher.email}</p>
                  </div>
                </div>

                <div class="bg-amber-50 rounded-xl p-4 border border-amber-100">
                  <div class="flex items-start gap-3">
                    <.icon
                      name="hero-information-circle"
                      class="w-5 h-5 text-amber-500 shrink-0 mt-0.5"
                    />
                    <p class="text-sm text-amber-700 leading-relaxed">
                      Die Prüfung hat noch nicht begonnen. Bitte warte, bis die Lehrperson die Prüfung startet.
                      Diese Seite wird sich automatisch aktualisieren.
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% @exam.status == "running" and @submission.submitted -> %>
          <%!-- Already Submitted --%>
          <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
            <div class="text-center">
              <div class="w-16 h-16 rounded-2xl bg-emerald-50 flex items-center justify-center mx-auto mb-4">
                <.icon name="hero-check-circle" class="w-8 h-8 text-emerald-500" />
              </div>
              <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
                Prüfung abgegeben
              </h1>
              <p class="text-stone-500 text-sm">
                Du hast deine Prüfung <span class="font-semibold text-stone-700">{@exam.name}</span>
                erfolgreich abgegeben.
              </p>
              <p class="text-stone-400 text-xs mt-2">
                Du kannst diese Seite jetzt schliessen.
              </p>
            </div>
          </div>
        <% @exam.status == "running" -> %>
          <%!-- Running Exam --%>
          <div class="max-w-4xl mx-auto px-4 py-8">
            <div class="mb-8">
              <div class="flex items-center justify-between">
                <div>
                  <div class="flex items-center gap-3 mb-2">
                    <span class="inline-flex items-center text-xs font-semibold px-3 py-1 rounded-full bg-emerald-100 text-emerald-700">
                      Laufend
                    </span>
                  </div>
                  <h1 class="font-serif text-3xl text-stone-900 font-normal mb-1">
                    {@exam.name}
                  </h1>
                  <p class="text-sm text-stone-500">
                    Teilnehmer: {@submission.firstname} {@submission.lastname}
                  </p>
                </div>
                <button
                  id="submit-exam-btn"
                  type="button"
                  phx-click="show_submit_modal"
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-paper-airplane" class="w-4 h-4" /> Abgeben
                </button>
              </div>
            </div>

            <%!-- Exam Content --%>
            <div class="bg-white rounded-2xl border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
              <div class="p-6 border-b border-stone-100">
                <h2 class="text-lg font-semibold text-stone-800">Prüfungsinhalt</h2>
              </div>
              <div class="p-6">
                <%= if @exam.content && @exam.content != %{} do %>
                  <pre class="text-sm text-stone-600 bg-stone-50 p-4 rounded-lg border border-stone-200 overflow-x-auto"><code phx-no-curly-interpolation>{Jason.encode!(@exam.content, pretty: true)}</code></pre>
                <% else %>
                  <p class="text-sm text-stone-400">Kein Inhalt vorhanden.</p>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Submit Confirmation Modal --%>
          <%= if @show_submit_modal do %>
            <dialog
              id="submit-exam-modal"
              class="modal modal-open"
              phx-window-keydown="close_submit_modal"
              phx-key="escape"
            >
              <div class="modal-backdrop bg-stone-900/50" phx-click="close_submit_modal"></div>
              <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
                <div class="p-6 border-b border-stone-100">
                  <div class="flex items-center gap-3">
                    <div class="w-10 h-10 rounded-xl bg-amber-50 flex items-center justify-center shrink-0">
                      <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-amber-500" />
                    </div>
                    <div>
                      <h3 class="text-lg font-semibold text-stone-800">Prüfung abgeben</h3>
                      <p class="text-xs text-stone-400 mt-0.5">Bitte bestätige die Abgabe.</p>
                    </div>
                  </div>
                </div>
                <div class="p-6">
                  <p class="text-sm text-stone-600 leading-relaxed">
                    Möchtest du die Prüfung
                    <span class="font-semibold text-stone-800">{@exam.name}</span>
                    jetzt abgeben?
                  </p>
                  <div class="bg-amber-50 rounded-lg p-3 mt-4 border border-amber-100">
                    <div class="flex items-start gap-2.5">
                      <.icon
                        name="hero-exclamation-triangle"
                        class="w-4 h-4 text-amber-500 shrink-0 mt-0.5"
                      />
                      <p class="text-xs text-amber-700 leading-relaxed">
                        Nach der Abgabe kannst du keine Änderungen mehr vornehmen.
                      </p>
                    </div>
                  </div>
                </div>
                <div class="p-6 pt-0 flex items-center justify-end gap-3">
                  <button
                    id="cancel-submit-btn"
                    type="button"
                    phx-click="close_submit_modal"
                    class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
                  >
                    Abbrechen
                  </button>
                  <button
                    id="confirm-submit-btn"
                    type="button"
                    phx-click="confirm_submit_exam"
                    class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                  >
                    <.icon name="hero-paper-airplane" class="w-4 h-4" /> Jetzt abgeben
                  </button>
                </div>
              </div>
            </dialog>
          <% end %>
        <% @exam.status in ["finished", "archived"] -> %>
          <%!-- Finished --%>
          <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
            <div class="text-center">
              <div class="w-16 h-16 rounded-2xl bg-purple-50 flex items-center justify-center mx-auto mb-4">
                <.icon name="hero-check-circle" class="w-8 h-8 text-purple-500" />
              </div>
              <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
                Prüfung beendet
              </h1>
              <p class="text-stone-500 text-sm">
                Die Prüfung <span class="font-semibold text-stone-700">{@exam.name}</span>
                wurde beendet.
              </p>
            </div>
          </div>
        <% true -> %>
          <%!-- Fallback (draft or other) --%>
          <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
            <div class="text-center">
              <div class="w-16 h-16 rounded-2xl bg-stone-100 flex items-center justify-center mx-auto mb-4">
                <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-stone-400" />
              </div>
              <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
                Prüfung nicht verfügbar
              </h1>
              <p class="text-stone-500 text-sm">
                Diese Prüfung ist aktuell nicht verfügbar.
              </p>
            </div>
          </div>
      <% end %>
    </Layouts.guest>
    """
  end

  @impl true
  def mount(%{"exam_token" => exam_token}, _session, socket) do
    submission = Exams.get_exam_submission_by_token!(exam_token)
    exam = submission.exam

    if connected?(socket) do
      Exams.subscribe_exam(exam.id)

      if exam.status in ["open", "running"] do
        {:ok, _} =
          TaskyWeb.Presence.track(
            self(),
            "exam_waiting:#{exam.id}",
            submission.exam_token,
            %{firstname: submission.firstname, lastname: submission.lastname}
          )
      end
    end

    {:ok,
     socket
     |> assign(:page_title, exam.name)
     |> assign(:exam, exam)
     |> assign(:submission, submission)
     |> assign(:show_submit_modal, false)}
  end

  @impl true
  def handle_event("show_submit_modal", _params, socket) do
    {:noreply, assign(socket, :show_submit_modal, true)}
  end

  def handle_event("close_submit_modal", _params, socket) do
    {:noreply, assign(socket, :show_submit_modal, false)}
  end

  def handle_event("confirm_submit_exam", _params, socket) do
    case Exams.submit_exam_submission(socket.assigns.submission) do
      {:ok, updated_submission} ->
        {:noreply,
         socket
         |> assign(:submission, updated_submission)
         |> assign(:show_submit_modal, false)}

      {:error, :exam_not_running} ->
        {:noreply,
         socket
         |> put_flash(:error, "Die Prüfung kann nicht mehr abgegeben werden.")
         |> assign(:show_submit_modal, false)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Fehler beim Abgeben der Prüfung.")
         |> assign(:show_submit_modal, false)}
    end
  end

  @impl true
  def handle_info({:exam_status_changed, updated_exam}, socket) do
    {:noreply, assign(socket, :exam, updated_exam)}
  end
end
