defmodule TaskyWeb.TaskLive.Index do
  use TaskyWeb, :live_view

  alias Tasky.Tasks
  import TaskyWeb.UI

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.page_header eyebrow="Task Management">
        <:title>Listing <em class="italic text-sky-500">Tasks</em></:title>
        <:description>Manage all tasks, assignments, and their submissions.</:description>
      </.page_header>

      <.card>
        <.card_header
          title="All Tasks"
          subtitle={"#{@task_count} tasks total"}
        >
          <:action>
            <.button_primary navigate={~p"/tasks/new"} class="text-sm px-5 py-2.5">
              <.icon name="hero-plus" class="w-4 h-4" /> New Task
            </.button_primary>
          </:action>
        </.card_header>

        <ul id="tasks" phx-update="stream" class="list-none p-0 m-0">
          <li
            :for={{id, task} <- @streams.tasks}
            id={id}
            class="flex items-start gap-5 px-6 py-5 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 hover:bg-stone-50"
          >
            <.list_icon color="sky" icon_name="hero-document-text" navigate={~p"/tasks/#{task}"} />

            <.link
              navigate={~p"/tasks/#{task}"}
              class="flex-1 min-w-0 flex flex-col gap-1.5"
            >
              <div class="flex items-center gap-2.5 flex-wrap">
                <h3 class="text-[15px] font-semibold text-stone-800 leading-[1.4]">
                  {task.name}
                </h3>
                <.badge color={
                  cond do
                    task.status == "draft" -> "stone"
                    task.status == "published" -> "sky"
                    task.status == "archived" -> "red"
                    true -> "stone"
                  end
                }>
                  {String.capitalize(task.status)}
                </.badge>
              </div>

              <%= if task.link do %>
                <p class="text-sm text-stone-500 leading-[1.6] max-w-[600px]">
                  <.icon name="hero-link" class="w-3.5 h-3.5 inline" />
                  {task.link}
                </p>
              <% end %>

              <div class="flex items-center gap-2 mt-1">
                <span class="text-[13px] text-stone-400 flex items-center gap-1">
                  <.icon name="hero-hashtag" class="w-3.5 h-3.5" /> Position {task.position}
                </span>
                <span class="text-xs text-stone-300">·</span>
                <.link
                  navigate={~p"/tasks/#{task}/submissions"}
                  class="text-[13px] text-stone-400 flex items-center gap-1 hover:text-sky-600 transition-colors"
                >
                  <.icon name="hero-users" class="w-3.5 h-3.5" /> View Submissions
                </.link>
              </div>
            </.link>

            <div class="flex items-center gap-2 shrink-0 pt-0.5">
              <.button_ghost navigate={~p"/tasks/#{task}/edit"} class="text-[13px] px-3.5 py-1.5">
                <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit
              </.button_ghost>
              <.button_danger
                phx-click={JS.push("delete", value: %{id: task.id}) |> hide("##{id}")}
                data-confirm="Are you sure you want to delete this task?"
                class="text-[13px] px-3.5 py-1.5"
              >
                <.icon name="hero-trash" class="w-4 h-4" />
              </.button_danger>
            </div>
          </li>
        </ul>

        <%= if @task_count == 0 do %>
          <.empty_state
            icon_name="hero-document-text"
            title="No tasks yet"
            description="Get started by creating your first task or assignment."
          >
            <:action>
              <.button_primary navigate={~p"/tasks/new"} class="text-sm px-5 py-2.5">
                <.icon name="hero-plus" class="w-4 h-4" /> Create First Task
              </.button_primary>
            </:action>
          </.empty_state>
        <% end %>
      </.card>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Tasks.subscribe_tasks(socket.assigns.current_scope)
    end

    tasks = list_tasks(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Listing Tasks")
     |> assign(:task_count, length(tasks))
     |> stream(:tasks, tasks)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)
    {:ok, _} = Tasks.delete_task(socket.assigns.current_scope, task)

    {:noreply,
     socket
     |> assign(:task_count, socket.assigns.task_count - 1)
     |> stream_delete(:tasks, task)}
  end

  @impl true
  def handle_info({type, %Tasky.Tasks.Task{}}, socket)
      when type in [:created, :updated, :deleted] do
    tasks = list_tasks(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(:task_count, length(tasks))
     |> stream(:tasks, tasks, reset: true)}
  end

  defp list_tasks(current_scope) do
    Tasks.list_tasks(current_scope)
  end
end
