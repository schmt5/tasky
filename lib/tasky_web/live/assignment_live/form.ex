defmodule TaskyWeb.AssignmentLive.Form do
  use TaskyWeb, :live_view

  alias Tasky.Assignments
  alias Tasky.Assignments.Assignment

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage assignment records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="assignment-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:link]} type="text" label="Link" />
        <.input field={@form[:status]} type="text" label="Status" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Assignment</.button>
          <.button navigate={return_path(@return_to, @assignment)}>Cancel</.button>
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
    assignment = Assignments.get_assignment!(id)

    socket
    |> assign(:page_title, "Edit Assignment")
    |> assign(:assignment, assignment)
    |> assign(:form, to_form(Assignments.change_assignment(assignment)))
  end

  defp apply_action(socket, :new, _params) do
    assignment = %Assignment{}

    socket
    |> assign(:page_title, "New Assignment")
    |> assign(:assignment, assignment)
    |> assign(:form, to_form(Assignments.change_assignment(assignment)))
  end

  @impl true
  def handle_event("validate", %{"assignment" => assignment_params}, socket) do
    changeset = Assignments.change_assignment(socket.assigns.assignment, assignment_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"assignment" => assignment_params}, socket) do
    save_assignment(socket, socket.assigns.live_action, assignment_params)
  end

  defp save_assignment(socket, :edit, assignment_params) do
    case Assignments.update_assignment(socket.assigns.assignment, assignment_params) do
      {:ok, assignment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Assignment updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, assignment))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_assignment(socket, :new, assignment_params) do
    case Assignments.create_assignment(assignment_params) do
      {:ok, assignment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Assignment created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, assignment))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _assignment), do: ~p"/assignments"
  defp return_path("show", assignment), do: ~p"/assignments/#{assignment}"
end
