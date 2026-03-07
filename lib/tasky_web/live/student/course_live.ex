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
            <%!-- Task Cards Grid --%>
            <div class="space-y-4">
              <div
                :for={submission <- @submissions}
                class={[
                  "rounded-xl shadow-sm transition-all duration-300 overflow-hidden border",
                  submission.status == "completed" &&
                    "bg-white/40 backdrop-blur-sm border-gray-300/50",
                  submission.status != "completed" &&
                    "bg-white border-gray-200 hover:shadow-md hover:border-gray-300"
                ]}
              >
                <%!-- Card Body with Modern Layout --%>
                <div class="p-6">
                  <div class="flex items-center gap-4">
                    <%!-- Content Section --%>
                    <div class="flex-1 min-w-0">
                      <%!-- Status Chip --%>
                      <div class="mb-2">
                        <span class={[
                          "inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold tracking-wide uppercase transition-all duration-200",
                          submission.status == "draft" &&
                            "bg-gray-100 text-gray-700 ring-1 ring-inset ring-gray-200",
                          submission.status == "not_started" &&
                            "bg-gray-100 text-gray-700 ring-1 ring-inset ring-gray-200",
                          submission.status == "open" &&
                            "bg-slate-100 text-slate-700 ring-1 ring-inset ring-slate-200",
                          submission.status == "in_progress" &&
                            "bg-blue-50 text-blue-700 ring-1 ring-inset ring-blue-600/20",
                          submission.status == "completed" &&
                            "bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-600/20",
                          submission.status == "review_approved" &&
                            "bg-purple-50 text-purple-700 ring-1 ring-inset ring-purple-600/20",
                          submission.status == "review_denied" &&
                            "bg-rose-50 text-rose-700 ring-1 ring-inset ring-rose-600/20"
                        ]}>
                          {format_status(submission.status)}
                        </span>
                      </div>
                      <%!-- Task Name as Link --%>
                      <.link
                        navigate={
                          if submission.status == "completed",
                            do: ~p"/student/tasks/#{submission.task.id}?preview=true",
                            else: ~p"/student/tasks/#{submission.task.id}"
                        }
                        class="text-xl font-semibold text-gray-800 hover:text-gray-900 transition-colors duration-150"
                      >
                        {submission.task.name}
                      </.link>
                    </div>
                    <%!-- Action Button or Completion Indicator --%>
                    <div class="flex-shrink-0">
                      <%= cond do %>
                        <% submission.status == "completed" || submission.status == "review_approved" -> %>
                          <div class="text-3xl">✅</div>
                        <% submission.status == "review_denied" -> %>
                          <div class="text-3xl">❌</div>
                        <% true -> %>
                          <.link
                            navigate={~p"/student/tasks/#{submission.task.id}"}
                            class="inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 transition-colors duration-150 shadow-sm"
                          >
                            {if submission.status in ["not_started", "open", "draft"],
                              do: "Starten",
                              else: "Öffnen"}
                          </.link>
                      <% end %>
                    </div>
                  </div>
                </div>
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

    {:ok,
     socket
     |> assign(:page_title, course.name)
     |> assign(:course, course)
     |> assign(:submissions, submissions)
     |> assign(:stats, stats)}
  end

  defp format_status(status) do
    case status do
      "draft" -> "Entwurf"
      "not_started" -> "Nicht begonnen"
      "open" -> "Offen"
      "in_progress" -> "In Bearbeitung"
      "completed" -> "Erledigt"
      "review_approved" -> "Genehmigt"
      "review_denied" -> "Abgelehnt"
      _ -> status |> String.replace("_", " ") |> String.capitalize()
    end
  end

  @impl true
  def handle_info({:submission_updated, _updated_submission}, socket) do
    # Reload all submissions to get the latest state
    submissions =
      Tasks.list_course_submissions(socket.assigns.current_scope, socket.assigns.course.id)

    stats = calculate_stats(submissions)

    {:noreply,
     socket
     |> assign(:submissions, submissions)
     |> assign(:stats, stats)
     |> put_flash(:info, "Aufgabenstatus aktualisiert!")}
  end

  defp calculate_stats(submissions) do
    %{
      total: length(submissions),
      completed: Enum.count(submissions, &(&1.status == "completed")),
      graded: Enum.count(submissions, &(&1.status == "review_approved"))
    }
  end
end
