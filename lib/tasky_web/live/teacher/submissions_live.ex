defmodule TaskyWeb.Teacher.SubmissionsLive do
  use TaskyWeb, :live_view

  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-7xl mx-auto">
        <.header>
          Submissions for {@task.name}
          <:subtitle>Review and grade student submissions</:subtitle>

          <:actions>
            <.button navigate={~p"/tasks/#{@task.id}"}>
              <.icon name="hero-arrow-left" /> Back to Task
            </.button>
            <.button variant="primary" phx-click="show_assign_modal">
              <.icon name="hero-user-plus" /> Assign Students
            </.button>
          </:actions>
        </.header>

        <div class="mt-8">
          <%= if @submissions == [] do %>
            <div class="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
              <.icon name="hero-users" class="mx-auto h-12 w-12 text-gray-400" />
              <h3 class="mt-2 text-sm font-semibold text-gray-900">No submissions yet</h3>

              <p class="mt-1 text-sm text-gray-500">
                Students haven't started working on this task yet.
              </p>
            </div>
          <% else %>
            <%!-- Summary Stats --%>
            <div class="mb-6 grid grid-cols-1 gap-5 sm:grid-cols-4">
              <div class="bg-white overflow-hidden shadow rounded-lg">
                <div class="p-5">
                  <div class="flex items-center">
                    <div class="flex-shrink-0">
                      <.icon name="hero-users" class="h-6 w-6 text-gray-400" />
                    </div>

                    <div class="ml-5 w-0 flex-1">
                      <dl>
                        <dt class="text-sm font-medium text-gray-500 truncate">Total Students</dt>

                        <dd class="text-lg font-semibold text-gray-900">{@stats.total}</dd>
                      </dl>
                    </div>
                  </div>
                </div>
              </div>

              <div class="bg-white overflow-hidden shadow rounded-lg">
                <div class="p-5">
                  <div class="flex items-center">
                    <div class="flex-shrink-0">
                      <.icon name="hero-check-circle" class="h-6 w-6 text-green-400" />
                    </div>

                    <div class="ml-5 w-0 flex-1">
                      <dl>
                        <dt class="text-sm font-medium text-gray-500 truncate">Completed</dt>

                        <dd class="text-lg font-semibold text-gray-900">{@stats.completed}</dd>
                      </dl>
                    </div>
                  </div>
                </div>
              </div>

              <div class="bg-white overflow-hidden shadow rounded-lg">
                <div class="p-5">
                  <div class="flex items-center">
                    <div class="flex-shrink-0">
                      <.icon name="hero-academic-cap" class="h-6 w-6 text-blue-400" />
                    </div>

                    <div class="ml-5 w-0 flex-1">
                      <dl>
                        <dt class="text-sm font-medium text-gray-500 truncate">Graded</dt>

                        <dd class="text-lg font-semibold text-gray-900">{@stats.graded}</dd>
                      </dl>
                    </div>
                  </div>
                </div>
              </div>

              <div class="bg-white overflow-hidden shadow rounded-lg">
                <div class="p-5">
                  <div class="flex items-center">
                    <div class="flex-shrink-0">
                      <.icon name="hero-clock" class="h-6 w-6 text-yellow-400" />
                    </div>

                    <div class="ml-5 w-0 flex-1">
                      <dl>
                        <dt class="text-sm font-medium text-gray-500 truncate">Pending</dt>

                        <dd class="text-lg font-semibold text-gray-900">{@stats.pending}</dd>
                      </dl>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <%!-- Submissions Table --%>
            <div class="bg-white shadow rounded-lg overflow-hidden">
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-gray-200">
                  <thead class="bg-gray-50">
                    <tr>
                      <th
                        scope="col"
                        class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                      >
                        Student
                      </th>

                      <th
                        scope="col"
                        class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                      >
                        Status
                      </th>

                      <th
                        scope="col"
                        class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                      >
                        Completed At
                      </th>

                      <th
                        scope="col"
                        class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                      >
                        Score
                      </th>

                      <th
                        scope="col"
                        class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                      >
                        Graded At
                      </th>

                      <th scope="col" class="relative px-6 py-3">
                        <span class="sr-only">Actions</span>
                      </th>
                    </tr>
                  </thead>

                  <tbody class="bg-white divide-y divide-gray-200">
                    <tr :for={submission <- @submissions} class="hover:bg-gray-50">
                      <td class="px-6 py-4 whitespace-nowrap">
                        <div class="flex items-center">
                          <div class="flex-shrink-0 h-10 w-10">
                            <div class="h-10 w-10 rounded-full bg-blue-100 flex items-center justify-center">
                              <span class="text-blue-600 font-medium text-sm">
                                {get_initials(submission.student.email)}
                              </span>
                            </div>
                          </div>

                          <div class="ml-4">
                            <div class="text-sm font-medium text-gray-900">
                              {submission.student.email}
                            </div>
                          </div>
                        </div>
                      </td>

                      <td class="px-6 py-4 whitespace-nowrap">
                        <span class={[
                          "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                          submission.status == "not_started" && "bg-gray-100 text-gray-800",
                          submission.status == "in_progress" && "bg-yellow-100 text-yellow-800",
                          submission.status == "completed" && "bg-green-100 text-green-800"
                        ]}>
                          {format_status(submission.status)}
                        </span>
                      </td>

                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <%= if submission.completed_at do %>
                          {format_datetime(submission.completed_at)}
                        <% else %>
                          <span class="text-gray-400">—</span>
                        <% end %>
                      </td>

                      <td class="px-6 py-4 whitespace-nowrap">
                        <%= if submission.points do %>
                          <div class="flex items-center gap-2">
                            <span class="text-sm font-semibold text-green-600">
                              {submission.points}
                            </span>
                            <span class="text-xs text-gray-400">/100</span>
                          </div>
                        <% else %>
                          <span class="text-gray-400 text-sm">—</span>
                        <% end %>
                      </td>

                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <%= if submission.graded_at do %>
                          <div class="flex flex-col">
                            <span>{format_datetime(submission.graded_at)}</span>
                            <%= if submission.graded_by do %>
                              <span class="text-xs text-gray-400">
                                by {submission.graded_by.email}
                              </span>
                            <% end %>
                          </div>
                        <% else %>
                          <span class="text-gray-400">—</span>
                        <% end %>
                      </td>

                      <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                        <%= if submission.status == "completed" do %>
                          <.link
                            navigate={~p"/tasks/#{@task.id}/grade/#{submission.id}"}
                            class="text-blue-600 hover:text-blue-900 inline-flex items-center gap-1"
                          >
                            <%= if submission.graded_at do %>
                              <.icon name="hero-pencil" class="w-4 h-4" /> Edit Grade
                            <% else %>
                              <.icon name="hero-academic-cap" class="w-4 h-4" /> Grade
                            <% end %>
                          </.link>
                        <% else %>
                          <span class="text-gray-400 text-sm">Not ready</span>
                        <% end %>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Assign Students Modal --%>
      <.modal :if={@show_assign_modal} id="assign-modal" show on_cancel={JS.push("hide_assign_modal")}>
        <div class="space-y-4">
          <h3 class="text-lg font-semibold">Assign Task to Students</h3>

          <%= if @unassigned_students == [] do %>
            <p class="text-sm text-gray-600">
              All students have already been assigned this task.
            </p>
          <% else %>
            <div class="space-y-2">
              <p class="text-sm text-gray-600">
                Select students to assign this task to:
              </p>

              <div class="flex gap-2 mb-4">
                <.button phx-click="assign_all_students" class="btn-sm">
                  <.icon name="hero-users" class="w-4 h-4" />
                  Assign All ({length(@unassigned_students)})
                </.button>
              </div>

              <div class="max-h-96 overflow-y-auto space-y-2">
                <label
                  :for={student <- @unassigned_students}
                  class="flex items-center gap-3 p-3 border rounded-lg hover:bg-gray-50 cursor-pointer"
                >
                  <input
                    type="checkbox"
                    name="student_ids[]"
                    value={student.id}
                    phx-click="toggle_student"
                    phx-value-student-id={student.id}
                    checked={student.id in @selected_student_ids}
                    class="checkbox checkbox-primary"
                  />
                  <div class="flex-1">
                    <div class="text-sm font-medium">{student.email}</div>
                    <div class="text-xs text-gray-500">Student</div>
                  </div>
                </label>
              </div>

              <div class="flex gap-2 pt-4 border-t">
                <.button
                  phx-click="assign_selected_students"
                  disabled={@selected_student_ids == []}
                  variant="primary"
                  class="flex-1"
                >
                  Assign Selected ({length(@selected_student_ids)})
                </.button>
                <.button phx-click="hide_assign_modal" class="flex-1">
                  Cancel
                </.button>
              </div>
            </div>
          <% end %>
        </div>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => task_id}, _session, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, task_id)
    submissions = Tasks.list_task_submissions(socket.assigns.current_scope, task_id)

    stats = %{
      total: length(submissions),
      completed: Enum.count(submissions, &(&1.status == "completed")),
      graded: Enum.count(submissions, &(&1.graded_at != nil)),
      pending: Enum.count(submissions, &(&1.status == "completed" and is_nil(&1.graded_at)))
    }

    {:ok,
     socket
     |> assign(:page_title, "Submissions for #{task.name}")
     |> assign(:task, task)
     |> assign(:submissions, submissions)
     |> assign(:stats, stats)
     |> assign(:show_assign_modal, false)
     |> assign(:unassigned_students, [])
     |> assign(:selected_student_ids, [])}
  end

  @impl true
  def handle_event("show_assign_modal", _params, socket) do
    unassigned_students =
      Tasks.list_unassigned_students(socket.assigns.current_scope, socket.assigns.task.id)

    {:noreply,
     socket
     |> assign(:show_assign_modal, true)
     |> assign(:unassigned_students, unassigned_students)
     |> assign(:selected_student_ids, [])}
  end

  def handle_event("hide_assign_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_assign_modal, false)
     |> assign(:selected_student_ids, [])}
  end

  def handle_event("toggle_student", %{"student-id" => student_id}, socket) do
    student_id = String.to_integer(student_id)
    selected_ids = socket.assigns.selected_student_ids

    new_selected_ids =
      if student_id in selected_ids do
        List.delete(selected_ids, student_id)
      else
        [student_id | selected_ids]
      end

    {:noreply, assign(socket, :selected_student_ids, new_selected_ids)}
  end

  def handle_event("assign_selected_students", _params, socket) do
    case Tasks.assign_task_to_students(
           socket.assigns.current_scope,
           socket.assigns.task.id,
           socket.assigns.selected_student_ids
         ) do
      {:ok, count} ->
        # Refresh submissions and stats
        submissions =
          Tasks.list_task_submissions(socket.assigns.current_scope, socket.assigns.task.id)

        stats = %{
          total: length(submissions),
          completed: Enum.count(submissions, &(&1.status == "completed")),
          graded: Enum.count(submissions, &(&1.graded_at != nil)),
          pending: Enum.count(submissions, &(&1.status == "completed" and is_nil(&1.graded_at)))
        }

        {:noreply,
         socket
         |> put_flash(:info, "Task assigned to #{count} student(s)")
         |> assign(:submissions, submissions)
         |> assign(:stats, stats)
         |> assign(:show_assign_modal, false)
         |> assign(:selected_student_ids, [])}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to assign task to students")}
    end
  end

  def handle_event("assign_all_students", _params, socket) do
    case Tasks.assign_task_to_all_students(socket.assigns.current_scope, socket.assigns.task.id) do
      {:ok, count} ->
        # Refresh submissions and stats
        submissions =
          Tasks.list_task_submissions(socket.assigns.current_scope, socket.assigns.task.id)

        stats = %{
          total: length(submissions),
          completed: Enum.count(submissions, &(&1.status == "completed")),
          graded: Enum.count(submissions, &(&1.graded_at != nil)),
          pending: Enum.count(submissions, &(&1.status == "completed" and is_nil(&1.graded_at)))
        }

        {:noreply,
         socket
         |> put_flash(:info, "Task assigned to all #{count} student(s)")
         |> assign(:submissions, submissions)
         |> assign(:stats, stats)
         |> assign(:show_assign_modal, false)
         |> assign(:selected_student_ids, [])}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to assign task to students")}
    end
  end

  defp format_status(status) do
    status
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %I:%M %p")
  end

  defp get_initials(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.slice(0..1)
    |> String.upcase()
  end
end
