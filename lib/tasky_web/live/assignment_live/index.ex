defmodule TaskyWeb.AssignmentLive.Index do
  use TaskyWeb, :live_view

  alias Tasky.Assignments

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="bg-white border-b border-stone-100 px-8 py-12">
        <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-sky-500 mb-3">
          Assignment Management
        </div>
        <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
          Listing <em class="italic text-sky-500">Assignments</em>
        </h1>
        <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
          Manage all assignments and their associated tasks.
        </p>
      </div>

      <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
        <div class="flex items-center justify-between p-6 border-b border-stone-100">
          <div>
            <h2 class="text-lg font-semibold text-stone-800">All Assignments</h2>
            <p class="text-sm text-stone-500 mt-1">
              {@assignment_count} assignments total
            </p>
          </div>
          <.link
            navigate={~p"/assignments/new"}
            class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> New Assignment
          </.link>
        </div>

        <ul id="assignments" phx-update="stream" class="list-none p-0 m-0">
          <li
            :for={{id, assignment} <- @streams.assignments}
            id={id}
            class="flex items-start gap-5 px-6 py-5 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 hover:bg-stone-50"
          >
            <.link
              navigate={~p"/assignments/#{assignment}"}
              class="w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5 bg-sky-100 text-sky-600"
            >
              <.icon name="hero-clipboard-document-check" class="w-5 h-5" />
            </.link>

            <.link
              navigate={~p"/assignments/#{assignment}"}
              class="flex-1 min-w-0 flex flex-col gap-1.5"
            >
              <div class="flex items-center gap-2.5 flex-wrap">
                <h3 class="text-[15px] font-semibold text-stone-800 leading-[1.4]">
                  {assignment.name}
                </h3>
                <span class={[
                  "inline-flex items-center text-[11px] font-semibold px-2.5 py-0.5 rounded-full whitespace-nowrap tracking-[0.01em]",
                  assignment.status == "draft" && "bg-stone-100 text-stone-600",
                  assignment.status == "published" && "bg-sky-100 text-sky-700",
                  assignment.status == "archived" && "bg-red-100 text-red-700"
                ]}>
                  {String.capitalize(assignment.status)}
                </span>
              </div>

              <%= if assignment.link do %>
                <p class="text-sm text-stone-500 leading-[1.6] max-w-[600px]">
                  <.icon name="hero-link" class="w-3.5 h-3.5 inline" />
                  {assignment.link}
                </p>
              <% end %>
            </.link>

            <div class="flex items-center gap-2 shrink-0 pt-0.5">
              <.link
                navigate={~p"/assignments/#{assignment}/edit"}
                class="inline-flex items-center gap-2 bg-transparent text-stone-500 text-[13px] font-medium px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-sky-50 hover:text-sky-600"
              >
                <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit
              </.link>
              <button
                type="button"
                phx-click={JS.push("delete", value: %{id: assignment.id}) |> hide("##{id}")}
                data-confirm="Are you sure you want to delete this assignment?"
                class="inline-flex items-center gap-2 text-red-600 text-[13px] font-medium px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-red-100 hover:text-red-700"
              >
                <.icon name="hero-trash" class="w-4 h-4" />
              </button>
            </div>
          </li>
        </ul>

        <%= if @assignment_count == 0 do %>
          <div class="flex flex-col items-center text-center px-8 py-16 bg-white">
            <div class="w-14 h-14 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-5">
              <.icon name="hero-clipboard-document-check" class="w-6 h-6" />
            </div>
            <h3 class="text-base font-semibold text-stone-700 mb-2">No assignments yet</h3>
            <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6] mb-6">
              Get started by creating your first assignment.
            </p>
            <.link
              navigate={~p"/assignments/new"}
              class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
            >
              <.icon name="hero-plus" class="w-4 h-4" /> Create First Assignment
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    assignments = list_assignments()

    {:ok,
     socket
     |> assign(:page_title, "Listing Assignments")
     |> assign(:assignment_count, length(assignments))
     |> stream(:assignments, assignments)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    assignment = Assignments.get_assignment!(id)
    {:ok, _} = Assignments.delete_assignment(assignment)

    {:noreply,
     socket
     |> assign(:assignment_count, socket.assigns.assignment_count - 1)
     |> stream_delete(:assignments, assignment)}
  end

  defp list_assignments() do
    Assignments.list_assignments()
  end
end
