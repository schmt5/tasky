defmodule TaskyWeb.Student.CoursesLive do
  use TaskyWeb, :live_view

  alias Tasky.Courses

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        My Courses
        <:subtitle>View all courses you're enrolled in</:subtitle>
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
          <.link navigate={~p"/student/courses/#{course.id}"} class="block p-6 hover:bg-gray-50">
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
          <div class="bg-gray-50 px-6 py-3 border-t border-gray-200">
            <.link
              navigate={~p"/student/courses/#{course.id}"}
              class="text-blue-600 hover:text-blue-700 text-sm font-medium"
            >
              View Course →
            </.link>
          </div>
        </div>
      </div>

      <div :if={!@has_courses} class="text-center py-12">
        <.icon name="hero-academic-cap" class="w-16 h-16 text-gray-400 mx-auto mb-4" />
        <h3 class="text-lg font-medium text-gray-900 mb-2">No courses yet</h3>
        <p class="text-gray-600">You haven't been enrolled in any courses yet.</p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    courses = Courses.list_enrolled_courses(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "My Courses")
     |> assign(:has_courses, length(courses) > 0)
     |> stream(:courses, courses)}
  end
end
