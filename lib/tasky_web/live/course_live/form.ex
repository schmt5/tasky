defmodule TaskyWeb.CourseLive.Form do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Courses.Course

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage course records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="course-form" phx-change="validate" phx-submit="save" class="max-w-2xl">
        <.input field={@form[:name]} type="text" label="Course Name" required />
        <.input
          field={@form[:description]}
          type="textarea"
          label="Description"
          placeholder="Enter a brief description of the course..."
          rows="4"
        />
        <footer class="flex gap-2">
          <.button phx-disable-with="Saving..." variant="primary">Save Course</.button>
          <.button type="button" navigate={return_path(@return_to, @course)}>Cancel</.button>
        </footer>
      </.form>
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
    |> assign(:page_title, "Edit Course")
    |> assign(:course, course)
    |> assign(:form, to_form(Courses.change_course(course)))
  end

  defp apply_action(socket, :new, _params) do
    course = %Course{}

    socket
    |> assign(:page_title, "New Course")
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
         |> put_flash(:info, "Course updated successfully")
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
         |> put_flash(:info, "Course created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, course))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _course), do: ~p"/courses"
  defp return_path("show", course), do: ~p"/courses/#{course}"
end
