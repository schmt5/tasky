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
            <.icon name="hero-arrow-left" /> Back to Courses
          </.button>
          <.button navigate={~p"/courses/#{@course}/add"}>
            <.icon name="hero-plus" /> Lerneinheiten hinzufügen
          </.button>
          <.button variant="primary" navigate={~p"/courses/#{@course}/edit?return_to=show"}>
            <.icon name="hero-pencil" /> Edit Course
          </.button>
        </:actions>
      </.header>

      <div class="mt-8 space-y-8">
        <!-- Tasks Section -->
        <div class="bg-white shadow rounded-lg p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-xl font-semibold text-gray-900">Tasks</h2>
            <.button variant="primary" phx-click="new_task">
              <.icon name="hero-plus" class="w-4 h-4" /> Add Task
            </.button>
          </div>

          <%= if @show_task_form do %>
            <div class="mb-6 p-4 bg-gray-50 rounded-lg border border-gray-200">
              <.form for={@task_form} id="task-form" phx-submit="save_task" phx-change="validate_task">
                <input type="hidden" name="task[course_id]" value={@course.id} />
                <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                  <.input field={@task_form[:name]} type="text" label="Task Name" required />
                  <.input field={@task_form[:link]} type="text" label="Link" required />
                  <.input field={@task_form[:position]} type="number" label="Position" required />
                  <.input
                    field={@task_form[:status]}
                    type="select"
                    label="Status"
                    options={[
                      {"Draft", "draft"},
                      {"Published", "published"},
                      {"Archived", "archived"}
                    ]}
                    required
                  />
                </div>
                <div class="flex gap-2 mt-4">
                  <.button type="submit" variant="primary">Save Task</.button>
                  <.button type="button" phx-click="cancel_task">Cancel</.button>
                </div>
              </.form>
            </div>
          <% end %>

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
                  Edit
                </.link>
                <.link
                  phx-click={JS.push("delete_task", value: %{id: task.id}) |> hide("##{id}")}
                  data-confirm="Are you sure?"
                  class="text-red-600 hover:text-red-700 text-sm font-medium"
                >
                  Delete
                </.link>
              </div>
            </div>
          </div>

          <div :if={!@has_tasks} class="text-center py-8 text-gray-500">
            <.icon name="hero-clipboard-document-list" class="w-12 h-12 mx-auto mb-2 text-gray-400" />
            <p>No tasks yet. Add your first task to get started.</p>
          </div>
        </div>
        
    <!-- Students Section -->
        <div class="bg-white shadow rounded-lg p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-xl font-semibold text-gray-900">Enrolled Students</h2>
            <.button variant="primary" phx-click="show_enroll_modal">
              <.icon name="hero-user-plus" class="w-4 h-4" /> Enroll Students
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
                data-confirm="Are you sure you want to unenroll this student?"
                class="text-red-600 hover:text-red-700 text-sm font-medium"
              >
                Unenroll
              </.link>
            </div>
          </div>

          <div
            :if={!@has_students}
            class="text-center py-8 text-gray-500"
          >
            <.icon name="hero-users" class="w-12 h-12 mx-auto mb-2 text-gray-400" />
            <p>No students enrolled yet.</p>
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
              <h3 class="text-lg font-semibold text-gray-900 mb-4">Enroll Students</h3>

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
                    Enroll
                  </.button>
                </div>
              </div>

              <div :if={Enum.empty?(@unenrolled_students)} class="text-center py-8 text-gray-500">
                <p>All students are already enrolled in this course.</p>
              </div>

              <div class="mt-6 flex justify-end">
                <.button phx-click="hide_enroll_modal">Close</.button>
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
     |> assign(:show_task_form, false)
     |> assign(:show_enroll_modal, false)
     |> assign(:unenrolled_students, [])
     |> assign(:task_form, nil)
     |> assign(:has_tasks, length(course.tasks) > 0)
     |> assign(:has_students, length(enrolled_students) > 0)
     |> stream(:tasks, course.tasks)
     |> stream(:enrolled_students, enrolled_students)}
  end

  @impl true
  def handle_event("new_task", _params, socket) do
    task_form =
      Tasks.change_task(
        socket.assigns.current_scope,
        %Tasks.Task{
          user_id: socket.assigns.current_scope.user.id,
          course_id: socket.assigns.course.id,
          position: length(socket.assigns.course.tasks) + 1,
          status: "draft"
        }
      )
      |> to_form()

    {:noreply,
     socket
     |> assign(:show_task_form, true)
     |> assign(:task_form, task_form)}
  end

  def handle_event("cancel_task", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_task_form, false)
     |> assign(:task_form, nil)}
  end

  def handle_event("validate_task", %{"task" => task_params}, socket) do
    changeset =
      Tasks.change_task(
        socket.assigns.current_scope,
        %Tasks.Task{
          user_id: socket.assigns.current_scope.user.id,
          course_id: socket.assigns.course.id
        },
        task_params
      )

    {:noreply, assign(socket, task_form: to_form(changeset, action: :validate))}
  end

  def handle_event("save_task", %{"task" => task_params}, socket) do
    case Tasks.create_task(socket.assigns.current_scope, task_params) do
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task created successfully")
         |> assign(:show_task_form, false)
         |> assign(:task_form, nil)
         |> assign(:has_tasks, true)
         |> stream_insert(:tasks, task)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, task_form: to_form(changeset))}
    end
  end

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
