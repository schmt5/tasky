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
            <%!-- Progress Indicator --%>
            <div class="mb-8 bg-white rounded-lg shadow-md p-6 border border-gray-200">
              <div class="flex items-center justify-between mb-2">
                <h3 class="text-sm font-semibold text-gray-700">Progress Overview</h3>
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
              <div class="mt-3 flex items-center justify-end text-xs text-gray-500">
                <span>
                  {@stats.completed} completed
                </span>
              </div>
            </div>
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
                    <%!-- Completion Indicator --%>
                    <div class="flex-shrink-0">
                      <%= if submission.status == "completed" do %>
                        <div class="text-2xl">
                          ✅
                        </div>
                      <% else %>
                        <div class="w-6 h-6 rounded border-2 border-gray-300 bg-white"></div>
                      <% end %>
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
