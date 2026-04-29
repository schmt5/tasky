defmodule TaskyWeb.Admin.UserEditLive do
  use TaskyWeb, :live_view

  alias Tasky.Accounts
  alias Tasky.Classes
  import TaskyWeb.RoleHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-header">
        <div class="max-w-5xl mx-auto">
          <div class="mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Benutzer", navigate: ~p"/admin/users"},
              %{label: full_name(@user)}
            ]} />
          </div>
          <h1>
            Benutzer <em>bearbeiten</em>
          </h1>
        </div>
      </div>

      <div class="max-w-3xl mx-auto mt-10 px-8 pb-8 space-y-6">
        <%!-- Profile header --%>
        <div class="bg-white rounded-[14px] border border-stone-100 p-6 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="flex items-start gap-5">
            <div class="w-16 h-16 rounded-full flex items-center justify-center shrink-0 bg-sky-100 text-sky-700 text-[20px] font-semibold">
              {initials(@user)}
            </div>

            <div class="flex-1 min-w-0">
              <h1 class="font-serif text-[28px] text-stone-900 leading-[1.2] mb-2 font-normal">
                {full_name(@user)}
              </h1>

              <div class="flex flex-wrap items-center gap-2 mb-3">
                <span class={[
                  "inline-flex items-center text-[11px] font-semibold px-2 py-0.5 rounded-full whitespace-nowrap",
                  @user.role == "admin" && "bg-red-100 text-red-800",
                  @user.role == "teacher" && "bg-sky-100 text-sky-700",
                  @user.role == "student" && "bg-green-100 text-green-700"
                ]}>
                  {role_name(@user.role)}
                </span>

                <span class="inline-flex items-center text-[11px] font-semibold px-2 py-0.5 rounded-full bg-stone-100 text-stone-600 whitespace-nowrap">
                  <.icon name="hero-academic-cap" class="w-3 h-3 mr-1" />
                  {if @user.class, do: @user.class.name, else: "Keine Klasse"}
                </span>

                <%= if @user.confirmed_at do %>
                  <span class="inline-flex items-center gap-0.5 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-green-100 text-green-700 whitespace-nowrap">
                    <.icon name="hero-check-circle" class="w-3 h-3" /> Bestätigt
                  </span>
                <% else %>
                  <span class="inline-flex items-center text-[11px] font-semibold px-2 py-0.5 rounded-full bg-stone-100 text-stone-500 whitespace-nowrap">
                    Unbestätigt
                  </span>
                <% end %>
              </div>

              <div class="text-[13px] text-stone-500 space-y-0.5">
                <div class="flex items-center gap-1.5">
                  <.icon name="hero-envelope" class="w-3.5 h-3.5 text-stone-400" />
                  {@user.email}
                </div>
                <div :if={@user.inserted_at} class="flex items-center gap-1.5">
                  <.icon name="hero-calendar" class="w-3.5 h-3.5 text-stone-400" />
                  Mitglied seit {format_date(@user.inserted_at)}
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Profile edit form --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="px-6 py-5 border-b border-stone-100">
            <h2 class="text-lg font-semibold text-stone-800">Profil</h2>
            <p class="text-sm text-stone-500 mt-1">
              Vorname, Nachname, E-Mail-Adresse und Klassenzuordnung
            </p>
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

              <.input
                field={@profile_form[:class_id]}
                type="select"
                label="Klasse"
                prompt="Keine Klasse"
                options={Enum.map(@classes, &{&1.name, &1.id})}
              />

              <div class="flex items-center justify-between pt-2">
                <.link
                  navigate={~p"/admin/users"}
                  class="inline-flex items-center gap-1.5 text-sm font-medium text-stone-500 hover:text-stone-700 transition-colors"
                >
                  <.icon name="hero-arrow-left" class="w-4 h-4" /> Zurück
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

        <%!-- Security --%>
        <div class="bg-white rounded-[14px] border border-stone-100 px-6 py-4 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] flex items-center justify-between gap-4">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-[10px] bg-stone-100 flex items-center justify-center shrink-0">
              <.icon name="hero-key" class="w-5 h-5 text-stone-500" />
            </div>
            <div>
              <h2 class="text-[15px] font-semibold text-stone-800">Passwort</h2>
              <p class="text-[13px] text-stone-500">
                Setzen Sie ein neues Passwort für den Benutzer.
              </p>
            </div>
          </div>
          <button
            type="button"
            phx-click="open_password_modal"
            class="inline-flex items-center gap-1.5 text-sm font-medium text-sky-700 hover:text-sky-800 bg-sky-50 hover:bg-sky-100 border border-sky-200 px-3 py-2 rounded-lg transition-all duration-150 shrink-0"
          >
            <.icon name="hero-arrow-path" class="w-4 h-4" /> Zurücksetzen
          </button>
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
    user = Accounts.get_user!(id) |> Tasky.Repo.preload(:class)
    changeset = Accounts.change_user_admin(user, %{}, validate_unique: false)

    {:ok,
     socket
     |> assign(:page_title, "Benutzer bearbeiten")
     |> assign(:user, user)
     |> assign(:classes, Classes.list_classes())
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
        user = Tasky.Repo.preload(user, :class, force: true)

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

  defp full_name(user) do
    case String.trim("#{user.firstname || ""} #{user.lastname || ""}") do
      "" -> user.email || ""
      name -> name
    end
  end

  defp initials(user) do
    first = first_letter(user.firstname)
    last = first_letter(user.lastname)

    case first <> last do
      "" -> "?"
      letters -> letters
    end
  end

  defp first_letter(nil), do: ""
  defp first_letter(""), do: ""
  defp first_letter(name), do: name |> String.first() |> String.upcase()

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y")
  defp format_date(_), do: ""
end
