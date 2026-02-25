defmodule TaskyWeb.Student.CourseLive do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@course.name}
        <:subtitle>{@course.description || "No description provided"}</:subtitle>
        <:actions>
          <.button navigate={~p"/student/courses"}>
            <.icon name="hero-arrow-left" /> Back to Courses
          </.button>
        </:actions>
      </.header>

      <div class="mt-8">
        <div class="bg-white shadow rounded-lg p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-xl font-semibold text-gray-900">Course Tasks</h2>
            <span class="text-sm text-gray-500">
              {length(@course.tasks)} {if length(@course.tasks) == 1, do: "task", else: "tasks"}
            </span>
          </div>

          <div class="space-y-3">
            <div
              :for={task <- @course.tasks}
              :if={task.status == "published"}
              class="flex items-center justify-between p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
            >
              <div class="flex-1">
                <h3 class="font-medium text-gray-900">{task.name}</h3>
                <div class="flex items-center gap-4 mt-1 text-sm text-gray-600">
                  <span>Position: {task.position}</span>
                  <span class={[
                    "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                    get_submission_status_class(@submissions_by_task[task.id])
                  ]}>
                    {get_submission_status_text(@submissions_by_task[task.id])}
                  </span>
                </div>
              </div>
              <div class="flex gap-2">
                <.button navigate={~p"/student/tasks/#{task.id}"}>
                  View Task
                </.button>
              </div>
            </div>
          </div>

          <div
            :if={Enum.all?(@course.tasks, fn task -> task.status != "published" end)}
            class="text-center py-8 text-gray-500"
          >
            <.icon name="hero-clipboard-document-list" class="w-12 h-12 mx-auto mb-2 text-gray-400" />
            <p>No published tasks available yet.</p>
          </div>
        </div>

        <div class="mt-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div class="flex items-start gap-3">
            <.icon name="hero-information-circle" class="w-5 h-5 text-blue-600 mt-0.5" />
            <div>
              <h3 class="font-medium text-blue-900">About This Course</h3>
              <p class="text-sm text-blue-700 mt-1">
                Teacher: <span class="font-medium">{@course.teacher.email}</span>
              </p>
              <p class="text-sm text-blue-700 mt-1">
                Complete all published tasks to finish the course.
              </p>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    student_id = socket.assigns.current_scope.user.id
    course = Courses.get_course_for_student!(student_id, id)

    submissions = Tasks.list_task_submissions(socket.assigns.current_scope, %{})
    submissions_by_task = Map.new(submissions, fn sub -> {sub.task_id, sub} end)

    {:ok,
     socket
     |> assign(:page_title, course.name)
     |> assign(:course, course)
     |> assign(:submissions_by_task, submissions_by_task)}
  end

  defp get_submission_status_class(nil), do: "bg-gray-200 text-gray-800"
  defp get_submission_status_class(%{status: "completed"}), do: "bg-green-100 text-green-800"
  defp get_submission_status_class(%{status: "in_progress"}), do: "bg-yellow-100 text-yellow-800"

  defp get_submission_status_class(%{status: "review_approved"}),
    do: "bg-green-100 text-green-800"

  defp get_submission_status_class(%{status: "review_denied"}), do: "bg-red-100 text-red-800"
  defp get_submission_status_class(_), do: "bg-gray-200 text-gray-800"

  defp get_submission_status_text(nil), do: "Not Started"
  defp get_submission_status_text(%{status: "completed"}), do: "Completed"
  defp get_submission_status_text(%{status: "in_progress"}), do: "In Progress"
  defp get_submission_status_text(%{status: "review_approved"}), do: "Approved"
  defp get_submission_status_text(%{status: "review_denied"}), do: "Needs Revision"

  defp get_submission_status_text(%{status: status}),
    do: String.capitalize(String.replace(status, "_", " "))
end
