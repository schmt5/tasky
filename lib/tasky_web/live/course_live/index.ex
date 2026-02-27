defmodule TaskyWeb.CourseLive.Index do
  use TaskyWeb, :live_view

  alias Tasky.Courses

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="bg-white border-b border-stone-100 px-8 py-12">
        <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-sky-500 mb-3">
          Course Management
        </div>
        <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
          My <em class="italic text-sky-500">Courses</em>
        </h1>
        <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
          Manage your courses, assignments, and enrolled students.
        </p>
      </div>

      <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
        <div class="flex items-center justify-between p-6 border-b border-stone-100">
          <div>
            <h2 class="text-lg font-semibold text-stone-800">All Courses</h2>
            <p class="text-sm text-stone-500 mt-1">
              {@course_count} courses total
            </p>
          </div>
          <.link
            navigate={~p"/courses/new"}
            class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> New Course
          </.link>
        </div>

        <ul :if={@has_courses} id="courses" phx-update="stream" class="list-none p-0 m-0">
          <li
            :for={{id, course} <- @streams.courses}
            id={id}
            class="flex items-start gap-5 px-6 py-5 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 hover:bg-stone-50"
          >
            <.link
              navigate={~p"/courses/#{course}"}
              class="w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5 bg-sky-100 text-sky-600"
            >
              <.icon name="hero-academic-cap" class="w-5 h-5" />
            </.link>

            <.link
              navigate={~p"/courses/#{course}"}
              class="flex-1 min-w-0 flex flex-col gap-1.5"
            >
              <div class="flex items-center gap-2.5 flex-wrap">
                <h3 class="text-[15px] font-semibold text-stone-800 leading-[1.4]">
                  {course.name}
                </h3>
              </div>

              <p class="text-sm text-stone-500 leading-[1.6] max-w-[600px]">
                {course.description || "No description provided"}
              </p>

              <div class="flex items-center gap-2 mt-1">
                <span class="text-[13px] text-stone-400 flex items-center gap-1">
                  <.icon name="hero-user" class="w-3.5 h-3.5" /> {course.teacher.email}
                </span>
                <span class="text-xs text-stone-300">·</span>
                <span class="text-[13px] text-stone-400 flex items-center gap-1">
                  <.icon name="hero-clipboard-document-list" class="w-3.5 h-3.5" />
                  {length(course.tasks || [])} tasks
                </span>
              </div>
            </.link>

            <div class="flex items-center gap-2 shrink-0 pt-0.5">
              <.link
                navigate={~p"/courses/#{course}/edit"}
                class="inline-flex items-center gap-2 bg-transparent text-stone-500 text-[13px] font-medium px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-sky-50 hover:text-sky-600"
              >
                <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit
              </.link>
              <button
                type="button"
                phx-click={JS.push("delete", value: %{id: course.id}) |> hide("##{id}")}
                data-confirm="Are you sure? This will delete all tasks in this course."
                class="inline-flex items-center gap-2 text-red-600 text-[13px] font-medium px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-red-100 hover:text-red-700"
              >
                <.icon name="hero-trash" class="w-4 h-4" />
              </button>
            </div>
          </li>
        </ul>

        <div :if={!@has_courses} class="flex flex-col items-center text-center px-8 py-16 bg-white">
          <div class="w-14 h-14 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-5">
            <.icon name="hero-academic-cap" class="w-6 h-6" />
          </div>
          <h3 class="text-base font-semibold text-stone-700 mb-2">No courses yet</h3>
          <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6] mb-6">
            Get started by creating your first course to organize your assignments.
          </p>
          <.link
            navigate={~p"/courses/new"}
            class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Create First Course
          </.link>
        </div>
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
     |> assign(:course_count, length(courses))
     |> assign(:has_courses, length(courses) > 0)
     |> stream(:courses, courses)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    course = Courses.get_course!(socket.assigns.current_scope, id)
    {:ok, _} = Courses.delete_course(course)

    new_count = socket.assigns.course_count - 1

    {:noreply,
     socket
     |> assign(:course_count, new_count)
     |> assign(:has_courses, new_count > 0)
     |> stream_delete(:courses, course)}
  end

  defp list_courses(current_scope) do
    Courses.list_courses(current_scope)
  end
end
