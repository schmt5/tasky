defmodule TaskyWeb.CourseLive.Form do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Courses.Course

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-sky-500">
              Kursverwaltung
            </div>
            <.link
              navigate={return_path(@return_to, @course)}
              class="inline-flex items-center gap-1.5 text-[13px] font-semibold text-stone-600 hover:text-stone-900 transition-colors duration-150"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Zurück
            </.link>
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            {@page_title}
          </h1>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            {if @live_action == :new,
              do: "Erstelle einen neuen Kurs für deine Aufgaben und Studenten.",
              else: "Bearbeite die Kursinformationen."}
          </p>
        </div>
      </div>

      <%!-- Form Card --%>
      <div class="max-w-6xl mx-auto px-8 pb-8">
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6">
            <.form
              for={@form}
              id="course-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-6"
            >
              <.input field={@form[:name]} type="text" label="Kursname" required />
              <.input
                field={@form[:description]}
                type="textarea"
                label="Beschreibung"
                placeholder="Gib eine kurze Beschreibung des Kurses ein..."
                rows="4"
              />
              <div class="flex items-center gap-3 pt-4 border-t border-stone-100">
                <.button
                  phx-disable-with="Speichert..."
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  {if @live_action == :new, do: "Kurs erstellen", else: "Änderungen speichern"}
                </.button>
                <.link
                  navigate={return_path(@return_to, @course)}
                  class="inline-flex items-center gap-2 text-stone-500 text-sm font-medium px-5 py-2.5 rounded-[10px] transition-all duration-150 hover:bg-stone-100 hover:text-stone-700"
                >
                  Abbrechen
                </.link>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    course = Courses.get_course!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Kurs bearbeiten")
    |> assign(:course, course)
    |> assign(:form, to_form(Courses.change_course(course)))
  end

  defp apply_action(socket, :new, _params) do
    course = %Course{}

    socket
    |> assign(:page_title, "Neuer Kurs")
    |> assign(:course, course)
    |> assign(:form, to_form(Courses.change_course(course)))
  end

  @impl true
  def handle_event("validate", %{"course" => course_params}, socket) do
    changeset = Courses.change_course(socket.assigns.course, course_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"course" => course_params}, socket) do
    save_course(socket, socket.assigns.live_action, course_params)
  end

  defp save_course(socket, :edit, course_params) do
    case Courses.update_course(socket.assigns.course, course_params) do
      {:ok, course} ->
        {:noreply,
         socket
         |> push_navigate(to: return_path(socket.assigns.return_to, course))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_course(socket, :new, course_params) do
    case Courses.create_course(socket.assigns.current_scope, course_params) do
      {:ok, course} ->
        {:noreply,
         socket
         |> put_flash(:info, "Kurs erfolgreich erstellt")
         |> push_navigate(to: return_path(socket.assigns.return_to, course))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _course), do: ~p"/courses"
  defp return_path("show", course), do: ~p"/courses/#{course}"
end
