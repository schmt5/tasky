defmodule TaskyWeb.Student.CourseLive do
  use TaskyWeb, :live_view

  alias Tasky.Tasks
  alias Tasky.Courses

  @impl true
  def render(assigns) do
    ~H"""
    <div id="course-tasks-container">
      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <%!-- Page Header --%>
        <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-4 mb-8">
          <div class="max-w-6xl mx-auto">
            <div class="flex items-center justify-between mb-2">
              <div class="text-[10px] tracking-[0.12em] uppercase font-semibold text-sky-500">
                Studenten Portal
              </div>

              <.link
                navigate={~p"/student/courses"}
                class="inline-flex items-center gap-1.5 text-[13px] font-semibold text-stone-600 hover:text-stone-900 transition-colors duration-150"
              >
                <.icon name="hero-arrow-left" class="w-4 h-4" /> Zurück
              </.link>
            </div>

            <h1 class="font-serif text-[36px] text-stone-900 leading-[1.1] mb-2 font-normal">
              {@course.name}
            </h1>

            <p class="text-[14px] text-stone-500 max-w-[560px] leading-[1.6]">
              {@course.description || "Sieh dir alle Aufgaben für diesen Kurs an"}
            </p>
          </div>
        </div>

        <%= if @submissions != [] do %>
          <%!-- Progress Card --%>
          <div class="max-w-6xl mx-auto px-8 mb-8">
            <div class="bg-gradient-to-br from-emerald-50 to-white rounded-[18px] border border-emerald-200 p-8 shadow-sm overflow-hidden relative">
              <%!-- Decorative background pattern --%>
              <div class="absolute top-0 right-0 w-32 h-32 bg-emerald-100/30 rounded-full blur-3xl -z-0">
              </div>
              <div class="absolute bottom-0 left-0 w-24 h-24 bg-emerald-100/20 rounded-full blur-2xl -z-0">
              </div>

              <div class="relative">
                <div class="flex items-center gap-4 mb-6">
                  <%!-- Icon --%>
                  <div class="flex-shrink-0">
                    <div class="w-12 h-12 bg-emerald-100 rounded-full flex items-center justify-center">
                      <.icon name="hero-chart-bar" class="w-6 h-6 text-emerald-600" />
                    </div>
                  </div>

                  <%!-- Header and percentage --%>
                  <div class="flex-1 min-w-0">
                    <h3 class="text-[18px] font-semibold text-stone-700">
                      Dein Kurs-Fortschritt
                    </h3>
                  </div>

                  <%!-- Large percentage display --%>
                  <div class="flex-shrink-0 text-right">
                    <div class="text-[36px] font-bold text-emerald-600 leading-none">
                      {if @stats.total > 0,
                        do: round(@stats.completed / @stats.total * 100),
                        else: 0}%
                    </div>
                    <div class="text-[11px] text-stone-400 font-medium mt-1">
                      Abgeschlossen
                    </div>
                  </div>
                </div>

                <%!-- Progress bar --%>
                <div class="mb-4">
                  <div class="w-full bg-stone-100 rounded-full h-3 overflow-hidden shadow-inner">
                    <div
                      class="bg-gradient-to-r from-emerald-400 via-emerald-500 to-emerald-600 h-3 rounded-full transition-all duration-700 ease-out shadow-[0_0_12px_rgba(16,185,129,0.5)] relative"
                      style={"width: #{if @stats.total > 0, do: (@stats.completed / @stats.total * 100), else: 0}%"}
                    >
                      <%!-- Shimmer effect --%>
                      <div class="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent animate-[shimmer_2s_infinite]">
                      </div>
                    </div>
                  </div>
                </div>

                <%!-- Stats row --%>
                <div class="flex items-center gap-6 text-[13px]">
                  <div class="flex items-center gap-2">
                    <div class="w-2 h-2 rounded-full bg-emerald-500"></div>
                    <span class="text-stone-600 font-medium">
                      {@stats.completed} / {@stats.total} Aufgaben
                    </span>
                  </div>

                  <%= if @stats.graded > 0 do %>
                    <div class="flex items-center gap-2 px-3 py-1.5 bg-emerald-50 rounded-lg border border-emerald-100">
                      <.icon name="hero-check-badge" class="w-4 h-4 text-emerald-600" />
                      <span class="text-emerald-700 font-semibold">
                        {@stats.graded} bewertet
                      </span>
                    </div>
                  <% end %>

                  <%= if @stats.completed == @stats.total && @stats.total > 0 do %>
                    <div class="ml-auto flex items-center gap-2 text-emerald-600 font-semibold animate-[fadeIn_0.5s_ease]">
                      <span class="text-[18px]">🎉</span>
                      <span>Alle erledigt!</span>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% end %>
        <%!-- Task List --%>
        <div class="max-w-6xl mx-auto px-8 pb-8">
          <%= if @submissions == [] do %>
            <div class="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
              <.icon name="hero-document-text" class="mx-auto h-12 w-12 text-gray-400" />
              <h3 class="mt-2 text-sm font-semibold text-gray-900">Noch keine Aufgaben</h3>

              <p class="mt-1 text-sm text-gray-500">
                In diesem Kurs gibt es noch keine Aufgaben. Schau später nochmal vorbei!
              </p>
            </div>
          <% else %>
            <%!-- Timeline Label --%>
            <div class="text-[10px] tracking-[0.12em] uppercase font-semibold text-stone-400 mb-1">
              Aufgaben
            </div>
            <%!-- Timeline Container --%>
            <div class="relative flex flex-col">
              <%!-- Vertical Spine Line --%>
              <div class="absolute left-[23px] top-[32px] bottom-[32px] w-[2px] bg-gradient-to-b from-stone-200 via-stone-200 to-stone-100 rounded-[1px] z-0">
              </div>
              <%!-- Timeline Items --%>
              <div
                :for={{submission, index} <- Enum.with_index(@submissions, 1)}
                class="flex items-start gap-4 relative z-[1]"
              >
                <%!-- Timeline Node --%>
                <div class={[
                  "flex-shrink-0 w-[48px] h-[48px] rounded-full flex items-center justify-center text-[14px] font-bold border-2 border-white shadow-sm mt-[14px] relative transition-all duration-200",
                  submission.status in ["completed", "review_approved"] &&
                    "bg-white shadow-[0_0_0_2px_#dcfce7]",
                  submission.task.id == @active_task_id &&
                    (index == 1 || index == length(@submissions)) &&
                    "bg-white text-stone-700 shadow-[0_0_0_3px_#e0f2fe,0_2px_8px_rgba(14,165,233,0.25)]",
                  submission.task.id == @active_task_id &&
                    index != 1 && index != length(@submissions) &&
                    "bg-sky-500 text-white shadow-[0_0_0_3px_#e0f2fe,0_2px_8px_rgba(14,165,233,0.25)]",
                  submission.task.id != @active_task_id &&
                    submission.status in ["not_started", "open", "draft", "in_progress"] &&
                    (index == 1 || index == length(@submissions)) &&
                    "bg-white text-stone-700 shadow-[0_0_0_2px_#e7e5e4]",
                  submission.task.id != @active_task_id &&
                    submission.status in ["not_started", "open", "draft", "in_progress"] &&
                    index != 1 && index != length(@submissions) &&
                    "bg-stone-200 text-stone-500 shadow-[0_0_0_2px_#e7e5e4]",
                  submission.status == "review_denied" &&
                    "bg-rose-100 text-rose-700 shadow-[0_0_0_2px_#ffe4e6]"
                ]}>
                  <%= if submission.status in ["completed", "review_approved"] do %>
                    <span class="text-[24px]">✅</span>
                  <% else %>
                    <%= cond do %>
                      <% index == 1 -> %>
                        <span class="text-[20px]">📍</span>
                      <% index == length(@submissions) -> %>
                        <span class="text-[20px]">🏁</span>
                      <% true -> %>
                        {String.pad_leading("#{index}", 2, "0")}
                    <% end %>
                  <% end %>
                </div>
                <%!-- Timeline Card --%>
                <div class={[
                  "flex-1 rounded-xl shadow-sm transition-all duration-300 overflow-hidden border mb-3 flex items-center gap-4 p-6",
                  submission.status in ["completed", "review_approved"] &&
                    "bg-white/40 backdrop-blur-sm border-stone-100",
                  submission.task.id == @active_task_id &&
                    "bg-white border-sky-200 shadow-[0_0_0_3px_#f0f9ff]",
                  submission.task.id != @active_task_id &&
                    submission.status in ["not_started", "open", "draft", "in_progress"] &&
                    "bg-white border-stone-200",
                  submission.status == "review_denied" &&
                    "bg-white border-rose-200"
                ]}>
                  <%!-- Card Body --%>
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 mb-1">
                      <span class={[
                        "text-[14px] font-semibold leading-[1.4] whitespace-nowrap overflow-hidden text-ellipsis",
                        submission.status in ["completed", "review_approved"] &&
                          "text-stone-400 line-through decoration-stone-300",
                        submission.status not in ["completed", "review_approved"] && "text-stone-800"
                      ]}>
                        {submission.task.name}
                      </span>
                      <%= if submission.graded_at do %>
                        <button
                          type="button"
                          phx-click="show_feedback"
                          phx-value-submission-id={submission.id}
                          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold bg-amber-100 text-amber-700 whitespace-nowrap flex-shrink-0 hover:bg-amber-200 transition-colors"
                        >
                          💬 Feedback
                        </button>
                      <% end %>
                    </div>

                    <div>
                      <span class={[
                        "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold whitespace-nowrap",
                        submission.status == "draft" && "bg-gray-100 text-gray-700",
                        submission.status == "not_started" && "bg-stone-100 text-stone-500",
                        submission.status == "open" && "bg-stone-100 text-stone-500",
                        submission.status == "in_progress" && "bg-sky-100 text-sky-700",
                        submission.status == "completed" && "bg-green-100 text-green-800",
                        submission.status == "review_approved" && "bg-sky-100 text-sky-700",
                        submission.status == "review_denied" && "bg-rose-100 text-rose-700"
                      ]}>
                        {format_status(submission.status)}
                      </span>
                    </div>
                  </div>
                  <%!-- Action Icon/Indicator --%>
                  <div class="flex-shrink-0">
                    <%= cond do %>
                      <% submission.status in ["completed", "review_approved"] -> %>
                        <.link
                          navigate={~p"/student/tasks/#{submission.task.id}?preview=true"}
                          class="px-3.5 py-2 text-[13px] font-semibold bg-transparent text-stone-500 rounded-lg hover:bg-stone-50 hover:text-stone-700 transition-all duration-150"
                        >
                          Ansehen
                        </.link>
                      <% submission.status == "review_denied" -> %>
                        <div class="w-8 h-8 rounded-full bg-rose-100 text-rose-700 flex items-center justify-center">
                          <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                        </div>
                      <% submission.task.id == @active_task_id -> %>
                        <.link
                          navigate={~p"/student/tasks/#{submission.task.id}"}
                          class="px-4 py-2 text-[13px] font-semibold bg-sky-500 text-white rounded-lg hover:bg-sky-600 transition-all duration-150 shadow-[0_2px_8px_rgba(14,165,233,0.25)]"
                        >
                          {if submission.status in ["not_started", "open", "draft"],
                            do: "Starten",
                            else: "Öffnen"}
                        </.link>
                      <% true -> %>
                        <.link
                          navigate={~p"/student/tasks/#{submission.task.id}"}
                          class="px-3.5 py-2 text-[13px] font-semibold bg-transparent text-stone-500 rounded-lg border-[1.5px] border-stone-200 hover:bg-sky-50 hover:text-sky-600 hover:border-sky-200 transition-all duration-150"
                        >
                          Öffnen
                        </.link>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Feedback Modal --%>
        <%= if @show_feedback_modal do %>
          <dialog
            id="feedback-modal"
            class="modal modal-open"
            phx-window-keydown="close_feedback_modal"
            phx-key="escape"
          >
            <%!-- Modal backdrop --%>
            <div class="modal-backdrop bg-stone-900/50" phx-click="close_feedback_modal"></div>
            <%!-- Modal box --%>
            <div class="modal-box max-w-lg p-0 bg-white rounded-[16px] shadow-2xl border border-stone-200">
              <%!-- Header --%>
              <div class="flex items-center justify-between px-6 py-4 border-b border-stone-100">
                <div class="flex items-center gap-2.5">
                  <div class="w-8 h-8 rounded-full bg-amber-100 flex items-center justify-center text-base">
                    💬
                  </div>
                  <div>
                    <h3 class="text-[15px] font-semibold text-stone-900">Feedback vom Lehrer</h3>
                    <%= if @feedback_task_name do %>
                      <p class="text-[12px] text-stone-400">{@feedback_task_name}</p>
                    <% end %>
                  </div>
                </div>
                <button
                  type="button"
                  phx-click="close_feedback_modal"
                  class="text-stone-400 hover:text-stone-600 transition-colors"
                >
                  <.icon name="hero-x-mark" class="w-5 h-5" />
                </button>
              </div>
              <%!-- Body --%>
              <div class="px-6 py-5">
                <div class="bg-amber-50 border border-amber-100 rounded-[10px] px-4 py-4">
                  <p class="text-[14px] text-stone-700 whitespace-pre-line leading-relaxed">
                    {String.trim(@feedback_text || "")}
                  </p>
                </div>
              </div>
              <%!-- Footer --%>
              <div class="px-6 py-4 border-t border-stone-100 flex justify-end">
                <button
                  type="button"
                  phx-click="close_feedback_modal"
                  class="px-4 py-2 bg-stone-900 text-white text-[13px] font-medium rounded-[8px] hover:bg-stone-800 transition-colors"
                >
                  Schließen
                </button>
              </div>
            </div>
          </dialog>
        <% end %>
      </Layouts.app>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => course_id}, _session, socket) do
    # Subscribe to real-time updates for this student's submissions
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Tasky.PubSub,
        "student:#{socket.assigns.current_scope.user.id}:submissions"
      )
    end

    # Get the course to verify enrollment and get course details
    student_id = socket.assigns.current_scope.user.id
    course = Courses.get_course_for_student!(student_id, course_id)

    # Get submissions for this specific course
    submissions = Tasks.list_course_submissions(socket.assigns.current_scope, course_id)

    stats = calculate_stats(submissions)
    active_task_id = find_active_task_id(submissions)

    {:ok,
     socket
     |> assign(:page_title, course.name)
     |> assign(:course, course)
     |> assign(:submissions, submissions)
     |> assign(:stats, stats)
     |> assign(:active_task_id, active_task_id)
     |> assign(:show_feedback_modal, false)
     |> assign(:feedback_text, nil)
     |> assign(:feedback_task_name, nil)}
  end

  @impl true
  def handle_info({:submission_updated, _updated_submission}, socket) do
    # Reload all submissions to get the latest state
    submissions =
      Tasks.list_course_submissions(socket.assigns.current_scope, socket.assigns.course.id)

    stats = calculate_stats(submissions)
    active_task_id = find_active_task_id(submissions)

    {:noreply,
     socket
     |> assign(:submissions, submissions)
     |> assign(:stats, stats)
     |> assign(:active_task_id, active_task_id)
     |> put_flash(:info, "Aufgabenstatus aktualisiert!")}
  end

  @impl true
  def handle_event("show_feedback", %{"submission-id" => submission_id}, socket) do
    submission_id = String.to_integer(submission_id)

    submission = Enum.find(socket.assigns.submissions, &(&1.id == submission_id))

    {:noreply,
     socket
     |> assign(:show_feedback_modal, true)
     |> assign(:feedback_text, submission.feedback || "")
     |> assign(:feedback_task_name, submission.task.name)}
  end

  @impl true
  def handle_event("close_feedback_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_feedback_modal, false)
     |> assign(:feedback_text, nil)
     |> assign(:feedback_task_name, nil)}
  end

  defp format_status(status) do
    case status do
      "draft" -> "TODO"
      "not_started" -> "Nicht begonnen"
      "open" -> "Offen"
      "in_progress" -> "In Bearbeitung"
      "completed" -> "Erledigt"
      "review_approved" -> "Genehmigt"
      "review_denied" -> "Abgelehnt"
      _ -> status |> String.replace("_", " ") |> String.capitalize()
    end
  end

  defp calculate_stats(submissions) do
    %{
      total: length(submissions),
      completed: Enum.count(submissions, &(&1.status == "completed")),
      graded: Enum.count(submissions, &(&1.status == "review_approved"))
    }
  end

  defp find_active_task_id(submissions) do
    # Find the in_progress task
    in_progress = Enum.find(submissions, &(&1.status == "in_progress"))

    if in_progress do
      in_progress.task.id
    else
      # Find the first non-completed task
      next_task =
        Enum.find(submissions, &(&1.status not in ["completed", "review_approved"]))

      if next_task do
        next_task.task.id
      else
        # If all completed, return the first task id (fallback)
        case List.first(submissions) do
          nil -> nil
          submission -> submission.task.id
        end
      end
    end
  end
end
