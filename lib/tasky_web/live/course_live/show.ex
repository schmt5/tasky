defmodule TaskyWeb.CourseLive.Show do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Tasks
  alias Tasky.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@course.name}
        <:subtitle>{@course.description || "No description provided"}</:subtitle>
        <:actions>
          <.button navigate={~p"/courses"}>
            <.icon name="hero-arrow-left" /> Zurück zu Kursen
          </.button>
          <.button variant="primary" navigate={~p"/courses/#{@course}/edit?return_to=show"}>
            <.icon name="hero-pencil" /> Kurs bearbeiten
          </.button>
        </:actions>
      </.header>

      <div class="mt-8 space-y-8">
        <!-- Tasks Section -->
        <div class="bg-white shadow rounded-lg p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-xl font-semibold text-gray-900">Lerneinheiten</h2>
            <.button variant="primary" navigate={~p"/courses/#{@course}/add"}>
              <.icon name="hero-plus" /> Lerneinheiten hinzufügen
            </.button>
          </div>

          <div id="tasks" phx-update="stream" class="space-y-2">
            <div
              :for={{id, task} <- @streams.tasks}
              id={id}
              class="flex items-center justify-between p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
            >
              <div class="flex-1">
                <h3 class="font-medium text-gray-900">{task.name}</h3>
                <div class="flex items-center gap-4 mt-1 text-sm text-gray-600">
                  <a href={task.link} target="_blank" class="text-blue-600 hover:underline">
                    {task.link}
                  </a>
                  <span>Position: {task.position}</span>
                  <span class={[
                    "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                    task.status == "draft" && "bg-gray-200 text-gray-800",
                    task.status == "published" && "bg-blue-100 text-blue-800",
                    task.status == "archived" && "bg-red-100 text-red-800"
                  ]}>
                    {String.capitalize(task.status)}
                  </span>
                </div>
              </div>
              <div class="flex gap-2">
                <.link
                  navigate={~p"/tasks/#{task}/edit"}
                  class="text-blue-600 hover:text-blue-700 text-sm font-medium"
                >
                  Bearbeiten
                </.link>
                <.link
                  phx-click={JS.push("delete_task", value: %{id: task.id}) |> hide("##{id}")}
                  data-confirm="Sind Sie sicher?"
                  class="text-red-600 hover:text-red-700 text-sm font-medium"
                >
                  Löschen
                </.link>
              </div>
            </div>
          </div>

          <div :if={!@has_tasks} class="text-center py-8 text-gray-500">
            <.icon name="hero-clipboard-document-list" class="w-12 h-12 mx-auto mb-2 text-gray-400" />
            <p>Noch keine Lerneinheiten. Fügen Sie Ihre erste Lerneinheit hinzu.</p>
          </div>
        </div>
        
    <!-- Students Section -->
        <div class="bg-white shadow rounded-lg p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-xl font-semibold text-gray-900">Eingeschriebene Studenten</h2>
            <.button variant="primary" phx-click="show_enroll_modal">
              <.icon name="hero-user-plus" class="w-4 h-4" /> Studenten einschreiben
            </.button>
          </div>

          <div id="enrolled-students" phx-update="stream" class="space-y-2">
            <div
              :for={{id, student} <- @streams.enrolled_students}
              id={id}
              class="flex items-center justify-between p-3 bg-gray-50 rounded-lg"
            >
              <div class="flex items-center gap-2">
                <.icon name="hero-user-circle" class="w-5 h-5 text-gray-400" />
                <span class="text-gray-900">{student.email}</span>
              </div>
              <.link
                phx-click={
                  JS.push("unenroll_student", value: %{student_id: student.id}) |> hide("##{id}")
                }
                data-confirm="Sind Sie sicher, dass Sie diesen Studenten ausschreiben möchten?"
                class="text-red-600 hover:text-red-700 text-sm font-medium"
              >
                Ausschreiben
              </.link>
            </div>
          </div>

          <div
            :if={!@has_students}
            class="text-center py-8 text-gray-500"
          >
            <.icon name="hero-users" class="w-12 h-12 mx-auto mb-2 text-gray-400" />
            <p>Noch keine Studenten eingeschrieben.</p>
          </div>
        </div>
      </div>
      
    <!-- Enrollment Modal -->
      <%= if @show_enroll_modal do %>
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
          <div
            class="bg-white rounded-lg shadow-xl max-w-md w-full mx-4"
            phx-click-away="hide_enroll_modal"
          >
            <div class="p-6">
              <h3 class="text-lg font-semibold text-gray-900 mb-4">Studenten einschreiben</h3>

              <div class="space-y-2 max-h-96 overflow-y-auto">
                <div
                  :for={student <- @unenrolled_students}
                  class="flex items-center justify-between p-3 bg-gray-50 rounded-lg hover:bg-gray-100"
                >
                  <div class="flex items-center gap-2">
                    <.icon name="hero-user-circle" class="w-5 h-5 text-gray-400" />
                    <span class="text-gray-900">{student.email}</span>
                  </div>
                  <.button
                    phx-click="enroll_student"
                    phx-value-student_id={student.id}
                    variant="primary"
                  >
                    Einschreiben
                  </.button>
                </div>
              </div>

              <div :if={Enum.empty?(@unenrolled_students)} class="text-center py-8 text-gray-500">
                <p>Alle Studenten sind bereits in diesem Kurs eingeschrieben.</p>
              </div>

              <div class="mt-6 flex justify-end">
                <.button phx-click="hide_enroll_modal">Schließen</.button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    course = Courses.get_course!(socket.assigns.current_scope, id)
    enrolled_students = Courses.list_enrolled_students(course.id)

    {:ok,
     socket
     |> assign(:page_title, course.name)
     |> assign(:course, course)
     |> assign(:show_enroll_modal, false)
     |> assign(:unenrolled_students, [])
     |> assign(:has_tasks, length(course.tasks) > 0)
     |> assign(:has_students, length(enrolled_students) > 0)
     |> stream(:tasks, course.tasks)
     |> stream(:enrolled_students, enrolled_students)}
  end

  @impl true
  def handle_event("delete_task", %{"id" => id}, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)
    {:ok, _} = Tasks.delete_task(socket.assigns.current_scope, task)

    course = Courses.get_course!(socket.assigns.current_scope, socket.assigns.course.id)

    {:noreply,
     socket
     |> assign(:has_tasks, length(course.tasks) > 0)
     |> stream_delete(:tasks, task)}
  end

  def handle_event("show_enroll_modal", _params, socket) do
    unenrolled_students = Courses.list_unenrolled_students(socket.assigns.course.id)

    {:noreply,
     socket
     |> assign(:show_enroll_modal, true)
     |> assign(:unenrolled_students, unenrolled_students)}
  end

  def handle_event("hide_enroll_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_enroll_modal, false)
     |> assign(:unenrolled_students, [])}
  end

  def handle_event("enroll_student", %{"student_id" => student_id}, socket) do
    student_id = String.to_integer(student_id)

    case Courses.enroll_student(socket.assigns.course.id, student_id) do
      {:ok, _enrollment} ->
        student = Accounts.get_user!(student_id)

        unenrolled_students =
          Enum.reject(socket.assigns.unenrolled_students, &(&1.id == student_id))

        {:noreply,
         socket
         |> put_flash(:info, "Student enrolled successfully")
         |> assign(:has_students, true)
         |> stream_insert(:enrolled_students, student)
         |> assign(:unenrolled_students, unenrolled_students)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to enroll student")}
    end
  end

  def handle_event("unenroll_student", %{"student_id" => student_id}, socket) do
    student_id = String.to_integer(student_id)

    case Courses.unenroll_student(socket.assigns.course.id, student_id) do
      {:ok, _} ->
        student = Accounts.get_user!(student_id)
        enrolled_students = Courses.list_enrolled_students(socket.assigns.course.id)

        {:noreply,
         socket
         |> put_flash(:info, "Student unenrolled successfully")
         |> assign(:has_students, length(enrolled_students) > 0)
         |> stream_delete(:enrolled_students, student)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unenroll student")}
    end
  end
end
