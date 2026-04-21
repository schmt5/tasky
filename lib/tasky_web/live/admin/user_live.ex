defmodule TaskyWeb.Admin.UserLive do
  use TaskyWeb, :live_view

  alias Tasky.Accounts
  alias Tasky.Classes
  import TaskyWeb.RoleHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-header">
        <div class="page-header-eyebrow">Administration</div>
        <h1>
          User <em>Management</em>
        </h1>
        <p>Manage users across the platform.</p>
      </div>

      <div class="max-w-5xl mx-auto mt-8">
        <form phx-change="filter" class="flex flex-wrap items-end gap-4 mb-6">
          <div class="flex flex-col">
            <label for="role-filter" class="text-xs font-semibold text-stone-500 mb-1">
              Rolle
            </label>
            <select
              id="role-filter"
              name="role"
              class="text-sm px-3 py-2 bg-white border border-stone-200 rounded-lg focus:outline-none focus:border-sky-500 focus:ring-1 focus:ring-sky-500"
            >
              <option value="">Alle Rollen</option>
              <option
                :for={{label, value} <- role_options()}
                value={value}
                selected={value == @role_filter}
              >
                {label}
              </option>
            </select>
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
              <option value="none" selected={@class_filter == "none"}>Keine Klasse</option>
              <option
                :for={class <- @classes}
                value={Integer.to_string(class.id)}
                selected={@class_filter == Integer.to_string(class.id)}
              >
                {class.name}
              </option>
            </select>
          </div>

          <div class="ml-auto text-sm text-stone-500">
            {length(@users)} Benutzer
          </div>
        </form>
      </div>

      <div class="max-w-5xl mx-auto bg-white border border-stone-200 rounded-[14px] overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
        <.table id="users" rows={@users}>
          <:col :let={user} label="Vorname">{user.firstname}</:col>
          <:col :let={user} label="Nachname">{user.lastname}</:col>
          <:col :let={user} label="E-Mail">{user.email}</:col>
          <:col :let={user} label="Rolle">
            <span class={[
              "inline-flex items-center text-[11px] font-semibold px-2 py-0.5 rounded-full whitespace-nowrap",
              user.role == "admin" && "bg-red-100 text-red-800",
              user.role == "teacher" && "bg-sky-100 text-sky-700",
              user.role == "student" && "bg-green-100 text-green-700"
            ]}>
              {role_name(user.role)}
            </span>
          </:col>
          <:col :let={user} label="Klasse">
            <%= if user.class do %>
              {user.class.name}
            <% else %>
              <span class="text-stone-400">—</span>
            <% end %>
          </:col>
          <:col :let={user} label="Status">
            <%= if user.confirmed_at do %>
              <span class="inline-flex items-center gap-0.5 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-green-100 text-green-700 whitespace-nowrap">
                <.icon name="hero-check-circle" class="w-3 h-3" /> Bestätigt
              </span>
            <% else %>
              <span class="inline-flex items-center text-[11px] font-semibold px-2 py-0.5 rounded-full bg-stone-100 text-stone-500 whitespace-nowrap">
                Unbestätigt
              </span>
            <% end %>
          </:col>
          <:action :let={user}>
            <.link
              navigate={~p"/admin/users/#{user.id}/edit"}
              class="inline-flex items-center gap-1.5 text-sm font-medium text-sky-600 hover:text-sky-700"
            >
              <.icon name="hero-pencil-square" class="w-4 h-4" /> Bearbeiten
            </.link>
          </:action>
        </.table>

        <%= if @users == [] do %>
          <div class="flex flex-col items-center text-center py-14 px-8">
            <div class="w-12 h-12 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-4">
              <.icon name="hero-user-group" class="w-6 h-6" />
            </div>
            <h3 class="text-[15px] font-semibold text-stone-700 mb-1.5">
              Keine Benutzer gefunden
            </h3>
            <p class="text-[13px] text-stone-400 max-w-[280px] leading-relaxed">
              Für die aktuellen Filter gibt es keine passenden Benutzer.
            </p>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "User Management")
     |> assign(:classes, Classes.list_classes())
     |> assign(:role_filter, "")
     |> assign(:class_filter, "")
     |> load_users()}
  end

  @impl true
  def handle_event("filter", %{"role" => role, "class_id" => class_id}, socket) do
    {:noreply,
     socket
     |> assign(:role_filter, role)
     |> assign(:class_filter, class_id)
     |> load_users()}
  end

  defp load_users(socket) do
    filters =
      []
      |> put_role_filter(socket.assigns.role_filter)
      |> put_class_filter(socket.assigns.class_filter)

    assign(socket, :users, Accounts.list_users(filters))
  end

  defp put_role_filter(filters, ""), do: filters
  defp put_role_filter(filters, role), do: [{:role, role} | filters]

  defp put_class_filter(filters, ""), do: filters
  defp put_class_filter(filters, "none"), do: [{:class_id, :none} | filters]

  defp put_class_filter(filters, class_id) do
    [{:class_id, String.to_integer(class_id)} | filters]
  end
end
