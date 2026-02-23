defmodule TaskyWeb.AssignmentLive.Index do
  use TaskyWeb, :live_view

  alias Tasky.Assignments

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Assignments
        <:actions>
          <.button variant="primary" navigate={~p"/assignments/new"}>
            <.icon name="hero-plus" /> New Assignment
          </.button>
        </:actions>
      </.header>

      <.table
        id="assignments"
        rows={@streams.assignments}
        row_click={fn {_id, assignment} -> JS.navigate(~p"/assignments/#{assignment}") end}
      >
        <:col :let={{_id, assignment}} label="Name">{assignment.name}</:col>
        <:col :let={{_id, assignment}} label="Link">{assignment.link}</:col>
        <:col :let={{_id, assignment}} label="Status">{assignment.status}</:col>
        <:action :let={{_id, assignment}}>
          <div class="sr-only">
            <.link navigate={~p"/assignments/#{assignment}"}>Show</.link>
          </div>
          <.link navigate={~p"/assignments/#{assignment}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, assignment}}>
          <.link
            phx-click={JS.push("delete", value: %{id: assignment.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Assignments")
     |> stream(:assignments, list_assignments())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    assignment = Assignments.get_assignment!(id)
    {:ok, _} = Assignments.delete_assignment(assignment)

    {:noreply, stream_delete(socket, :assignments, assignment)}
  end

  defp list_assignments() do
    Assignments.list_assignments()
  end
end
