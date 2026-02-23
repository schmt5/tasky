defmodule TaskyWeb.Student.TaskLive do
  use TaskyWeb, :live_view

  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto">
        <.header>
          {@task.name}
          <:subtitle>
            <div class="flex items-center gap-4 mt-2">
              <span class={[
                "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium",
                @submission.status == "not_started" && "bg-gray-100 text-gray-800",
                @submission.status == "in_progress" && "bg-yellow-100 text-yellow-800",
                @submission.status == "completed" && "bg-green-100 text-green-800"
              ]}>
                {format_status(@submission.status)}
              </span>
              <%= if @submission.completed_at do %>
                <span class="text-sm text-gray-500">
                  Completed {format_date(@submission.completed_at)}
                </span>
              <% end %>
            </div>
          </:subtitle>

          <:actions>
            <.button navigate={~p"/student/my-tasks"}>
              <.icon name="hero-arrow-left" /> Back to My Tasks
            </.button>
          </:actions>
        </.header>

        <div class="mt-8 space-y-8">
          <%!-- Task Details --%>
          <div class="bg-white shadow rounded-lg p-6">
            <h2 class="text-lg font-semibold text-gray-900 mb-4">Task Details</h2>

            <.list>
              <:item title="Status">
                <span class={[
                  "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                  @task.status == "draft" && "bg-gray-100 text-gray-800",
                  @task.status == "published" && "bg-blue-100 text-blue-800",
                  @task.status == "archived" && "bg-red-100 text-red-800"
                ]}>
                  {String.capitalize(@task.status)}
                </span>
              </:item>

              <:item :if={@task.link} title="Link">
                <a
                  href={@task.link}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-blue-600 hover:text-blue-700 underline flex items-center gap-1"
                >
                  {@task.link} <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                </a>
              </:item>

              <:item :if={@task.position} title="Position">{@task.position}</:item>
            </.list>
          </div>
          <%!-- Action Buttons --%>
          <%= if @submission.status == "not_started" do %>
            <div class="bg-blue-50 border border-blue-200 rounded-lg p-6">
              <h3 class="text-lg font-semibold text-blue-900 mb-2">Ready to Start?</h3>

              <p class="text-blue-700 mb-4">
                Click the button below to mark this task as in progress.
              </p>

              <.button
                variant="primary"
                phx-click="start_task"
                phx-value-id={@submission.id}
                class="w-full sm:w-auto"
              >
                <.icon name="hero-play" class="w-5 h-5" /> Start Task
              </.button>
            </div>
          <% end %>

          <%= if @submission.status == "in_progress" do %>
            <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-6">
              <h3 class="text-lg font-semibold text-yellow-900 mb-2">Task In Progress</h3>

              <p class="text-yellow-700 mb-4">
                Once you've completed this task, click the button below to submit it for grading.
              </p>

              <.button
                variant="primary"
                phx-click="complete_task"
                phx-value-id={@submission.id}
                class="w-full sm:w-auto bg-green-600 hover:bg-green-700"
              >
                <.icon name="hero-check-circle" class="w-5 h-5" /> Mark as Complete
              </.button>
            </div>
          <% end %>

          <%= if @submission.status == "completed" do %>
            <div class="bg-green-50 border border-green-200 rounded-lg p-6">
              <h3 class="text-lg font-semibold text-green-900 mb-2">Task Completed!</h3>

              <%= if @submission.graded_at do %>
                <div class="space-y-4">
                  <p class="text-green-700">Your task has been graded by your teacher.</p>

                  <div class="bg-white rounded-lg p-4 border border-green-200">
                    <div class="flex items-center justify-between mb-3">
                      <span class="text-sm font-medium text-gray-700">Score</span>
                      <span class="text-2xl font-bold text-green-600">
                        {@submission.points}<span class="text-sm text-gray-500">/100</span>
                      </span>
                    </div>

                    <%= if @submission.feedback && @submission.feedback != "" do %>
                      <div class="border-t border-gray-200 pt-3">
                        <span class="text-sm font-medium text-gray-700">Teacher Feedback</span>
                        <p class="mt-1 text-gray-600 whitespace-pre-wrap">{@submission.feedback}</p>
                      </div>
                    <% end %>

                    <%= if @submission.graded_at do %>
                      <div class="mt-3 text-xs text-gray-500">
                        Graded {format_date(@submission.graded_at)}
                      </div>
                    <% end %>
                  </div>
                </div>
              <% else %>
                <p class="text-green-700">
                  Your task has been submitted and is waiting for your teacher to grade it.
                </p>

                <div class="mt-4 flex items-center gap-2 text-sm text-green-600">
                  <.icon name="hero-clock" class="w-5 h-5 animate-pulse" />
                  <span>Waiting for grade...</span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)

    {:ok, submission} =
      Tasks.get_or_create_submission(
        socket.assigns.current_scope,
        id
      )

    {:ok,
     socket
     |> assign(:page_title, task.name)
     |> assign(:task, task)
     |> assign(:submission, submission)}
  end

  @impl true
  def handle_event("start_task", %{"id" => id}, socket) do
    {:ok, submission} =
      Tasks.update_submission_status(
        socket.assigns.current_scope,
        id,
        "in_progress"
      )

    {:noreply,
     socket
     |> put_flash(:info, "Task started! Good luck!")
     |> assign(:submission, submission)}
  end

  def handle_event("complete_task", %{"id" => id}, socket) do
    {:ok, submission} =
      Tasks.complete_task(
        socket.assigns.current_scope,
        id
      )

    {:noreply,
     socket
     |> put_flash(:info, "Task completed! Your teacher will grade it soon.")
     |> assign(:submission, submission)}
  end

  defp format_status(status) do
    status
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end
end
