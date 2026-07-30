defmodule TaskyWeb.CourseLive.Reorder do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Tasks
  alias TaskyWeb.Params

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

          <div class="flex items-center gap-3 mb-3">
            <.back_button
              navigate={~p"/courses/#{@course}"}
              tooltip={"Zurück zu #{@course.name}"}
            />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              Lerneinheiten sortieren
            </h1>
          </div>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Ziehen Sie die Lerneinheiten, um ihre Reihenfolge zu ändern — oder verschieben Sie sie
            mit den Pfeiltasten.
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

          <ul id="sortable-tasks" phx-hook=".DragSortTasks" class="list-none p-0 m-0 min-h-[200px]">
            <li
              :for={{task, index} <- Enum.with_index(@tasks)}
              id={"task-#{task.id}"}
              data-id={task.id}
              draggable="true"
              class="flex items-center gap-4 px-6 py-4 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 cursor-grab hover:bg-stone-50 active:cursor-grabbing"
            >
              <div class="w-8 h-8 rounded-[8px] flex items-center justify-center shrink-0 bg-stone-100 text-stone-400">
                <.icon name="hero-bars-3" class="w-5 h-5" />
              </div>

              <span class="text-[13px] font-semibold text-stone-400 tabular-nums w-6 shrink-0">
                {index + 1}.
              </span>

              <div class="flex-1 min-w-0">
                <h3 class="text-[15px] font-semibold text-stone-800 truncate">{task.name}</h3>
              </div>

              <div class="flex items-center gap-2 shrink-0">
                <.task_status_chip status={task.status} />

                <%!-- Not draggable, so a press on an arrow can't start a drag. --%>
                <div class="flex items-center gap-1" draggable="false">
                  <div class="tooltip tooltip-delayed tooltip-left" data-tip="Nach oben">
                    <button
                      type="button"
                      phx-click="move_up"
                      phx-value-id={task.id}
                      disabled={index == 0}
                      aria-label={"«#{task.name}» nach oben verschieben"}
                      class="inline-flex items-center justify-center w-8 h-8 rounded-[6px] text-stone-500 transition-all duration-150 hover:bg-stone-100 hover:text-stone-700 disabled:opacity-30 disabled:pointer-events-none"
                    >
                      <.icon name="hero-arrow-up" class="w-4 h-4" />
                    </button>
                  </div>

                  <div class="tooltip tooltip-delayed tooltip-left" data-tip="Nach unten">
                    <button
                      type="button"
                      phx-click="move_down"
                      phx-value-id={task.id}
                      disabled={index == length(@tasks) - 1}
                      aria-label={"«#{task.name}» nach unten verschieben"}
                      class="inline-flex items-center justify-center w-8 h-8 rounded-[6px] text-stone-500 transition-all duration-150 hover:bg-stone-100 hover:text-stone-700 disabled:opacity-30 disabled:pointer-events-none"
                    >
                      <.icon name="hero-arrow-down" class="w-4 h-4" />
                    </button>
                  </div>
                </div>
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
      <%!-- Drag & drop, native HTML5 — no third-party library. --%>
      <%!-- The hook never reorders the DOM: it only reports the intended move and --%>
      <%!-- lets the server re-render, so LiveView stays authoritative over the list. --%>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".DragSortTasks">
        export default {
          mounted() {
            this.dragId = null;

            this.el.addEventListener("dragstart", (e) => {
              const row = e.target.closest("li[data-id]");
              if (!row) return;

              this.dragId = row.dataset.id;
              this.dragRow = row;
              e.dataTransfer.effectAllowed = "move";
              // Firefox refuses to start a drag unless some data is set.
              e.dataTransfer.setData("text/plain", this.dragId);
              row.classList.add("drag-source");
            });

            this.el.addEventListener("dragover", (e) => {
              const row = this.dropTarget(e);
              if (!row) return;

              // Only preventDefault on a valid target, so the cursor still
              // shows "no drop" over the dragged row itself.
              e.preventDefault();
              e.dataTransfer.dropEffect = "move";
              this.clearIndicators();
              row.classList.add(this.place(e, row) === "after" ? "drop-after" : "drop-before");
            });

            this.el.addEventListener("drop", (e) => {
              const row = this.dropTarget(e);
              if (!row) return;

              e.preventDefault();
              this.pushEvent("move", {
                id: this.dragId,
                target_id: row.dataset.id,
                place: this.place(e, row)
              });
              this.reset();
            });

            this.el.addEventListener("dragend", () => this.reset());

            // Fires when the pointer leaves the list entirely.
            this.el.addEventListener("dragleave", (e) => {
              if (!this.el.contains(e.relatedTarget)) this.clearIndicators();
            });
          },

          destroyed() {
            this.reset();
          },

          // The row being hovered, unless it is the one being dragged.
          dropTarget(e) {
            const row = e.target.closest("li[data-id]");
            if (!row || !this.dragId || row.dataset.id === this.dragId) return null;
            return row;
          },

          // Which side of the row's vertical midpoint the cursor sits on.
          place(e, row) {
            const rect = row.getBoundingClientRect();
            return e.clientY > rect.top + rect.height / 2 ? "after" : "before";
          },

          clearIndicators() {
            this.el.querySelectorAll(".drop-before, .drop-after").forEach((row) => {
              row.classList.remove("drop-before", "drop-after");
            });
          },

          reset() {
            if (this.dragRow) this.dragRow.classList.remove("drag-source");
            this.dragRow = null;
            this.dragId = null;
            this.clearIndicators();
          }
        }
      </script>

      <style>
        #sortable-tasks .drag-source {
          opacity: 0.4;
          background: #f5f5f4;
        }

        #sortable-tasks .drop-before {
          box-shadow: inset 0 2px 0 0 #0ea5e9;
        }

        #sortable-tasks .drop-after {
          box-shadow: inset 0 -2px 0 0 #0ea5e9;
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
  def handle_event("move", %{"id" => id, "target_id" => target_id, "place" => place}, socket)
      when place in ["before", "after"] do
    ids = ids(socket)
    id = Params.int(id)
    target_id = Params.int(target_id)

    # Both ids must be known and distinct; anything else is stale or tampered.
    if id != target_id and id in ids and target_id in ids do
      remaining = List.delete(ids, id)
      target_index = Enum.find_index(remaining, &(&1 == target_id))
      offset = if place == "after", do: 1, else: 0

      remaining
      |> List.insert_at(target_index + offset, id)
      |> persist(socket)
    else
      {:noreply, socket}
    end
  end

  # Any other shape of "move" is stale or tampered input — ignore it rather
  # than crashing the LiveView on a FunctionClauseError.
  def handle_event("move", _params, socket), do: {:noreply, socket}

  def handle_event("move_up", %{"id" => id}, socket), do: shift(socket, id, -1)
  def handle_event("move_down", %{"id" => id}, socket), do: shift(socket, id, 1)

  # Moves a task one slot in `offset` direction; a no-op at the list boundaries.
  defp shift(socket, id, offset) do
    ids = ids(socket)
    index = Enum.find_index(ids, &(&1 == Params.int(id)))
    target = if index, do: index + offset

    if target && target >= 0 && target < length(ids) do
      ids
      |> List.delete_at(index)
      |> List.insert_at(target, Enum.at(ids, index))
      |> persist(socket)
    else
      {:noreply, socket}
    end
  end

  defp persist(ordered_ids, socket) do
    course = socket.assigns.course

    case Tasks.reorder_tasks(socket.assigns.current_scope, course.id, ordered_ids) do
      {:ok, _} ->
        {:noreply, assign(socket, :tasks, Tasks.list_tasks_by_course(course.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Fehler beim Aktualisieren der Reihenfolge")}
    end
  end

  defp ids(socket), do: Enum.map(socket.assigns.tasks, & &1.id)
end
