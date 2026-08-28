defmodule TaskyWeb.StudentsLive.Index do
  @moduledoc """
  The teacher-facing directory of learners.

  Mirrors `TaskyWeb.Admin.UserLive`, minus the role filter: every row here is a
  student. The organization boundary lives in `Tasky.Accounts.list_students/2`,
  not in this view — a teacher sees the students of their own organization, an
  admin sees all of them.
  """

  use TaskyWeb, :live_view

  alias Tasky.Accounts
  alias Tasky.Classes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-header">
        <div class="max-w-5xl mx-auto">
          <div class="page-header-eyebrow">Lernende</div>
          <h1>
            Lernende <em>verwalten</em>
          </h1>
          <p>
            Alle Lernenden deiner Organisation — über ihre Klasse zugeordnet.
          </p>
        </div>
      </div>

      <div class="max-w-5xl mx-auto mt-10 bg-white border border-stone-200 rounded-[14px] overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
        <div class="px-6 py-5 border-b border-stone-100">
          <form phx-change="filter" phx-submit="filter" class="flex flex-wrap items-end gap-4">
            <div class="flex flex-col flex-1 min-w-[220px]">
              <label for="search" class="text-xs font-semibold text-stone-500 mb-1">
                Suche
              </label>
              <div class="relative">
                <.icon
                  name="hero-magnifying-glass"
                  class="w-4 h-4 text-stone-400 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
                />
                <input
                  type="search"
                  id="search"
                  name="search"
                  value={@search}
                  placeholder="Name oder E-Mail"
                  phx-debounce="250"
                  class="w-full text-sm pl-9 pr-3 py-2 bg-white border border-stone-200 rounded-lg focus:outline-none focus:border-sky-500 focus:ring-1 focus:ring-sky-500"
                />
              </div>
            </div>

            <div class="flex flex-col">
              <label for="class-filter" class="text-xs font-semibold text-stone-500 mb-1">
                Klasse
              </label>
              <select
                id="class-filter"
                name="class_id"
                class="text-sm px-3 py-2 bg-white border border-stone-200 rounded-lg focus:outline-none focus:border-sky-500 focus:ring-1 focus:ring-sky-500"
              >
                <option value="">Alle Klassen</option>
                <option
                  :for={class <- @classes}
                  value={Integer.to_string(class.id)}
                  selected={@class_filter == Integer.to_string(class.id)}
                >
                  {class.name}
                </option>
              </select>
            </div>
          </form>
        </div>

        <%= if @students == [] do %>
          <div class="flex flex-col items-center text-center py-14 px-8">
            <div class="w-12 h-12 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-4">
              <.icon name="hero-user-group" class="w-6 h-6" />
            </div>
            <h3 class="text-[15px] font-semibold text-stone-700 mb-1.5">
              Keine Lernenden gefunden
            </h3>
            <p class="text-[13px] text-stone-400 max-w-[320px] leading-relaxed">
              <%= cond do %>
                <% filters_active?(@search, @class_filter) -> %>
                  Für die aktuellen Filter gibt es keine passenden Lernenden.
                <% @classes == [] -> %>
                  Deine Organisation hat noch keine Klasse. Lernende werden über den Registrierungslink einer Klasse zugeordnet.
                <% true -> %>
                  Noch keine Lernenden registriert. Teile den Registrierungslink einer Klasse, damit sie sich anmelden können.
              <% end %>
            </p>
          </div>
        <% else %>
          <.table
            id="students"
            rows={@students}
            row_click={fn student -> JS.navigate(~p"/students/#{student.id}/edit") end}
          >
            <:col :let={student} label="Vorname">{student.firstname}</:col>
            <:col :let={student} label="Nachname">{student.lastname}</:col>
            <:col :let={student} label="E-Mail">{student.email}</:col>
            <:col :let={student} label="Klasse">
              <%= if student.class do %>
                {student.class.name}
              <% else %>
                <span class="text-stone-400">—</span>
              <% end %>
            </:col>
            <:col :let={student} label="Status">
              <%= if student.confirmed_at do %>
                <span class="inline-flex items-center gap-0.5 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-green-100 text-green-700 whitespace-nowrap">
                  <.icon name="hero-check-circle" class="w-3 h-3" /> Bestätigt
                </span>
              <% else %>
                <span class="inline-flex items-center text-[11px] font-semibold px-2 py-0.5 rounded-full bg-stone-100 text-stone-500 whitespace-nowrap">
                  Unbestätigt
                </span>
              <% end %>
            </:col>
            <:action :let={student}>
              <.link
                navigate={~p"/students/#{student.id}/edit"}
                class="inline-flex items-center gap-1.5 text-sm font-medium text-sky-600 hover:text-sky-700"
              >
                <.icon name="hero-pencil-square" class="w-4 h-4" /> Bearbeiten
              </.link>
            </:action>
          </.table>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Lernende verwalten")
     |> assign(:classes, Classes.list_classes(socket.assigns.current_scope))
     |> assign(:search, "")
     |> assign(:class_filter, "")
     |> load_students()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:search, Map.get(params, "search", socket.assigns.search))
     |> assign(:class_filter, Map.get(params, "class_id", socket.assigns.class_filter))
     |> load_students()}
  end

  defp load_students(socket) do
    filters =
      []
      |> put_search_filter(socket.assigns.search)
      |> put_class_filter(socket.assigns.class_filter)

    assign(socket, :students, Accounts.list_students(socket.assigns.current_scope, filters))
  end

  defp put_search_filter(filters, ""), do: filters
  defp put_search_filter(filters, term), do: [{:search, term} | filters]

  defp put_class_filter(filters, ""), do: filters

  defp put_class_filter(filters, class_id) do
    case TaskyWeb.Params.int(class_id) do
      nil -> filters
      id -> [{:class_id, id} | filters]
    end
  end

  defp filters_active?(search, class), do: String.trim(search) != "" or class != ""
end
