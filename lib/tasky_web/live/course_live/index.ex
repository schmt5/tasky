defmodule TaskyWeb.CourseLive.Index do
  use TaskyWeb, :live_view

  alias Tasky.Courses

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        My Courses
        <:actions>
          <.button variant="primary" navigate={~p"/courses/new"}>
            <.icon name="hero-plus" /> New Course
          </.button>
        </:actions>
      </.header>

      <div
        :if={@has_courses}
        id="courses"
        phx-update="stream"
        class="grid gap-6 mt-8 md:grid-cols-2 lg:grid-cols-3"
      >
        <div
          :for={{id, course} <- @streams.courses}
          id={id}
          class="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow duration-200 overflow-hidden"
        >
          <.link navigate={~p"/courses/#{course}"} class="block p-6 hover:bg-gray-50">
            <h3 class="text-xl font-semibold text-gray-900 mb-2">{course.name}</h3>
            <p class="text-gray-600 text-sm mb-4 line-clamp-3">
              {course.description || "No description provided"}
            </p>
            <div class="flex items-center justify-between text-sm text-gray-500">
              <span class="flex items-center gap-1">
                <.icon name="hero-academic-cap" class="w-4 h-4" />
                {course.teacher.email}
              </span>
              <span class="flex items-center gap-1">
                <.icon name="hero-clipboard-document-list" class="w-4 h-4" />
                {length(course.tasks || [])} tasks
              </span>
            </div>
          </.link>
          <div class="bg-gray-50 px-6 py-3 flex gap-2 justify-end border-t border-gray-200">
            <.link
              navigate={~p"/courses/#{course}/edit"}
              class="text-blue-600 hover:text-blue-700 text-sm font-medium"
            >
              Edit
            </.link>
            <.link
              phx-click={JS.push("delete", value: %{id: course.id}) |> hide("##{id}")}
              data-confirm="Are you sure? This will delete all tasks in this course."
              class="text-red-600 hover:text-red-700 text-sm font-medium"
            >
              Delete
            </.link>
          </div>
        </div>
      </div>

      <div
        :if={!@has_courses}
        class="text-center py-12"
      >
        <.icon name="hero-academic-cap" class="w-16 h-16 text-gray-400 mx-auto mb-4" />
        <h3 class="text-lg font-medium text-gray-900 mb-2">No courses yet</h3>
        <p class="text-gray-600 mb-4">Get started by creating your first course.</p>
        <.button variant="primary" navigate={~p"/courses/new"}>
          <.icon name="hero-plus" /> Create Course
        </.button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    courses = list_courses(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Courses")
     |> assign(:has_courses, length(courses) > 0)
     |> stream(:courses, courses)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    course = Courses.get_course!(socket.assigns.current_scope, id)
    {:ok, _} = Courses.delete_course(course)

    courses = list_courses(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(:has_courses, length(courses) > 0)
     |> stream_delete(:courses, course)}
  end

  defp list_courses(current_scope) do
    Courses.list_courses(current_scope)
  end
end
