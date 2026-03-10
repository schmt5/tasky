defmodule TaskyWeb.Student.CourseLive do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <div id="course-tasks-container">
      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <%!-- Page Header --%>
        <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
          <div class="max-w-6xl mx-auto">
            <div class="flex items-center justify-between mb-3">
              <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-sky-500">
                Studenten Portal
              </div>

              <.link
                navigate={~p"/student/courses"}
                class="inline-flex items-center gap-1.5 text-[13px] font-semibold text-stone-600 hover:text-stone-900 transition-colors duration-150"
              >
                <.icon name="hero-arrow-left" class="w-4 h-4" /> Zurück
              </.link>
            </div>

            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
              {@course.name}
            </h1>

            <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
              {@course.description || "Sieh dir alle Aufgaben für diesen Kurs an"}
            </p>
          </div>
        </div>

        <%= if @submissions != [] do %>
          <%!-- Progress Card --%>
          <div class="max-w-6xl mx-auto px-8 mb-8">
            <div class="bg-gradient-to-br from-sky-50 to-white rounded-[14px] border border-sky-100 p-6 shadow-[0_1px_3px_rgba(14,165,233,0.08)]">
              <div class="flex items-center justify-between mb-3">
                <h3 class="text-[13px] font-semibold text-stone-700 tracking-[0.01em]">
                  Kurs-Fortschritt
                </h3>

                <span class="text-[28px] font-bold bg-gradient-to-br from-sky-500 to-sky-600 bg-clip-text text-transparent">
                  {if @stats.total > 0,
                    do: round(@stats.completed / @stats.total * 100),
                    else: 0}%
                </span>
              </div>

              <div class="w-full bg-stone-100 rounded-full h-2.5 overflow-hidden shadow-inner">
                <div
                  class="bg-gradient-to-r from-sky-400 via-sky-500 to-sky-600 h-2.5 rounded-full transition-all duration-500 ease-out shadow-[0_0_8px_rgba(14,165,233,0.4)]"
                  style={"width: #{if @stats.total > 0, do: (@stats.completed / @stats.total * 100), else: 0}%"}
                >
                </div>
              </div>

              <div class="mt-3 flex items-center justify-between text-[13px]">
                <span class="text-stone-500">
                  {@stats.completed} von {@stats.total} Aufgaben erledigt
                </span>
                <%= if @stats.graded > 0 do %>
                  <span class="text-sky-600 font-medium flex items-center gap-1">
                    <.icon name="hero-check-badge" class="w-4 h-4" /> {@stats.graded} bewertet
                  </span>
                <% end %>
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
              <div class="absolute left-[19px] top-[32px] bottom-[32px] w-[2px] bg-gradient-to-b from-stone-200 via-stone-200 to-stone-100 rounded-[1px] z-0">
              </div>
              <%!-- Timeline Items --%>
              <div
                :for={{submission, index} <- Enum.with_index(@submissions, 1)}
                class="flex items-start gap-4 relative z-[1]"
              >
                <%!-- Timeline Node --%>
                <div class={[
                  "flex-shrink-0 w-[40px] h-[40px] rounded-full flex items-center justify-center text-[12px] font-bold border-2 border-white shadow-sm mt-[14px] relative transition-all duration-200",
                  submission.status in ["completed", "review_approved"] &&
                    "bg-green-100 text-green-700 shadow-[0_0_0_2px_#dcfce7]",
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
                    <.icon name="hero-check" class="w-4 h-4" />
                  <% else %>
                    <%= cond do %>
                      <% index == 1 -> %>
                        <span class="text-[16px]">📍</span>
                      <% index == length(@submissions) -> %>
                        <span class="text-[16px]">🏁</span>
                      <% true -> %>
                        {String.pad_leading("#{index}", 2, "0")}
                    <% end %>
                  <% end %>
                </div>
                <%!-- Timeline Card --%>
                <.link
                  navigate={
                    if submission.status == "completed",
                      do: ~p"/student/tasks/#{submission.task.id}?preview=true",
                      else: ~p"/student/tasks/#{submission.task.id}"
                  }
                  class={[
                    "flex-1 rounded-xl shadow-sm transition-all duration-300 overflow-hidden border mb-3 flex items-center gap-4 p-6 no-underline",
                    submission.status in ["completed", "review_approved"] &&
                      "bg-white/40 backdrop-blur-sm border-stone-100 hover:border-stone-200",
                    submission.task.id == @active_task_id &&
                      "bg-white border-sky-200 shadow-[0_0_0_3px_#f0f9ff] hover:border-sky-300 hover:shadow-[0_4px_16px_rgba(14,165,233,0.12),0_0_0_3px_#f0f9ff]",
                    submission.task.id != @active_task_id &&
                      submission.status in ["not_started", "open", "draft", "in_progress"] &&
                      "bg-white border-stone-200 hover:shadow-md hover:border-stone-300 hover:-translate-y-[1px]",
                    submission.status == "review_denied" &&
                      "bg-white border-rose-200 hover:border-rose-300"
                  ]}
                >
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
                        <div class="w-8 h-8 rounded-full bg-green-100 text-green-700 flex items-center justify-center">
                          <.icon name="hero-check" class="w-3.5 h-3.5" />
                        </div>
                      <% submission.status == "review_denied" -> %>
                        <div class="w-8 h-8 rounded-full bg-rose-100 text-rose-700 flex items-center justify-center">
                          <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                        </div>
                      <% submission.task.id == @active_task_id -> %>
                        <button class="px-4 py-2 text-[13px] font-semibold bg-sky-500 text-white rounded-lg hover:bg-sky-600 transition-all duration-150 shadow-[0_2px_8px_rgba(14,165,233,0.25)]">
                          {if submission.status in ["not_started", "open", "draft"],
                            do: "Starten",
                            else: "Öffnen"}
                        </button>
                      <% true -> %>
                        <button class="px-3.5 py-2 text-[13px] font-semibold bg-transparent text-stone-500 rounded-lg border-[1.5px] border-stone-200 hover:bg-sky-50 hover:text-sky-600 hover:border-sky-200 transition-all duration-150">
                          Öffnen
                        </button>
                    <% end %>
                  </div>
                </.link>
              </div>
            </div>
          <% end %>
        </div>
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
     |> assign(:active_task_id, active_task_id)}
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
