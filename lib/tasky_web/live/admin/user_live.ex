defmodule TaskyWeb.Admin.UserLive do
  use TaskyWeb, :live_view

  alias Tasky.Accounts
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
        <p>Manage user roles and permissions across the platform.</p>
      </div>

      <div :for={{role_name, users} <- @users_by_role} class="mb-6 last:mb-0">
        <div class="content-card">
          <div class="flex items-center justify-between p-6 border-b border-stone-100">
            <div>
              <h2 class="text-lg font-semibold text-stone-800 capitalize">
                {role_name(role_name)}s
              </h2>
              <p class="text-sm text-stone-500 mt-1">
                {length(users)} {if length(users) == 1, do: "user", else: "users"}
              </p>
            </div>
          </div>

          <ul class="ks-list">
            <li :for={user <- users} class="ks-item">
              <div class={[
                "ks-item-icon",
                user.role == "admin" && "ks-icon-red",
                user.role == "teacher" && "ks-icon-sky",
                user.role == "student" && "ks-icon-green"
              ]}>
                <.icon name="hero-user-circle" class="w-5 h-5" />
              </div>

              <div class="ks-item-main">
                <div class="ks-item-header">
                  <h3 class="ks-item-title">{user.email}</h3>
                  <span class={[
                    "ks-badge",
                    user.role == "admin" && "ks-badge-red",
                    user.role == "teacher" && "ks-badge-sky",
                    user.role == "student" && "ks-badge-green"
                  ]}>
                    {role_name(user.role)}
                  </span>
                  <%= if user.confirmed_at do %>
                    <span class="ks-badge ks-badge-green">
                      <.icon name="hero-check-circle" class="w-3 h-3" /> Confirmed
                    </span>
                  <% else %>
                    <span class="ks-badge ks-badge-stone">Unconfirmed</span>
                  <% end %>
                </div>

                <div class="ks-meta">
                  <%= if user.id == @current_scope.user.id do %>
                    <span class="ks-meta-item">
                      <.icon name="hero-user" class="w-3.5 h-3.5" /> Current user
                    </span>
                  <% end %>
                </div>
              </div>

              <div class="ks-item-actions">
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
                      class="text-sm px-3 py-2 border border-stone-200 rounded-lg focus:outline-none focus:border-sky-500 focus:ring-1 focus:ring-sky-500"
                    >
                      <option
                        :for={{label, value} <- role_options()}
                        value={value}
                        selected={value == user.role}
                      >
                        {label}
                      </option>
                    </select>
                    <button type="submit" class="btn-custom-primary btn-custom-sm">
                      <.icon name="hero-arrow-path" class="w-4 h-4" /> Update
                    </button>
                  </.form>
                <% end %>
              </div>
            </li>
          </ul>

          <%= if users == [] do %>
            <div class="ks-empty">
              <div class="ks-empty-icon">
                <.icon name="hero-user-group" class="w-6 h-6" />
              </div>
              <h3 class="ks-empty-title">No {role_name(role_name)}s found</h3>
              <p class="ks-empty-desc">
                There are currently no users with the {role_name(role_name)} role.
              </p>
            </div>
          <% end %>
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
