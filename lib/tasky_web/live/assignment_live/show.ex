defmodule TaskyWeb.AssignmentLive.Show do
  use TaskyWeb, :live_view

  alias Tasky.Assignments

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Assignment {@assignment.id}
        <:subtitle>This is a assignment record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/assignments"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/assignments/#{@assignment}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit assignment
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@assignment.name}</:item>
        <:item title="Link">{@assignment.link}</:item>
        <:item title="Status">{@assignment.status}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Assignment")
     |> assign(:assignment, Assignments.get_assignment!(id))}
  end
end
