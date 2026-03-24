defmodule TaskyWeb.CourseLive.Reorder do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/courses/#{@course}/reorder"}
    >
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Kurse", navigate: ~p"/courses"},
              %{label: @course.name, navigate: ~p"/courses/#{@course}"},
              %{label: "Sortieren"}
            ]} />
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Lerneinheiten sortieren
          </h1>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Ziehen Sie die Lerneinheiten, um ihre Reihenfolge zu ändern
          </p>
        </div>
      </div>

      <div class="max-w-4xl mx-auto px-8 pb-8">
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6 border-b border-stone-100">
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 rounded-[10px] flex items-center justify-center shrink-0 bg-sky-100 text-sky-600">
                <.icon name="hero-arrows-up-down" class="w-5 h-5" />
              </div>

              <div>
                <h2 class="text-lg font-semibold text-stone-800">
                  Lerneinheiten für "{@course.name}"
                </h2>

                <p class="text-sm text-stone-500 mt-0.5">{length(@tasks)} Lerneinheiten insgesamt</p>
              </div>
            </div>
          </div>

          <ul
            id="sortable-tasks"
            phx-hook=".SortableTasks"
            class="list-none p-0 m-0 min-h-[200px]"
          >
            <li
              :for={task <- @tasks}
              id={"task-#{task.id}"}
              data-id={task.id}
              class="flex items-center gap-4 px-6 py-4 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 cursor-grab hover:bg-stone-50 active:cursor-grabbing"
            >
              <div class="w-8 h-8 rounded-[8px] flex items-center justify-center shrink-0 bg-stone-100 text-stone-400">
                <.icon name="hero-bars-3" class="w-5 h-5" />
              </div>

              <div class="flex-1 min-w-0">
                <h3 class="text-[15px] font-semibold text-stone-800 truncate">{task.name}</h3>
              </div>

              <div class="flex items-center gap-2 shrink-0">
                <span class={[
                  "inline-flex items-center text-[11px] font-semibold px-2.5 py-0.5 rounded-full whitespace-nowrap tracking-[0.01em]",
                  task.status == "draft" && "bg-stone-100 text-stone-700",
                  task.status == "published" && "bg-sky-100 text-sky-700",
                  task.status == "archived" && "bg-red-100 text-red-700"
                ]}>
                  {String.capitalize(task.status)}
                </span>
              </div>
            </li>
          </ul>

          <div :if={Enum.empty?(@tasks)} class="flex flex-col items-center text-center px-8 py-16">
            <div class="w-14 h-14 rounded-[14px] bg-stone-50 flex items-center justify-center text-stone-400 mb-5">
              <.icon name="hero-clipboard-document-list" class="w-6 h-6" />
            </div>

            <h3 class="text-base font-semibold text-stone-700 mb-2">Keine Lerneinheiten</h3>

            <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6] mb-6">
              Fügen Sie Lerneinheiten zum Kurs hinzu, um sie zu sortieren.
            </p>

            <.back_link navigate={~p"/courses/#{@course}"} label="Zurück zum Kurs" />
          </div>
        </div>
      </div>
      <%!-- Sortable.js Hook --%>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".SortableTasks">
        export default {
          mounted() {
            Sortable.create(this.el, {
              animation: 150,
              ghostClass: 'sortable-ghost',
              onEnd: (evt) => {
                const items = Array.from(this.el.children).map((item, index) => ({
                  id: parseInt(item.dataset.id),
                  position: index
                }));

                this.pushEvent("reorder", { items: items });
              }
            });
          }
        }
      </script>

      <style>
        .sortable-ghost {
          opacity: 0.4;
          background: #f3f4f6;
        }
      </style>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    course = Courses.get_course!(socket.assigns.current_scope, id)
    tasks = Tasks.list_tasks_by_course(course.id)

    {:ok,
     socket
     |> assign(:page_title, "Sortieren - #{course.name}")
     |> assign(:course, course)
     |> assign(:tasks, tasks)}
  end

  @impl true
  def handle_event("reorder", %{"items" => items}, socket) do
    task_positions =
      Enum.map(items, fn item ->
        %{
          id: item["id"],
          position: item["position"]
        }
      end)

    case Tasks.reorder_tasks(socket.assigns.current_scope, task_positions) do
      {:ok, _} ->
        {:noreply, assign(socket, :tasks, Tasks.list_tasks_by_course(socket.assigns.course.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Fehler beim Aktualisieren der Reihenfolge")}
    end
  end
end
