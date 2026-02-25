defmodule TaskyWeb.Student.CourseLive do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".OpenLink">
      export default {
        mounted() {
          this.handleEvent("open_link", ({url}) => {
            window.open(url, '_blank');
          });
        }
      }
    </script>
    <div id="course-tasks-container" phx-hook=".OpenLink">
      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <%!-- Header --%>
        <div class="bg-white max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 pt-6">
          <.header>
            {@course.name}
            <:subtitle>
              {@course.description || "Sieh dir alle Aufgaben für diesen Kurs an"}
            </:subtitle>
            <:actions>
              <.link
                navigate={~p"/student/courses"}
                class="text-sm font-semibold text-gray-700 hover:text-gray-900"
              >
                <.icon name="hero-arrow-left" class="w-4 h-4 inline" /> Zurück
              </.link>
            </:actions>
          </.header>
        </div>

        <%= if @submissions != [] do %>
          <%!-- Progress Bar - Sticky --%>
          <div class="sticky top-0 z-10 -mt-8">
            <div class="max-w-5xl bg-white mx-auto px-4 sm:px-6 lg:px-8 py-6">
              <div class="flex items-center justify-between mb-2">
                <h3 class="text-sm font-semibold text-gray-700">Fortschritt</h3>
                <span class="text-2xl font-bold text-blue-600">
                  {if @stats.total > 0,
                    do: round(@stats.completed / @stats.total * 100),
                    else: 0}%
                </span>
              </div>
              <div class="w-full bg-gray-200 rounded-full h-3 overflow-hidden">
                <div
                  class="bg-gradient-to-r from-blue-500 to-blue-600 h-3 rounded-full transition-all duration-500 ease-out"
                  style={"width: #{if @stats.total > 0, do: (@stats.completed / @stats.total * 100), else: 0}%"}
                >
                </div>
              </div>
              <div class="mt-2 flex items-center justify-end text-xs text-gray-500">
                <span>
                  {@stats.completed} von {@stats.total} erledigt
                </span>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Task List --%>
        <div class="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
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
                      <%= if submission.task.link do %>
                        <div
                          phx-click="mark_in_progress"
                          phx-value-submission-id={submission.id}
                          phx-value-link={"#{submission.task.link}?user_id=#{@current_scope.user.id}&task_id=#{submission.task.id}&user_name=#{@current_scope.user.email}"}
                        >
                          <a
                            href={"#{submission.task.link}?user_id=#{@current_scope.user.id}&task_id=#{submission.task.id}&user_name=#{@current_scope.user.email}"}
                            target="_blank"
                            rel="noopener noreferrer"
                            class="text-xl font-semibold text-gray-800 hover:text-gray-900 transition-colors duration-150"
                          >
                            {submission.task.name}
                          </a>
                        </div>
                      <% else %>
                        <h3 class="text-xl font-semibold text-gray-900">
                          {submission.task.name}
                        </h3>
                      <% end %>
                    </div>
                    <%!-- Action Button or Completion Indicator --%>
                    <div class="flex-shrink-0">
                      <%= cond do %>
                        <% submission.status == "completed" || submission.status == "review_approved" -> %>
                          <div class="text-3xl">
                            ✅
                          </div>
                        <% submission.status == "review_denied" -> %>
                          <div class="text-3xl">
                            ❌
                          </div>
                        <% submission.task.link -> %>
                          <div
                            phx-click="mark_in_progress"
                            phx-value-submission-id={submission.id}
                            phx-value-link={"#{submission.task.link}?user_id=#{@current_scope.user.id}&task_id=#{submission.task.id}&user_name=#{@current_scope.user.email}"}
                          >
                            <a
                              href={"#{submission.task.link}?user_id=#{@current_scope.user.id}&task_id=#{submission.task.id}&user_name=#{@current_scope.user.email}"}
                              target="_blank"
                              rel="noopener noreferrer"
                              class="inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 transition-colors duration-150 shadow-sm"
                            >
                              {if submission.status in ["not_started", "open", "draft"],
                                do: "Starten",
                                else: "Öffnen"}
                            </a>
                          </div>
                        <% true -> %>
                          <div class="w-6 h-6 rounded border-2 border-gray-300 bg-white"></div>
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

    stats = %{
      total: length(submissions),
      completed: Enum.count(submissions, &(&1.status == "completed")),
      graded: Enum.count(submissions, &(&1.status == "review_approved"))
    }

    {:ok,
     socket
     |> assign(:page_title, course.name)
     |> assign(:course, course)
     |> assign(:submissions, submissions)
     |> assign(:stats, stats)}
  end

  defp format_status(status) do
    status
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  @impl true
  def handle_event(
        "mark_in_progress",
        %{"submission-id" => submission_id, "link" => link},
        socket
      ) do
    submission_id = String.to_integer(submission_id)
    submission = Enum.find(socket.assigns.submissions, &(&1.id == submission_id))

    socket =
      if submission && submission.status in ["open", "draft", "not_started"] do
        case Tasks.update_submission_status(
               socket.assigns.current_scope,
               submission_id,
               "in_progress"
             ) do
          {:ok, _updated_submission} ->
            # Reload submissions to reflect the change
            submissions =
              Tasks.list_course_submissions(
                socket.assigns.current_scope,
                socket.assigns.course.id
              )

            stats = %{
              total: length(submissions),
              completed: Enum.count(submissions, &(&1.status == "completed")),
              graded: Enum.count(submissions, &(&1.status == "review_approved"))
            }

            socket
            |> assign(:submissions, submissions)
            |> assign(:stats, stats)

          {:error, _changeset} ->
            socket
        end
      else
        socket
      end

    # Open the link using JS command
    {:noreply, push_event(socket, "open_link", %{url: link})}
  end

  @impl true
  def handle_info({:submission_updated, _updated_submission}, socket) do
    # Reload all submissions to get the latest state
    submissions =
      Tasks.list_course_submissions(socket.assigns.current_scope, socket.assigns.course.id)

    stats = %{
      total: length(submissions),
      completed: Enum.count(submissions, &(&1.status == "completed")),
      graded: Enum.count(submissions, &(&1.status == "review_approved"))
    }

    {:noreply,
     socket
     |> assign(:submissions, submissions)
     |> assign(:stats, stats)
     |> put_flash(:info, "Task status updated!")}
  end
end
