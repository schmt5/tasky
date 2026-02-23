defmodule TaskyWeb.Admin.UserLive do
  use TaskyWeb, :live_view

  alias Tasky.Accounts
  import TaskyWeb.RoleHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <.header>
          User Management
          <:subtitle>Manage user roles and permissions</:subtitle>
        </.header>

        <div class="mt-8 space-y-8">
          <div :for={{role_name, users} <- @users_by_role}>
            <div class="mb-4">
              <h3 class="text-lg font-semibold text-gray-900 capitalize">
                {role_name(role_name)}s ({length(users)})
              </h3>
            </div>

            <div class="overflow-hidden bg-white shadow sm:rounded-lg">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th
                      scope="col"
                      class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500"
                    >
                      Email
                    </th>

                    <th
                      scope="col"
                      class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500"
                    >
                      Role
                    </th>

                    <th
                      scope="col"
                      class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500"
                    >
                      Confirmed
                    </th>

                    <th
                      scope="col"
                      class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500"
                    >
                      Actions
                    </th>
                  </tr>
                </thead>

                <tbody class="divide-y divide-gray-200 bg-white">
                  <tr :for={user <- users} class="hover:bg-gray-50">
                    <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">
                      {user.email}
                    </td>

                    <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">
                      <span class={[
                        "inline-flex rounded-full px-2 py-1 text-xs font-semibold leading-5",
                        user.role == "admin" && "bg-purple-100 text-purple-800",
                        user.role == "teacher" && "bg-blue-100 text-blue-800",
                        user.role == "student" && "bg-green-100 text-green-800"
                      ]}>
                        {role_name(user.role)}
                      </span>
                    </td>

                    <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">
                      <%= if user.confirmed_at do %>
                        <span class="text-green-600">✓</span>
                      <% else %>
                        <span class="text-gray-400">—</span>
                      <% end %>
                    </td>

                    <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">
                      <%= if user.id != @current_scope.user.id do %>
                        <.form
                          for={%{}}
                          id={"role-form-#{user.id}"}
                          phx-submit="change_role"
                          phx-value-user-id={user.id}
                          class="flex items-center gap-2"
                        >
                          <select
                            name="role"
                            class="rounded-md border-gray-300 text-sm focus:border-brand focus:ring-brand"
                          >
                            <option
                              :for={{label, value} <- role_options()}
                              value={value}
                              selected={value == user.role}
                            >
                              {label}
                            </option>
                          </select>
                          <.button type="submit">Update</.button>
                        </.form>
                      <% else %>
                        <span class="text-xs text-gray-400">Current user</span>
                      <% end %>
                    </td>
                  </tr>
                </tbody>
              </table>

              <%= if users == [] do %>
                <div class="px-6 py-8 text-center text-sm text-gray-500">
                  No {role_name(role_name)}s found
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    users_by_role = Accounts.list_all_users_grouped_by_role()

    {:ok,
     socket
     |> assign(:users_by_role, users_by_role)
     |> assign(:page_title, "User Management")}
  end

  @impl true
  def handle_event("change_role", %{"user-id" => user_id, "role" => role}, socket) do
    user = Accounts.get_user!(user_id)

    case Accounts.update_user_role(user, %{role: role}) do
      {:ok, _updated_user} ->
        users_by_role = Accounts.list_all_users_grouped_by_role()

        {:noreply,
         socket
         |> put_flash(:info, "User role updated to #{role_name(role)} successfully")
         |> assign(:users_by_role, users_by_role)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update user role")}
    end
  end
end
