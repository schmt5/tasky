defmodule TaskyWeb.Student.MyTasksLive do
  use TaskyWeb, :live_view

  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-7xl mx-auto">
        <.header>
          My Tasks
          <:subtitle>View and manage all your assigned tasks</:subtitle>
        </.header>

        <div class="mt-8">
          <%= if @submissions == [] do %>
            <div class="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
              <.icon name="hero-document-text" class="mx-auto h-12 w-12 text-gray-400" />
              <h3 class="mt-2 text-sm font-semibold text-gray-900">No tasks yet</h3>

              <p class="mt-1 text-sm text-gray-500">
                You haven't been assigned any tasks yet. Check back later!
              </p>
            </div>
          <% else %>
            <%!-- Task Cards Grid --%>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <div
                :for={submission <- @submissions}
                class="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow duration-200 overflow-hidden border border-gray-200"
              >
                <%!-- Card Header with Status Badge --%>
                <div class="px-6 py-4 border-b border-gray-100 bg-gradient-to-r from-gray-50 to-white">
                  <div class="flex items-start justify-between">
                    <span class={[
                      "inline-flex items-center px-3 py-1 rounded-full text-xs font-medium",
                      submission.status == "not_started" && "bg-gray-100 text-gray-800",
                      submission.status == "in_progress" && "bg-yellow-100 text-yellow-800",
                      submission.status == "completed" && "bg-green-100 text-green-800"
                    ]}>
                      {format_status(submission.status)}
                    </span>
                  </div>
                </div>
                <%!-- Card Body --%>
                <div class="px-6 py-5">
                  <%!-- Task Name as Clickable Link --%>
                  <%= if submission.task.link do %>
                    <a
                      href={"#{submission.task.link}?user_id=#{@current_scope.user.id}&task_id=#{submission.task.id}&user_name=#{@current_scope.user.email}"}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="group block"
                    >
                      <h3 class="text-lg font-semibold text-gray-900 group-hover:text-blue-600 transition-colors duration-150 flex items-center gap-2">
                        {submission.task.name}
                        <.icon
                          name="hero-arrow-top-right-on-square"
                          class="w-5 h-5 text-gray-400 group-hover:text-blue-600 transition-colors duration-150"
                        />
                      </h3>
                    </a>
                  <% else %>
                    <h3 class="text-lg font-semibold text-gray-900">
                      {submission.task.name}
                    </h3>
                  <% end %>
                  <%!-- Task Metadata --%>
                  <div class="mt-4 space-y-3">
                    <%!-- Completion Date --%>
                    <div class="flex items-center justify-between text-sm">
                      <span class="text-gray-500 flex items-center gap-2">
                        <.icon name="hero-calendar" class="w-4 h-4" /> Completed
                      </span>
                      <%= if submission.completed_at do %>
                        <span class="font-medium text-gray-900">
                          {format_date(submission.completed_at)}
                        </span>
                      <% else %>
                        <span class="text-gray-400">Not yet</span>
                      <% end %>
                    </div>
                    <%!-- Score --%>
                    <div class="flex items-center justify-between text-sm">
                      <span class="text-gray-500 flex items-center gap-2">
                        <.icon name="hero-academic-cap" class="w-4 h-4" /> Score
                      </span>
                      <%= if submission.graded_at do %>
                        <div class="flex items-center gap-1">
                          <span class="text-lg font-bold text-green-600">
                            {submission.points}
                          </span>
                          <span class="text-xs text-gray-400">/100</span>
                        </div>
                      <% else %>
                        <%= if submission.status == "completed" do %>
                          <span class="text-xs text-yellow-600 flex items-center gap-1 font-medium">
                            <.icon name="hero-clock" class="w-4 h-4" /> Pending
                          </span>
                        <% else %>
                          <span class="text-gray-400">Not graded</span>
                        <% end %>
                      <% end %>
                    </div>
                  </div>
                </div>
                <%!-- Card Footer with Progress Indicator --%>
                <div class="px-6 py-3 bg-gray-50 border-t border-gray-100">
                  <div class="flex items-center justify-between text-xs text-gray-500">
                    <%= cond do %>
                      <% submission.graded_at -> %>
                        <span class="flex items-center gap-1 text-green-600 font-medium">
                          <.icon name="hero-check-circle" class="w-4 h-4" /> Graded
                        </span>
                      <% submission.status == "completed" -> %>
                        <span class="flex items-center gap-1 text-yellow-600 font-medium">
                          <.icon name="hero-clock" class="w-4 h-4" /> Awaiting grade
                        </span>
                      <% submission.status == "in_progress" -> %>
                        <span class="flex items-center gap-1 text-blue-600 font-medium">
                          <.icon name="hero-arrow-path" class="w-4 h-4" /> In progress
                        </span>
                      <% true -> %>
                        <span class="flex items-center gap-1 text-gray-500">
                          <.icon name="hero-document-text" class="w-4 h-4" /> Not started
                        </span>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
            <%!-- Summary Stats --%>
            <div class="mt-6 grid grid-cols-1 gap-5 sm:grid-cols-3">
              <div class="bg-white overflow-hidden shadow rounded-lg">
                <div class="p-5">
                  <div class="flex items-center">
                    <div class="flex-shrink-0">
                      <.icon name="hero-document-text" class="h-6 w-6 text-gray-400" />
                    </div>

                    <div class="ml-5 w-0 flex-1">
                      <dl>
                        <dt class="text-sm font-medium text-gray-500 truncate">Total Tasks</dt>

                        <dd class="text-lg font-semibold text-gray-900">{@stats.total}</dd>
                      </dl>
                    </div>
                  </div>
                </div>
              </div>

              <div class="bg-white overflow-hidden shadow rounded-lg">
                <div class="p-5">
                  <div class="flex items-center">
                    <div class="flex-shrink-0">
                      <.icon name="hero-check-circle" class="h-6 w-6 text-green-400" />
                    </div>

                    <div class="ml-5 w-0 flex-1">
                      <dl>
                        <dt class="text-sm font-medium text-gray-500 truncate">Completed</dt>

                        <dd class="text-lg font-semibold text-gray-900">{@stats.completed}</dd>
                      </dl>
                    </div>
                  </div>
                </div>
              </div>

              <div class="bg-white overflow-hidden shadow rounded-lg">
                <div class="p-5">
                  <div class="flex items-center">
                    <div class="flex-shrink-0">
                      <.icon name="hero-academic-cap" class="h-6 w-6 text-blue-400" />
                    </div>

                    <div class="ml-5 w-0 flex-1">
                      <dl>
                        <dt class="text-sm font-medium text-gray-500 truncate">Graded</dt>

                        <dd class="text-lg font-semibold text-gray-900">{@stats.graded}</dd>
                      </dl>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    submissions = Tasks.list_my_submissions(socket.assigns.current_scope)

    stats = %{
      total: length(submissions),
      completed: Enum.count(submissions, &(&1.status == "completed")),
      graded: Enum.count(submissions, &(&1.graded_at != nil))
    }

    {:ok,
     socket
     |> assign(:page_title, "My Tasks")
     |> assign(:submissions, submissions)
     |> assign(:stats, stats)}
  end

  defp format_status(status) do
    status
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end
end
