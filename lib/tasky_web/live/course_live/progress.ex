defmodule TaskyWeb.CourseLive.Progress do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Repo

  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-7xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-emerald-500">
              Kursfortschritt
            </div>
            <div class="flex items-center gap-2">
              <.link
                navigate={~p"/courses/#{@course}"}
                class="inline-flex items-center gap-1.5 text-[13px] font-semibold text-stone-600 hover:text-stone-900 transition-colors duration-150"
              >
                <.icon name="hero-arrow-left" class="w-4 h-4" /> Zurück zum Kurs
              </.link>
            </div>
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            {@course.name}
          </h1>

          <p class="text-[15px] text-stone-500 leading-[1.7]">
            Übersicht über den Fortschritt aller Studenten
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
                        Aufgabe
                      </th>
                      <th
                        :for={student <- @students}
                        scope="col"
                        class="px-4 py-4 text-center text-xs font-semibold text-stone-700 uppercase tracking-wider min-w-[120px]"
                      >
                        <div class="flex flex-col items-center gap-1">
                          <div class="w-8 h-8 rounded-full flex items-center justify-center shrink-0 bg-stone-100 text-stone-600 mx-auto mb-2">
                            <.icon name="hero-user-circle" class="w-5 h-5" />
                          </div>
                          <span class="line-clamp-2 text-[11px]">{student.email}</span>
                        </div>
                      </th>
                    </tr>
                  </thead>
                  <tbody class="bg-white divide-y divide-stone-100">
                    <tr
                      :for={task <- @tasks}
                      class="hover:bg-stone-50 transition-colors duration-150"
                    >
                      <td class="sticky left-0 z-10 bg-white group-hover:bg-stone-50 px-6 py-4 whitespace-nowrap border-r border-stone-200">
                        <div class="flex items-center gap-3">
                          <div class="w-8 h-8 rounded-[10px] flex items-center justify-center shrink-0 bg-sky-100 text-sky-600">
                            <.icon name="hero-clipboard-document-list" class="w-5 h-5" />
                          </div>
                          <span class="text-[14px] font-medium text-stone-800">
                            {task.name}
                          </span>
                        </div>
                      </td>
                      <td :for={student <- @students} class="px-4 py-4">
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
                Fügen Sie Lerneinheiten hinzu und schreiben Sie Studenten ein, um den Fortschritt zu verfolgen.
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
     |> assign(:has_data, has_data)}
  end

  # Private Functions

  defp build_progress_map(course_id, students, tasks) do
    student_ids = Enum.map(students, & &1.id)
    task_ids = Enum.map(tasks, & &1.id)

    submissions =
      Repo.all(
        from s in Tasky.Tasks.TaskSubmission,
          join: t in assoc(s, :task),
          where:
            s.student_id in ^student_ids and s.task_id in ^task_ids and t.course_id == ^course_id,
          select: %{student_id: s.student_id, task_id: s.task_id, status: s.status}
      )

    Enum.reduce(submissions, %{}, fn submission, acc ->
      key = {submission.student_id, submission.task_id}
      Map.put(acc, key, submission.status)
    end)
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
end
