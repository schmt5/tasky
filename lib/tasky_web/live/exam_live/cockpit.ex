defmodule TaskyWeb.ExamLive.Cockpit do
  use TaskyWeb, :live_view

  alias Tasky.Exams

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
              %{label: "Cockpit"}
            ]} />
          </div>

          <div class="flex items-center justify-between">
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
              Cockpit
            </h1>

            <%= if @exam.status == "open" do %>
              <button
                type="button"
                phx-click="show_confirm"
                phx-value-action="start_exam"
                class="inline-flex items-center gap-2.5 bg-emerald-500 text-white text-sm font-semibold px-6 py-3 rounded-xl shadow-[0_2px_12px_rgba(16,185,129,0.3)] transition-all duration-150 hover:bg-emerald-600 active:scale-[0.98]"
              >
                <.icon name="hero-play" class="w-5 h-5" /> Prüfung starten
              </button>
            <% end %>
            <%= if @exam.status == "running" do %>
              <button
                type="button"
                phx-click="show_confirm"
                phx-value-action="end_exam"
                class="inline-flex items-center gap-2.5 bg-red-500 text-white text-sm font-semibold px-6 py-3 rounded-xl shadow-[0_2px_12px_rgba(239,68,68,0.3)] transition-all duration-150 hover:bg-red-600 active:scale-[0.98]"
              >
                <.icon name="hero-stop" class="w-5 h-5" /> Prüfung beenden
              </button>
            <% end %>
          </div>

          <.exam_status_chip status={@exam.status} />
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <%= if @exam.status != "finished" do %>
          <%!-- Enrollment Token Card --%>
          <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-[10px] flex items-center justify-center shrink-0 bg-amber-50 text-amber-500">
                  <.icon name="hero-key" class="w-5 h-5" />
                </div>
                <div>
                  <h2 class="text-lg font-semibold text-stone-800">Einschreibelink</h2>
                  <p class="text-sm text-stone-500 mt-0.5">
                    Teile diesen Link mit Lernenden, damit sie sich für die Prüfung einschreiben können.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6">
              <%= if @exam.enrollment_token do %>
                <div class="flex items-center gap-3">
                  <input
                    id="enrollment-token-field"
                    type="text"
                    value={"http://localhost:4000/guest/enroll/#{@exam.enrollment_token}"}
                    readonly
                    class="flex-1 font-mono text-sm text-stone-700 bg-stone-50 border border-stone-200 rounded-lg px-4 py-2.5 focus:outline-none focus:ring-2 focus:ring-amber-300 focus:border-amber-400 select-all cursor-text"
                    phx-hook=".CopyToClipboard"
                  />
                  <button
                    id="copy-token-btn"
                    type="button"
                    phx-hook=".CopyButton"
                    data-target="enrollment-token-field"
                    class="inline-flex items-center gap-2 bg-amber-500 text-white text-sm font-semibold px-4 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(245,158,11,0.25)] transition-all duration-150 hover:bg-amber-600 active:scale-[0.98]"
                  >
                    <.icon name="hero-clipboard-document" class="w-4 h-4" />
                    <span>Kopieren</span>
                  </button>
                </div>
              <% else %>
                <div class="flex items-center gap-3 text-stone-400">
                  <.icon name="hero-exclamation-circle" class="w-5 h-5" />
                  <p class="text-sm">
                    Kein Einschreibeschlüssel gesetzt. Du kannst einen in den
                    <.link
                      navigate={~p"/exams/#{@exam}/edit?return_to=show"}
                      class="text-amber-600 hover:text-amber-700 font-medium underline underline-offset-2"
                    >
                      Prüfungseinstellungen
                    </.link>
                    hinterlegen.
                  </p>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- Submissions Card --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6 border-b border-stone-100">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-[10px] flex items-center justify-center shrink-0 bg-blue-50 text-blue-500">
                  <.icon name="hero-users" class="w-5 h-5" />
                </div>
                <div>
                  <h2 class="text-lg font-semibold text-stone-800">Teilnehmer</h2>
                  <p class="text-sm text-stone-500 mt-0.5">
                    Eingeschriebene Lernende für diese Prüfung.
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <span class="inline-flex items-center gap-1.5 bg-emerald-50 text-emerald-700 text-sm font-semibold px-3 py-1.5 rounded-full">
                  <span class="w-2 h-2 rounded-full bg-emerald-400" />
                  {MapSet.size(@present_tokens)} online
                </span>
                <span class="inline-flex items-center gap-1.5 bg-blue-50 text-blue-700 text-sm font-semibold px-3 py-1.5 rounded-full">
                  <.icon name="hero-user-group-mini" class="w-4 h-4" />
                  {@submissions_count}
                </span>
              </div>
            </div>
          </div>
          <div class="p-6">
            <div id="submissions" phx-update="stream">
              <div class="hidden only:flex flex-col items-center justify-center py-12 text-stone-400">
                <.icon name="hero-user-group" class="w-10 h-10 mb-3 text-stone-300" />
                <p class="text-sm font-medium">Noch keine Teilnehmer eingeschrieben.</p>
              </div>
              <div
                :for={{id, submission} <- @streams.submissions}
                id={id}
                class="flex items-center gap-4 px-4 py-3 -mx-4 rounded-lg hover:bg-stone-50 transition-colors duration-150 group"
              >
                <div class="relative shrink-0">
                  <div class="w-9 h-9 rounded-full bg-gradient-to-br from-blue-400 to-indigo-500 flex items-center justify-center text-white text-sm font-bold shadow-sm">
                    {String.first(submission.firstname)}{String.first(submission.lastname)}
                  </div>
                  <div class={[
                    "absolute -bottom-0.5 -right-0.5 w-3.5 h-3.5 rounded-full border-2 border-white",
                    if(MapSet.member?(@present_tokens, submission.exam_token),
                      do: "bg-emerald-400",
                      else: "bg-amber-300"
                    )
                  ]} />
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-semibold text-stone-800 truncate">
                    {submission.firstname} {submission.lastname}
                  </p>
                  <p class="text-xs mt-0.5">
                    <%= if MapSet.member?(@present_tokens, submission.exam_token) do %>
                      <span class="text-emerald-500 font-medium">Online</span>
                      <span class="text-stone-300 mx-1">·</span>
                    <% else %>
                      <span class="text-amber-500 font-medium">Abwesend</span>
                      <span class="text-stone-300 mx-1">·</span>
                    <% end %>
                    <span class="text-stone-400">
                      Eingeschrieben am {Calendar.strftime(
                        submission.inserted_at,
                        "%d.%m.%Y um %H:%M"
                      )}
                    </span>
                  </p>
                </div>
                <div class="opacity-0 group-hover:opacity-100 transition-opacity duration-150">
                  <span class="text-xs text-stone-400 font-mono bg-stone-100 px-2 py-1 rounded">
                    {submission.exam_token}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Start Exam Confirmation Modal --%>
      <%= if @confirm_action == :start_exam do %>
        <dialog
          id="start-exam-modal"
          class="modal modal-open"
          phx-window-keydown="close_confirm"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_confirm"></div>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-emerald-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-play" class="w-5 h-5 text-emerald-600" />
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-stone-800">Prüfung starten</h3>
                  <p class="text-xs text-stone-400 mt-0.5">
                    Diese Aktion kann nicht rückgängig gemacht werden.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6">
              <p class="text-sm text-stone-600 leading-relaxed">
                Möchtest du die Prüfung <span class="font-semibold text-stone-800">{@exam.name}</span>
                jetzt starten?
                Alle eingeschriebenen Lernenden erhalten sofort Zugang zu den Aufgaben.
              </p>
              <div class="bg-amber-50 rounded-lg p-3 mt-4 border border-amber-100">
                <div class="flex items-start gap-2.5">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-4 h-4 text-amber-500 shrink-0 mt-0.5"
                  />
                  <p class="text-xs text-amber-700 leading-relaxed">
                    Nach dem Start können sich keine weiteren Lernenden mehr einschreiben.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6 pt-0 flex items-center justify-end gap-3">
              <button
                type="button"
                phx-click="close_confirm"
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Abbrechen
              </button>
              <button
                type="button"
                phx-click="confirm_action"
                class="inline-flex items-center gap-2 bg-emerald-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(16,185,129,0.25)] transition-all duration-150 hover:bg-emerald-600 active:scale-[0.98]"
              >
                <.icon name="hero-play" class="w-4 h-4" /> Jetzt starten
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <%!-- End Exam Confirmation Modal --%>
      <%= if @confirm_action == :end_exam do %>
        <dialog
          id="end-exam-modal"
          class="modal modal-open"
          phx-window-keydown="close_confirm"
          phx-key="escape"
        >
          <div class="modal-backdrop bg-stone-900/50" phx-click="close_confirm"></div>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-red-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-stop" class="w-5 h-5 text-red-600" />
                </div>
                <div>
                  <h3 class="text-lg font-semibold text-stone-800">Prüfung beenden</h3>
                  <p class="text-xs text-stone-400 mt-0.5">
                    Diese Aktion kann nicht rückgängig gemacht werden.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6">
              <p class="text-sm text-stone-600 leading-relaxed">
                Möchtest du die Prüfung <span class="font-semibold text-stone-800">{@exam.name}</span>
                jetzt beenden?
                Alle Lernenden werden sofort von der Prüfung getrennt.
              </p>
              <div class="bg-red-50 rounded-lg p-3 mt-4 border border-red-100">
                <div class="flex items-start gap-2.5">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-4 h-4 text-red-500 shrink-0 mt-0.5"
                  />
                  <p class="text-xs text-red-700 leading-relaxed">
                    Nach dem Beenden können Lernende keine Änderungen mehr vornehmen.
                  </p>
                </div>
              </div>
            </div>
            <div class="p-6 pt-0 flex items-center justify-end gap-3">
              <button
                type="button"
                phx-click="close_confirm"
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Abbrechen
              </button>
              <button
                type="button"
                phx-click="confirm_action"
                class="inline-flex items-center gap-2 bg-red-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(239,68,68,0.25)] transition-all duration-150 hover:bg-red-600 active:scale-[0.98]"
              >
                <.icon name="hero-stop" class="w-4 h-4" /> Jetzt beenden
              </button>
            </div>
          </div>
        </dialog>
      <% end %>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              this.el.select();
            });
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyButton">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const targetId = this.el.getAttribute("data-target");
              const input = document.getElementById(targetId);
              if (!input) return;

              navigator.clipboard.writeText(input.value).then(() => {
                const span = this.el.querySelector("span");
                const original = span.textContent;
                span.textContent = "Kopiert!";
                this.el.classList.remove("bg-amber-500", "hover:bg-amber-600");
                this.el.classList.add("bg-emerald-500", "hover:bg-emerald-600");
                setTimeout(() => {
                  span.textContent = original;
                  this.el.classList.remove("bg-emerald-500", "hover:bg-emerald-600");
                  this.el.classList.add("bg-amber-500", "hover:bg-amber-600");
                }, 2000);
              });
            });
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tasky.PubSub, "exam_waiting:#{exam.id}")
    end

    submissions = Exams.list_exam_submissions(exam)

    # Build a MapSet of currently present exam_tokens
    present_tokens =
      TaskyWeb.Presence.list("exam_waiting:#{exam.id}")
      |> Map.keys()
      |> MapSet.new()

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Cockpit")
     |> assign(:exam, exam)
     |> assign(:submissions_count, length(submissions))
     |> assign(:present_tokens, present_tokens)
     |> assign(:confirm_action, nil)
     |> stream(:submissions, submissions)}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    present_tokens =
      socket.assigns.present_tokens
      |> then(fn tokens ->
        Enum.reduce(diff.joins, tokens, fn {key, _}, acc -> MapSet.put(acc, key) end)
      end)
      |> then(fn tokens ->
        Enum.reduce(diff.leaves, tokens, fn {key, _}, acc -> MapSet.delete(acc, key) end)
      end)

    # Re-stream all submissions so the presence indicator updates
    submissions = Exams.list_exam_submissions(socket.assigns.exam)

    {:noreply,
     socket
     |> assign(:present_tokens, present_tokens)
     |> stream(:submissions, submissions, reset: true)}
  end

  @impl true
  def handle_event("show_confirm", %{"action" => action}, socket) do
    {:noreply, assign(socket, :confirm_action, String.to_existing_atom(action))}
  end

  def handle_event("close_confirm", _params, socket) do
    {:noreply, assign(socket, :confirm_action, nil)}
  end

  def handle_event("confirm_action", _params, socket) do
    case socket.assigns.confirm_action do
      :start_exam ->
        case Exams.update_exam_status(socket.assigns.exam, "running") do
          {:ok, exam} ->
            {:noreply,
             socket
             |> assign(:exam, exam)
             |> assign(:confirm_action, nil)
             |> put_flash(:info, "Prüfung gestartet")}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:confirm_action, nil)
             |> put_flash(:error, "Prüfung konnte nicht gestartet werden.")}
        end

      :end_exam ->
        case Exams.update_exam_status(socket.assigns.exam, "finished") do
          {:ok, exam} ->
            {:noreply,
             socket
             |> assign(:exam, exam)
             |> assign(:confirm_action, nil)
             |> put_flash(:info, "Prüfung beendet")}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:confirm_action, nil)
             |> put_flash(:error, "Prüfung konnte nicht beendet werden.")}
        end

      _ ->
        {:noreply, assign(socket, :confirm_action, nil)}
    end
  end
end
