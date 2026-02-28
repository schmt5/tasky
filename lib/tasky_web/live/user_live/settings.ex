defmodule TaskyWeb.UserLive.Settings do
  use TaskyWeb, :live_view

  on_mount {TaskyWeb.UserAuth, :require_sudo_mode}

  alias Tasky.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-sky-500">
              Kontoeinstellungen
            </div>
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Profileinstellungen
          </h1>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Verwalten Sie Ihre persönlichen Informationen und Kontoeinstellungen
          </p>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <%!-- Profile Information Section --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="flex items-center justify-between p-6 border-b border-stone-100">
            <div>
              <h2 class="text-lg font-semibold text-stone-800">Profilinformationen</h2>
              <p class="text-sm text-stone-500 mt-1">
                Aktualisieren Sie Ihren Namen und persönliche Details
              </p>
            </div>
          </div>

          <div class="p-6">
            <.form
              for={@profile_form}
              id="profile_form"
              phx-submit="update_profile"
              phx-change="validate_profile"
              class="space-y-5"
            >
              <div class="grid grid-cols-1 gap-5 sm:grid-cols-2">
                <div>
                  <.input
                    field={@profile_form[:firstname]}
                    type="text"
                    label="Vorname"
                    required
                  />
                </div>
                <div>
                  <.input
                    field={@profile_form[:lastname]}
                    type="text"
                    label="Nachname"
                    required
                  />
                </div>
              </div>

              <div class="flex justify-end pt-2">
                <.button
                  variant="primary"
                  phx-disable-with="Saving..."
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-check" class="w-4 h-4" /> Profil speichern
                </.button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Email Address Section --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="flex items-center justify-between p-6 border-b border-stone-100">
            <div>
              <h2 class="text-lg font-semibold text-stone-800">E-Mail-Adresse</h2>
              <p class="text-sm text-stone-500 mt-1">Ändern Sie Ihre E-Mail für den Kontozugriff</p>
            </div>
          </div>

          <div class="p-6">
            <.form
              for={@email_form}
              id="email_form"
              phx-submit="update_email"
              phx-change="validate_email"
              class="space-y-5"
            >
              <div>
                <.input
                  field={@email_form[:email]}
                  type="email"
                  label="Email"
                  autocomplete="username"
                  required
                />
              </div>

              <div class="bg-amber-50 border border-amber-200 rounded-[10px] p-4">
                <div class="flex items-start gap-3">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-5 h-5 text-amber-600 mt-0.5 shrink-0"
                  />
                  <p class="text-sm text-amber-800 leading-[1.6]">
                    Sie erhalten einen Bestätigungslink an Ihre neue E-Mail-Adresse. Klicken Sie darauf, um die Änderung abzuschließen.
                  </p>
                </div>
              </div>

              <div class="flex justify-end pt-2">
                <.button
                  variant="primary"
                  phx-disable-with="Changing..."
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-arrow-path" class="w-4 h-4" /> E-Mail ändern
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "E-Mail erfolgreich geändert.")

        {:error, _} ->
          put_flash(socket, :error, "Der E-Mail-Änderungslink ist ungültig oder abgelaufen.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    profile_changeset = Accounts.change_user_profile(user, %{})

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:profile_form, to_form(profile_changeset))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info =
          "Ein Link zur Bestätigung Ihrer E-Mail-Änderung wurde an die neue Adresse gesendet."

        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_profile", params, socket) do
    %{"user" => user_params} = params

    profile_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, profile_form: profile_form)}
  end

  def handle_event("update_profile", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    case Accounts.update_user_profile(user, user_params) do
      {:ok, _user} ->
        info = "Profil erfolgreich aktualisiert."
        {:noreply, socket |> put_flash(:info, info)}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset, action: :insert))}
    end
  end
end
