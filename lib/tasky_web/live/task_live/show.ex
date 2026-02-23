defmodule TaskyWeb.TaskLive.Show do
  use TaskyWeb, :live_view

  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@task.name}
        <:subtitle>Task details and submission statistics</:subtitle>
        <:actions>
          <.button navigate={~p"/tasks"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
          <.button navigate={~p"/tasks/#{@task}/submissions"}>
            <.icon name="hero-users" /> View Submissions
            <%= if @submission_stats.total > 0 do %>
              <span class="ml-1 inline-flex items-center justify-center px-2 py-1 text-xs font-bold leading-none text-white bg-blue-600 rounded-full">
                {@submission_stats.total}
              </span>
            <% end %>
          </.button>
          <.button variant="primary" navigate={~p"/tasks/#{@task}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit
          </.button>
        </:actions>
      </.header>

      <div class="mt-8 space-y-8">
        <%!-- Task Details --%>
        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">Task Details</h2>
          <.list>
            <:item title="Name">{@task.name}</:item>
            <:item :if={@task.link} title="Link">
              <a
                href={@task.link}
                target="_blank"
                rel="noopener noreferrer"
                class="text-blue-600 hover:text-blue-700 underline flex items-center gap-1"
              >
                {@task.link}
                <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
              </a>
            </:item>
            <:item :if={@task.position} title="Position">{@task.position}</:item>
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
          </.list>
        </div>

        <%!-- Submission Statistics --%>
        <%= if @submission_stats.total > 0 do %>
          <div class="bg-white shadow rounded-lg p-6">
            <h2 class="text-lg font-semibold text-gray-900 mb-4">Submission Statistics</h2>
            <div class="grid grid-cols-1 gap-5 sm:grid-cols-4">
              <div class="bg-gray-50 rounded-lg p-4">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <.icon name="hero-users" class="h-6 w-6 text-gray-400" />
                  </div>
                  <div class="ml-4">
                    <p class="text-sm font-medium text-gray-500">Total</p>
                    <p class="text-2xl font-semibold text-gray-900">{@submission_stats.total}</p>
                  </div>
                </div>
              </div>

              <div class="bg-green-50 rounded-lg p-4">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <.icon name="hero-check-circle" class="h-6 w-6 text-green-400" />
                  </div>
                  <div class="ml-4">
                    <p class="text-sm font-medium text-green-600">Completed</p>
                    <p class="text-2xl font-semibold text-green-900">
                      {@submission_stats.completed}
                    </p>
                  </div>
                </div>
              </div>

              <div class="bg-blue-50 rounded-lg p-4">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <.icon name="hero-academic-cap" class="h-6 w-6 text-blue-400" />
                  </div>
                  <div class="ml-4">
                    <p class="text-sm font-medium text-blue-600">Graded</p>
                    <p class="text-2xl font-semibold text-blue-900">{@submission_stats.graded}</p>
                  </div>
                </div>
              </div>

              <div class="bg-yellow-50 rounded-lg p-4">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <.icon name="hero-clock" class="h-6 w-6 text-yellow-400" />
                  </div>
                  <div class="ml-4">
                    <p class="text-sm font-medium text-yellow-600">Pending</p>
                    <p class="text-2xl font-semibold text-yellow-900">{@submission_stats.pending}</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Tasks.subscribe_tasks(socket.assigns.current_scope)
    end

    task = Tasks.get_task!(socket.assigns.current_scope, id)
    submissions = Tasks.list_task_submissions(socket.assigns.current_scope, id)

    submission_stats = %{
      total: length(submissions),
      completed: Enum.count(submissions, &(&1.status == "completed")),
      graded: Enum.count(submissions, &(&1.graded_at != nil)),
      pending: Enum.count(submissions, &(&1.status == "completed" and is_nil(&1.graded_at)))
    }

    {:ok,
     socket
     |> assign(:page_title, task.name)
     |> assign(:task, task)
     |> assign(:submission_stats, submission_stats)}
  end

  @impl true
  def handle_info(
        {:updated, %Tasky.Tasks.Task{id: id} = task},
        %{assigns: %{task: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :task, task)}
  end

  def handle_info(
        {:deleted, %Tasky.Tasks.Task{id: id}},
        %{assigns: %{task: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current task was deleted.")
     |> push_navigate(to: ~p"/tasks")}
  end

  def handle_info({type, %Tasky.Tasks.Task{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
