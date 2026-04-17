defmodule TaskyWeb.Guest.ExamLive do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias TaskyWeb.Presence

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

              <%!-- Participants List --%>
              <div class="bg-white rounded-2xl border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-6">
                <div class="flex items-center justify-between mb-4">
                  <h3 class="text-sm font-semibold text-stone-700">
                    Teilnehmer im Warteraum
                  </h3>
                  <span class="text-xs font-semibold bg-sky-100 text-sky-700 px-2.5 py-1 rounded-full">
                    {map_size(@presences)}
                  </span>
                </div>

                <div id="waiting-participants" class="space-y-2">
                  <%= for {token, %{metas: [meta | _]}} <- @presences do %>
                    <div
                      id={"participant-#{token}"}
                      class={[
                        "flex items-center gap-3 px-3 py-2.5 rounded-xl transition-all duration-200",
                        if(token == @submission.exam_token,
                          do: "bg-sky-50 border border-sky-100",
                          else: "bg-stone-50"
                        )
                      ]}
                    >
                      <div class={[
                        "w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold",
                        if(token == @submission.exam_token,
                          do: "bg-sky-200 text-sky-700",
                          else: "bg-stone-200 text-stone-600"
                        )
                      ]}>
                        {String.first(meta.firstname)}{String.first(meta.lastname)}
                      </div>
                      <span class="text-sm text-stone-700 font-medium">
                        {meta.firstname} {meta.lastname}
                      </span>
                      <%= if token == @submission.exam_token do %>
                        <span class="ml-auto text-xs text-sky-500 font-semibold">(Du)</span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% @exam.status == "running" -> %>
          <%!-- Running Exam --%>
          <div class="max-w-4xl mx-auto px-4 py-8">
            <div class="mb-8">
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
      # Subscribe to exam status changes
      Exams.subscribe_exam(exam.id)

      # Subscribe to presence updates for the waiting room
      Phoenix.PubSub.subscribe(Tasky.PubSub, "exam_waiting:#{exam.id}")

      # Track this guest in the waiting room if exam is open
      if exam.status == "open" do
        {:ok, _} =
          Presence.track(
            self(),
            "exam_waiting:#{exam.id}",
            submission.exam_token,
            %{firstname: submission.firstname, lastname: submission.lastname}
          )
      end
    end

    presences = Presence.list("exam_waiting:#{exam.id}")

    {:ok,
     socket
     |> assign(:page_title, exam.name)
     |> assign(:exam, exam)
     |> assign(:submission, submission)
     |> assign(:presences, presences)}
  end

  # Handle presence diffs (joins/leaves in the waiting room)
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    {:noreply,
     socket
     |> handle_joins(diff.joins)
     |> handle_leaves(diff.leaves)}
  end

  # Handle exam status changes from the teacher
  @impl true
  def handle_info({:exam_status_changed, updated_exam}, socket) do
    {:noreply, assign(socket, :exam, updated_exam)}
  end

  defp handle_joins(socket, joins) do
    presences =
      Enum.reduce(joins, socket.assigns.presences, fn {key, %{metas: metas}}, acc ->
        Map.put(acc, key, %{metas: metas})
      end)

    assign(socket, :presences, presences)
  end

  defp handle_leaves(socket, leaves) do
    presences =
      Enum.reduce(leaves, socket.assigns.presences, fn {key, _}, acc ->
        Map.delete(acc, key)
      end)

    assign(socket, :presences, presences)
  end
end
