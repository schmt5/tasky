defmodule TaskyWeb.Student.MyTasksLive do
  use TaskyWeb, :live_view

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
    <Layouts.app flash={@flash} current_scope={@current_scope} phx-hook=".OpenLink">
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
            <div class="space-y-6">
              <div
                :for={submission <- @submissions}
                class="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow duration-200 overflow-hidden border border-gray-200"
              >
                <%!-- Card Header with Status Badge --%>
                <div class="px-6 py-4 border-b border-gray-100 bg-gradient-to-r from-gray-50 to-white">
                  <div class="flex items-start justify-between">
                    <span class={[
                      "inline-flex items-center px-3 py-1 rounded-full text-xs font-medium",
                      submission.status == "draft" && "bg-gray-100 text-gray-800",
                      submission.status == "not_started" && "bg-gray-100 text-gray-800",
                      submission.status == "open" && "bg-gray-200 text-gray-700",
                      submission.status == "in_progress" && "bg-blue-100 text-blue-800",
                      submission.status == "completed" && "bg-green-100 text-green-800",
                      submission.status == "review_approved" && "bg-purple-100 text-purple-800",
                      submission.status == "review_denied" && "bg-red-100 text-red-800"
                    ]}>
                      {format_status(submission.status)}
                    </span>
                  </div>
                </div>
                <%!-- Card Body --%>
                <div class="px-6 py-5">
                  <%!-- Task Name as Clickable Link --%>
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
                    </div>
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
                      <% submission.status == "review_approved" -> %>
                        <span class="flex items-center gap-1 text-purple-600 font-medium">
                          <.icon name="hero-check-circle" class="w-4 h-4" /> Approved
                        </span>
                      <% submission.status == "review_denied" -> %>
                        <span class="flex items-center gap-1 text-red-600 font-medium">
                          <.icon name="hero-x-circle" class="w-4 h-4" /> Denied
                        </span>
                      <% submission.status == "completed" -> %>
                        <span class="flex items-center gap-1 text-green-600 font-medium">
                          <.icon name="hero-clock" class="w-4 h-4" /> Under review
                        </span>
                      <% submission.status == "in_progress" -> %>
                        <span class="flex items-center gap-1 text-blue-600 font-medium">
                          <.icon name="hero-arrow-path" class="w-4 h-4" /> In progress
                        </span>
                      <% submission.status == "open" -> %>
                        <span class="flex items-center gap-1 text-gray-500 font-medium">
                          <.icon name="hero-document-text" class="w-4 h-4" /> Open
                        </span>
                      <% submission.status == "not_started" -> %>
                        <span class="flex items-center gap-1 text-gray-500">
                          <.icon name="hero-document-text" class="w-4 h-4" /> Not started
                        </span>
                      <% submission.status == "draft" -> %>
                        <span class="flex items-center gap-1 text-gray-500">
                          <.icon name="hero-document-text" class="w-4 h-4" /> Draft
                        </span>
                      <% true -> %>
                        <span class="flex items-center gap-1 text-gray-500">
                          <.icon name="hero-document-text" class="w-4 h-4" /> Unknown
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
    # Subscribe to real-time updates for this student's submissions
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Tasky.PubSub,
        "student:#{socket.assigns.current_scope.user.id}:submissions"
      )
    end

    submissions = Tasks.list_my_submissions(socket.assigns.current_scope)

    stats = %{
      total: length(submissions),
      completed: Enum.count(submissions, &(&1.status == "completed")),
      graded: Enum.count(submissions, &(&1.status == "review_approved"))
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

  @impl true
  def handle_event(
        "mark_in_progress",
        %{"submission-id" => submission_id, "link" => link},
        socket
      ) do
    IO.inspect(submission_id, label: "Received submission_id")
    submission_id = String.to_integer(submission_id)
    submission = Enum.find(socket.assigns.submissions, &(&1.id == submission_id))
    IO.inspect(submission, label: "Found submission")

    # Only mark as in_progress if it's currently open or draft
    IO.inspect(submission && submission.status, label: "Current status")

    socket =
      if submission && submission.status in ["open", "draft", "not_started"] do
        IO.puts("Attempting to update status to in_progress")

        case Tasks.update_submission_status(
               socket.assigns.current_scope,
               submission_id,
               "in_progress"
             ) do
          {:ok, _updated_submission} ->
            IO.puts("Successfully updated to in_progress")
            # Reload submissions to reflect the change
            submissions = Tasks.list_my_submissions(socket.assigns.current_scope)

            stats = %{
              total: length(submissions),
              completed: Enum.count(submissions, &(&1.status == "completed")),
              graded: Enum.count(submissions, &(&1.status == "review_approved"))
            }

            socket
            |> assign(:submissions, submissions)
            |> assign(:stats, stats)

          {:error, changeset} ->
            IO.inspect(changeset, label: "Error updating submission")
            socket
        end
      else
        IO.puts("Submission not found or status not open/draft")
        socket
      end

    # Open the link using JS command
    {:noreply, push_event(socket, "open_link", %{url: link})}
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  @impl true
  def handle_info({:submission_updated, _updated_submission}, socket) do
    # Reload all submissions to get the latest state
    submissions = Tasks.list_my_submissions(socket.assigns.current_scope)

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
