defmodule TaskyWeb.Student.ExamsLive do
  @moduledoc """
  The exams a logged-in participant has been assigned to.

  The link into a running exam points at `/guest/exam/:exam_token` on purpose:
  that runtime is shared with anonymous participants, and it is the only entry
  point that works inside the Safe Exam Browser, which starts without a session
  cookie. Rows come from `Exams.list_assigned_exams/1`, which filters on the
  current user, so the token rendered here is the participant's own by
  construction.
  """

  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/student/exams"}>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-4 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="text-[10px] tracking-[0.12em] uppercase font-semibold text-sky-500 mb-2">
            Lernenden Portal
          </div>

          <h1 class="font-serif text-[36px] text-stone-900 leading-[1.1] mb-2 font-normal">
            Meine <em class="italic text-sky-500">Prüfungen</em>
          </h1>

          <p class="text-[14px] text-stone-500 max-w-[560px] leading-[1.6]">
            Alle Prüfungen, für die du eingeteilt bist.
          </p>
        </div>
      </div>

      <div class="max-w-6xl mx-auto bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
        <div class="flex items-center justify-between p-6 border-b border-stone-100">
          <div>
            <h2 class="text-lg font-semibold text-stone-800">Zugewiesene Prüfungen</h2>
            <p class="text-sm text-stone-500 mt-1">{@exam_count} Prüfungen insgesamt</p>
          </div>
        </div>

        <ul :if={@has_exams} id="exams" phx-update="stream" class="list-none p-0 m-0">
          <li
            :for={{id, submission} <- @streams.exams}
            id={id}
            class="flex items-start gap-5 px-6 py-5 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 hover:bg-stone-50"
          >
            <div class={[
              "w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5",
              state_icon_class(submission)
            ]}>
              <.icon name="hero-academic-cap" class="w-5 h-5" />
            </div>

            <div class="flex-1 min-w-0 flex flex-col gap-1.5">
              <div class="flex items-center gap-2.5 flex-wrap">
                <h3 class="text-[15px] font-semibold text-stone-800 leading-[1.4]">
                  {submission.exam.name}
                </h3>
                <span class={[
                  "inline-flex items-center text-[11px] font-semibold px-2.5 py-0.5 rounded-full whitespace-nowrap tracking-[0.01em]",
                  state_badge_class(submission)
                ]}>
                  {state_label(submission)}
                </span>
              </div>

              <p class="text-sm text-stone-500 leading-[1.6] max-w-[600px]">
                {state_hint(submission)}
              </p>

              <div class="flex items-center gap-2 mt-1">
                <span class="text-[13px] text-stone-400 flex items-center gap-1">
                  <.icon name="hero-user" class="w-3.5 h-3.5" /> {submission.exam.teacher.email}
                </span>
                <%= if returned?(submission) and submission.exam.return_show_points_and_mark and submission.mark do %>
                  <span class="text-xs text-stone-300">·</span>
                  <span class="text-[13px] text-stone-400 flex items-center gap-1">
                    <.icon name="hero-academic-cap" class="w-3.5 h-3.5" />
                    Note {Tasky.Grading.format_mark(submission.mark)}
                  </span>
                <% end %>
              </div>
            </div>

            <div class="flex items-center gap-2 shrink-0 pt-0.5">
              <%= cond do %>
                <% joinable?(submission) -> %>
                  <.link
                    navigate={~p"/guest/exam/#{submission.exam_token}"}
                    id={"start-exam-#{submission.id}"}
                    class="inline-flex items-center gap-2 bg-sky-500 text-white text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                  >
                    {if submission.exam.status == "running",
                      do: "Prüfung fortsetzen",
                      else: "Zur Prüfung"}
                    <.icon name="hero-arrow-right" class="w-4 h-4" />
                  </.link>
                <% returned?(submission) -> %>
                  <.link
                    navigate={~p"/student/exams/#{submission.exam.id}"}
                    id={"view-exam-#{submission.id}"}
                    class="inline-flex items-center gap-2 bg-sky-500 text-white text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                  >
                    Prüfung ansehen <.icon name="hero-arrow-right" class="w-4 h-4" />
                  </.link>
                <% true -> %>
                  <span></span>
              <% end %>
            </div>
          </li>
        </ul>

        <div :if={!@has_exams} class="flex flex-col items-center text-center px-8 py-16 bg-white">
          <div class="w-14 h-14 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-5">
            <.icon name="hero-academic-cap" class="w-6 h-6" />
          </div>

          <h3 class="text-base font-semibold text-stone-700 mb-2">Noch keine Prüfungen</h3>

          <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6]">
            Du bist noch für keine Prüfung eingeteilt. Sobald deine Lehrperson dich zuweist,
            erscheint die Prüfung hier.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    submissions = Exams.list_assigned_exams(socket.assigns.current_scope)

    # One subscription per listed exam: the same {:exam_status_changed, exam}
    # event covers the start, the end and the return, so a student sitting on
    # this page never has to reload.
    if connected?(socket) do
      Enum.each(submissions, &Exams.subscribe_exam(&1.exam_id))
    end

    {:ok,
     socket
     |> assign(:page_title, "Meine Prüfungen")
     |> assign_exams(submissions)}
  end

  @impl true
  def handle_info({:exam_status_changed, _exam}, socket) do
    {:noreply, assign_exams(socket, Exams.list_assigned_exams(socket.assigns.current_scope))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_exams(socket, submissions) do
    socket
    |> assign(:exam_count, length(submissions))
    |> assign(:has_exams, submissions != [])
    |> stream(:exams, submissions, reset: true)
  end

  defp joinable?(%{submitted: false, exam: %{status: status}}) when status in ["open", "running"],
    do: true

  defp joinable?(_submission), do: false

  defp returned?(%{exam: exam}), do: Exams.returned?(exam)

  # One atom per row state, so label, colour and hint can never disagree — they
  # used to each `case` on the German label, and two different states ("Zugewiesen"
  # and "Zurückgegeben") happened to render in the same sky.
  #
  # The colours line up with the teacher side on purpose: amber = waiting (the
  # guest waiting room), emerald = running (`exam_status_chip`), purple =
  # abgegeben (the cockpit chip), sky = zurückgegeben (the grading page).
  defp state(%{submitted: true} = submission) do
    if returned?(submission), do: :returned, else: :submitted
  end

  defp state(%{exam: %{status: "open"}}), do: :assigned
  defp state(%{exam: %{status: "running"}}), do: :running

  defp state(submission) do
    if returned?(submission), do: :returned, else: :finished
  end

  defp state_label(submission) do
    case state(submission) do
      :assigned -> "Zugewiesen"
      :running -> "Läuft"
      :submitted -> "Abgegeben"
      :returned -> "Zurückgegeben"
      :finished -> "Beendet"
    end
  end

  defp state_badge_class(submission) do
    case state(submission) do
      :assigned -> "bg-amber-50 text-amber-700"
      :running -> "bg-emerald-100 text-emerald-700"
      :submitted -> "bg-purple-100 text-purple-700"
      :returned -> "bg-sky-100 text-sky-700"
      :finished -> "bg-stone-100 text-stone-600"
    end
  end

  defp state_icon_class(submission) do
    case state(submission) do
      :assigned -> "bg-amber-50 text-amber-600"
      :running -> "bg-emerald-50 text-emerald-600"
      :submitted -> "bg-purple-50 text-purple-500"
      :returned -> "bg-sky-100 text-sky-600"
      :finished -> "bg-stone-100 text-stone-400"
    end
  end

  defp state_hint(submission) do
    case state(submission) do
      :assigned -> "Die Prüfung ist noch nicht gestartet. Du kommst in den Warteraum."
      :running -> "Die Prüfung läuft. Du kannst weiterarbeiten."
      :submitted -> "Du hast abgegeben. Die Korrektur ist noch nicht freigegeben."
      :returned -> "Deine korrigierte Prüfung ist freigegeben."
      :finished -> "Die Prüfung ist beendet."
    end
  end
end
