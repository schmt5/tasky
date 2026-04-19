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
                  <button
                    type="button"
                    phx-click="open_password_modal"
                    phx-value-user-id={user.id}
                    class="inline-flex items-center gap-1.5 text-sm font-medium text-sky-600 hover:text-sky-700 bg-sky-50 hover:bg-sky-100 border border-sky-200 px-3 py-2 rounded-lg transition-all duration-150"
                  >
                    <.icon name="hero-key" class="w-4 h-4" /> Passwort
                  </button>
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

      <%= if @show_password_modal do %>
        <dialog
          class="modal modal-open"
          phx-window-keydown="close_password_modal"
          phx-key="escape"
        >
          <div class="modal-box max-w-md">
            <div class="flex items-center gap-3 mb-6">
              <div class="w-10 h-10 bg-sky-100 rounded-xl flex items-center justify-center">
                <.icon name="hero-key" class="w-5 h-5 text-sky-600" />
              </div>
              <div>
                <h3 class="text-lg font-semibold text-stone-900">Passwort zurücksetzen</h3>
                <p class="text-sm text-stone-500">{@selected_user.email}</p>
              </div>
            </div>

            <.form
              for={@password_form}
              id={"password-reset-form-#{@selected_user.id}"}
              phx-submit="reset_password"
            >
              <div class="space-y-4">
                <.input
                  field={@password_form[:password]}
                  type="text"
                  label="Neues Passwort"
                  placeholder="Mindestens 8 Zeichen"
                  required
                  phx-mounted={JS.focus()}
                  class="w-full px-4 py-3 text-[15px] text-stone-900 bg-white border border-stone-200 rounded-[10px] transition-all duration-150 placeholder:text-stone-400 focus:outline-none focus:border-sky-400 focus:ring-4 focus:ring-sky-100"
                />

                <div class="bg-amber-50 border border-amber-200 rounded-[10px] p-3">
                  <div class="flex items-start gap-2">
                    <.icon
                      name="hero-exclamation-triangle"
                      class="w-4 h-4 text-amber-600 mt-0.5 shrink-0"
                    />
                    <p class="text-xs text-amber-800 leading-[1.5]">
                      Das Passwort wird sofort geändert. Der Benutzer muss sich mit dem neuen Passwort anmelden.
                    </p>
                  </div>
                </div>
              </div>

              <div class="flex justify-end gap-3 mt-6">
                <button
                  type="button"
                  phx-click="close_password_modal"
                  class="px-4 py-2.5 text-sm font-medium text-stone-700 bg-white border border-stone-200 rounded-[10px] hover:bg-stone-50 transition-all duration-150"
                >
                  Abbrechen
                </button>
                <button
                  type="submit"
                  phx-disable-with="Wird gespeichert..."
                  class="px-4 py-2.5 text-sm font-semibold text-white bg-sky-500 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] hover:bg-sky-600 transition-all duration-150"
                >
                  Passwort setzen
                </button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop bg-black/50" phx-click="close_password_modal">
            <button class="cursor-default">close</button>
          </div>
        </dialog>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    users_by_role = Accounts.list_all_users_grouped_by_role()

    {:ok,
     socket
     |> assign(:users_by_role, users_by_role)
     |> assign(:page_title, "User Management")
     |> assign(:show_password_modal, false)
     |> assign(:selected_user, nil)
     |> assign(:password_form, to_form(%{"password" => ""}, as: "password_reset"))}
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

  def handle_event("open_password_modal", %{"user-id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)

    {:noreply,
     socket
     |> assign(:show_password_modal, true)
     |> assign(:selected_user, user)
     |> assign(:password_form, to_form(%{"password" => ""}, as: "password_reset"))}
  end

  def handle_event("close_password_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_password_modal, false)
     |> assign(:selected_user, nil)
     |> assign(:password_form, to_form(%{"password" => ""}, as: "password_reset"))}
  end

  def handle_event("reset_password", %{"password_reset" => %{"password" => password}}, socket) do
    user = socket.assigns.selected_user

    case Accounts.admin_reset_password(user, password) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Passwort für #{user.email} wurde zurückgesetzt.")
         |> assign(:show_password_modal, false)
         |> assign(:selected_user, nil)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:password_form, to_form(changeset, as: "password_reset"))}
    end
  end
end
