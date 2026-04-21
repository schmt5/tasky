defmodule TaskyWeb.Admin.UserEditLive do
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
          Benutzer <em>bearbeiten</em>
        </h1>
        <p>{@user.firstname} {@user.lastname} &middot; {@user.email}</p>
      </div>

      <div class="max-w-2xl space-y-6">
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="flex items-center justify-between p-6 border-b border-stone-100">
            <div>
              <h2 class="text-lg font-semibold text-stone-800">Profilinformationen</h2>
              <p class="text-sm text-stone-500 mt-1">
                Vorname, Nachname und E-Mail-Adresse
              </p>
            </div>
            <span class={[
              "inline-flex items-center text-[11px] font-semibold px-2 py-0.5 rounded-full whitespace-nowrap",
              @user.role == "admin" && "bg-red-100 text-red-800",
              @user.role == "teacher" && "bg-sky-100 text-sky-700",
              @user.role == "student" && "bg-green-100 text-green-700"
            ]}>
              {role_name(@user.role)}
            </span>
          </div>

          <div class="p-6">
            <.form
              for={@profile_form}
              id="admin-user-edit-form"
              phx-submit="update_user"
              phx-change="validate_user"
              class="space-y-5"
            >
              <div class="grid grid-cols-1 gap-5 sm:grid-cols-2">
                <.input field={@profile_form[:firstname]} type="text" label="Vorname" required />
                <.input field={@profile_form[:lastname]} type="text" label="Nachname" required />
              </div>

              <.input
                field={@profile_form[:email]}
                type="email"
                label="E-Mail"
                autocomplete="off"
                required
              />

              <div class="flex items-center justify-between pt-2">
                <.link
                  navigate={~p"/admin/users"}
                  class="text-sm font-medium text-stone-500 hover:text-stone-700"
                >
                  Zurück
                </.link>
                <.button
                  variant="primary"
                  phx-disable-with="Wird gespeichert..."
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-check" class="w-4 h-4" /> Speichern
                </.button>
              </div>
            </.form>
          </div>
        </div>

        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="flex items-center justify-between p-6 border-b border-stone-100">
            <div>
              <h2 class="text-lg font-semibold text-stone-800">Passwort</h2>
              <p class="text-sm text-stone-500 mt-1">
                Setzen Sie ein neues Passwort für den Benutzer
              </p>
            </div>
            <button
              type="button"
              phx-click="open_password_modal"
              class="inline-flex items-center gap-1.5 text-sm font-medium text-sky-600 hover:text-sky-700 bg-sky-50 hover:bg-sky-100 border border-sky-200 px-3 py-2 rounded-lg transition-all duration-150"
            >
              <.icon name="hero-key" class="w-4 h-4" /> Passwort zurücksetzen
            </button>
          </div>
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
                <p class="text-sm text-stone-500">{@user.email}</p>
              </div>
            </div>

            <.form
              for={@password_form}
              id={"password-reset-form-#{@user.id}"}
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
  def mount(%{"id" => id}, _session, socket) do
    user = Accounts.get_user!(id)
    changeset = Accounts.change_user_admin(user, %{}, validate_unique: false)

    {:ok,
     socket
     |> assign(:page_title, "Benutzer bearbeiten")
     |> assign(:user, user)
     |> assign(:profile_form, to_form(changeset))
     |> assign(:show_password_modal, false)
     |> assign(:password_form, to_form(%{"password" => ""}, as: "password_reset"))}
  end

  @impl true
  def handle_event("validate_user", %{"user" => params}, socket) do
    form =
      socket.assigns.user
      |> Accounts.change_user_admin(params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :profile_form, form)}
  end

  def handle_event("update_user", %{"user" => params}, socket) do
    case Accounts.admin_update_user(socket.assigns.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Benutzer aktualisiert.")
         |> assign(:user, user)
         |> assign(
           :profile_form,
           to_form(Accounts.change_user_admin(user, %{}, validate_unique: false))
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("open_password_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_password_modal, true)
     |> assign(:password_form, to_form(%{"password" => ""}, as: "password_reset"))}
  end

  def handle_event("close_password_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_password_modal, false)
     |> assign(:password_form, to_form(%{"password" => ""}, as: "password_reset"))}
  end

  def handle_event("reset_password", %{"password_reset" => %{"password" => password}}, socket) do
    case Accounts.admin_reset_password(socket.assigns.user, password) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Passwort für #{socket.assigns.user.email} wurde zurückgesetzt.")
         |> assign(:show_password_modal, false)}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_form, to_form(changeset, as: "password_reset"))}
    end
  end
end
