defmodule TaskyWeb.CourseLive.Add do
  @moduledoc """
  Creates a new learning unit (task) for a course: a simple name form.
  The unit starts as a draft (invisible to students); content is authored
  afterwards in `TaskyWeb.TaskLive.Content`.
  """
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/courses/#{@course}/add"}
    >
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Kurse", navigate: ~p"/courses"},
              %{label: @course.name, navigate: ~p"/courses/#{@course}"},
              %{label: "Lerneinheit hinzufügen"}
            ]} />
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button navigate={~p"/courses/#{@course}"} tooltip={"Zurück zu #{@course.name}"} />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              Neue Lerneinheit
            </h1>
          </div>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Erstellen Sie eine neue Lerneinheit für
            <span class="font-medium text-stone-700">"{@course.name}"</span>
            und gestalten Sie anschliessend den Inhalt.
          </p>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8">
        <div class="max-w-xl bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-8">
          <.form
            for={@form}
            id="add-task-form"
            phx-submit="create_task"
            phx-change="validate"
            class="space-y-6"
          >
            <div>
              <.input
                field={@form[:name]}
                type="text"
                label="Name der Lerneinheit"
                placeholder="z. B. Kapitel 1 – Grundlagen"
                maxlength="255"
                autofocus
                phx-debounce="300"
                class="w-full text-sm text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-sky-300 focus:border-sky-400"
              />
              <p class="text-xs text-stone-400 mt-2 leading-relaxed">
                Die Lerneinheit wird als Entwurf erstellt und ist für Lernende erst sichtbar,
                wenn Sie sie veröffentlichen.
              </p>
            </div>

            <div class="pt-1 border-t border-stone-100">
              <div class="pt-5">
                <.checkbox_field
                  field={@form[:extended]}
                  accent="violet"
                  label="Erweiterte Lerneinheit"
                  description="Markiert die Lerneinheit für Lernende als freiwillige Erweiterung."
                />
              </div>
            </div>

            <div class="pt-1 border-t border-stone-100">
              <div class="pt-5">
                <.radio_group
                  field={@form[:solution_release_mode]}
                  legend="Musterlösung anzeigen"
                  options={TaskyWeb.TaskComponents.solution_release_options()}
                />
              </div>
            </div>

            <div class="flex items-center justify-end gap-3">
              <.link
                navigate={~p"/courses/#{@course}"}
                class="text-sm font-semibold text-stone-500 px-4 py-2.5 rounded-lg transition-colors duration-150 hover:text-stone-700 hover:bg-stone-50"
              >
                Abbrechen
              </.link>
              <button
                type="submit"
                phx-disable-with="Wird erstellt…"
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <.icon name="hero-plus" class="w-4 h-4" /> Erstellen und Inhalt gestalten
              </button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    course = Courses.get_course!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, "Lerneinheit hinzufügen")
     |> assign(:course, course)
     |> assign(:form, to_form(Tasks.change_new_task(socket.assigns.current_scope)))}
  end

  @impl true
  def handle_event("validate", %{"task" => params}, socket) do
    changeset =
      Tasks.change_new_task(
        socket.assigns.current_scope,
        task_attrs(socket.assigns.course, params)
      )

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("create_task", %{"task" => params}, socket) do
    scope = socket.assigns.current_scope
    attrs = task_attrs(socket.assigns.course, params)

    case Tasks.create_task(scope, attrs) do
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lerneinheit «#{task.name}» erstellt.")
         |> push_navigate(to: ~p"/tasks/#{task}/content")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
    end
  end

  # `position` and `status` are not part of the form but are required by the
  # changeset, so they ride along on every validate and on the final insert.
  # The position is (re)computed on each call so a unit created in a parallel
  # session can't hand us a stale one.
  defp task_attrs(course, params) do
    Map.merge(params, %{
      "name" => params |> Map.get("name", "") |> String.trim(),
      "position" => Tasks.next_task_position(course.id),
      "status" => "draft",
      "course_id" => course.id
    })
  end
end
