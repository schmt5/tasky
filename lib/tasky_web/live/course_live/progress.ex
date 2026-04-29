defmodule TaskyWeb.CourseLive.Progress do
  use TaskyWeb, :live_view

  alias Tasky.Courses

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/courses/#{@course}/progress"}
    >
      <%!-- Page Header --%>
      <div class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-7xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Kurse", navigate: ~p"/courses"},
              %{label: @course.name, navigate: ~p"/courses/#{@course}"},
              %{label: "Fortschritt"}
            ]} />
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            {@course.name}
          </h1>

          <p class="text-[15px] text-stone-500 leading-[1.7]">
            Übersicht über den Fortschritt aller Lernenden
          </p>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-8 pb-8">
        <%!-- Progress Grid --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <%= if @has_data do %>
            <div class="overflow-x-auto">
              <div class="inline-block min-w-full align-middle">
                <table class="min-w-full divide-y divide-stone-200">
                  <thead class="bg-stone-50">
                    <tr>
                      <th
                        scope="col"
                        class="sticky left-0 z-10 bg-stone-50 px-6 py-4 text-left text-xs font-semibold text-stone-700 uppercase tracking-wider border-r border-stone-200"
                      >
                        <button
                          type="button"
                          phx-click="toggle_anonymize"
                          class="inline-flex items-center gap-2 px-2 py-1 rounded-lg hover:bg-stone-200 transition-colors"
                          title={
                            if @anonymized,
                              do: "Namen anzeigen",
                              else: "Namen ausblenden"
                          }
                        >
                          <.icon
                            name={if @anonymized, do: "hero-eye-slash", else: "hero-eye"}
                            class="w-4 h-4 text-stone-600"
                          />
                          <span class="text-xs font-semibold text-stone-700 uppercase tracking-wider">
                            Lernende
                          </span>
                        </button>
                      </th>

                      <th
                        :for={task <- @tasks}
                        scope="col"
                        class="px-3 py-4 text-center text-xs font-semibold text-stone-700 uppercase tracking-wider min-w-[100px] max-w-[140px]"
                      >
                        <.link
                          navigate={~p"/progress/#{task.id}"}
                          title={task.name}
                          class="block hover:text-sky-700 transition-colors"
                        >
                          <span class="line-clamp-2 text-[12px] font-medium text-stone-800 hover:text-sky-700 normal-case">
                            {task.name}
                          </span>
                        </.link>
                      </th>
                    </tr>
                  </thead>

                  <tbody class="bg-white divide-y divide-stone-100">
                    <tr
                      :for={{student, index} <- Enum.with_index(@students)}
                      class="hover:bg-stone-50 transition-colors duration-150"
                    >
                      <td class="sticky left-0 z-10 bg-white px-6 py-4 whitespace-nowrap border-r border-stone-200">
                        <div class="flex items-center gap-3">
                          <div class="w-8 h-8 rounded-full flex items-center justify-center shrink-0 bg-sky-100 text-sky-700 text-[11px] font-semibold">
                            {if @anonymized, do: "?", else: get_initials(student)}
                          </div>
                          <span class="text-[14px] font-medium text-stone-800">
                            {if @anonymized,
                              do: "Lernende #{index + 1}",
                              else: get_full_name(student)}
                          </span>
                        </div>
                      </td>

                      <td :for={task <- @tasks} class="px-4 py-4">
                        <div class="flex justify-center">
                          <%= case get_submission_status(@progress_map, student.id, task.id) do %>
                            <% :completed -> %>
                              <div
                                class="w-10 h-10 rounded-[8px] bg-emerald-500 flex items-center justify-center shadow-sm"
                                title="Abgeschlossen"
                              >
                                <.icon name="hero-check" class="w-5 h-5 text-white" />
                              </div>
                            <% :in_progress -> %>
                              <div
                                class="w-10 h-10 rounded-[8px] bg-sky-500 flex items-center justify-center shadow-sm"
                                title="In Bearbeitung"
                              >
                                <.icon name="hero-ellipsis-horizontal" class="w-5 h-5 text-white" />
                              </div>
                            <% :not_started -> %>
                              <div
                                class="w-10 h-10 rounded-[8px] bg-stone-200 flex items-center justify-center"
                                title="Nicht begonnen"
                              >
                                <.icon name="hero-minus" class="w-5 h-5 text-stone-400" />
                              </div>
                          <% end %>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
            <%!-- Legend --%>
            <div class="border-t border-stone-200 bg-stone-50 px-6 py-4">
              <div class="flex items-center justify-center gap-8">
                <div class="flex items-center gap-2">
                  <div class="w-6 h-6 rounded-[6px] bg-emerald-500 flex items-center justify-center">
                    <.icon name="hero-check" class="w-4 h-4 text-white" />
                  </div>
                  <span class="text-[13px] text-stone-600">Abgeschlossen</span>
                </div>

                <div class="flex items-center gap-2">
                  <div class="w-6 h-6 rounded-[6px] bg-sky-500 flex items-center justify-center">
                    <.icon name="hero-ellipsis-horizontal" class="w-4 h-4 text-white" />
                  </div>
                  <span class="text-[13px] text-stone-600">In Bearbeitung</span>
                </div>

                <div class="flex items-center gap-2">
                  <div class="w-6 h-6 rounded-[6px] bg-stone-200 flex items-center justify-center">
                    <.icon name="hero-minus" class="w-4 h-4 text-stone-400" />
                  </div>
                  <span class="text-[13px] text-stone-600">Nicht begonnen</span>
                </div>
              </div>
            </div>
          <% else %>
            <div class="flex flex-col items-center text-center px-8 py-16">
              <div class="w-14 h-14 rounded-[14px] bg-emerald-50 flex items-center justify-center text-emerald-400 mb-5">
                <.icon name="hero-chart-bar" class="w-6 h-6" />
              </div>

              <h3 class="text-base font-semibold text-stone-700 mb-2">Keine Daten verfügbar</h3>

              <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6]">
                Fügen Sie Lerneinheiten hinzu und schreiben Sie Lernende ein, um den Fortschritt zu verfolgen.
              </p>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    course = Courses.get_course!(socket.assigns.current_scope, id)

    # Subscribe to real-time progress updates for this course
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tasky.PubSub, "course:#{course.id}:progress")
    end

    students = Courses.list_enrolled_students(course.id)
    tasks = Enum.sort_by(course.tasks, & &1.position)

    progress_map = build_progress_map(course.id, students, tasks)

    has_data = length(students) > 0 && length(tasks) > 0

    {:ok,
     socket
     |> assign(:page_title, "Fortschritt - #{course.name}")
     |> assign(:course, course)
     |> assign(:students, students)
     |> assign(:tasks, tasks)
     |> assign(:progress_map, progress_map)
     |> assign(:has_data, has_data)
     |> assign(:anonymized, false)}
  end

  @impl true
  def handle_event("toggle_anonymize", _params, socket) do
    {:noreply, assign(socket, :anonymized, !socket.assigns.anonymized)}
  end

  @impl true
  def handle_info({:submission_updated, _updated_submission}, socket) do
    # Rebuild the progress map with fresh data
    progress_map =
      build_progress_map(socket.assigns.course.id, socket.assigns.students, socket.assigns.tasks)

    {:noreply, assign(socket, :progress_map, progress_map)}
  end

  # Private Functions

  defp build_progress_map(course_id, students, tasks) do
    student_ids = Enum.map(students, & &1.id)
    task_ids = Enum.map(tasks, & &1.id)
    Courses.get_progress_map_for_course(course_id, student_ids, task_ids)
  end

  defp get_submission_status(progress_map, student_id, task_id) do
    case Map.get(progress_map, {student_id, task_id}) do
      "completed" -> :completed
      "in_progress" -> :in_progress
      "open" -> :in_progress
      nil -> :not_started
      _ -> :not_started
    end
  end

  defp get_initials(student) do
    first_initial =
      case student.firstname do
        nil -> "?"
        "" -> "?"
        name -> name |> String.first() |> String.upcase()
      end

    last_initial =
      case student.lastname do
        nil -> "?"
        "" -> "?"
        name -> name |> String.first() |> String.upcase()
      end

    "#{first_initial}#{last_initial}"
  end

  defp get_full_name(student) do
    first = student.firstname || ""
    last = student.lastname || ""

    case String.trim("#{first} #{last}") do
      "" -> student.email || ""
      name -> name
    end
  end
end
