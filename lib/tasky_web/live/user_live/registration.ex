defmodule TaskyWeb.UserLive.Registration do
  use TaskyWeb, :live_view

  alias Tasky.Accounts
  alias Tasky.Accounts.User
  alias Tasky.Classes
  alias Tasky.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-gradient-to-br from-sky-50 via-white to-stone-50 flex items-center justify-center px-4 py-12">
        <div class="w-full max-w-[440px]">
          <%!-- Header --%>
          <div class="text-center mb-8">
            <div class="inline-flex items-center justify-center w-16 h-16 rounded-[16px] bg-gradient-to-br from-sky-400 to-sky-600 shadow-[0_4px_16px_rgba(14,165,233,0.25)] mb-6">
              <svg
                width="32"
                height="32"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                stroke-width="2"
                class="text-white"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
                />
              </svg>
            </div>

            <h1 class="font-serif text-[38px] text-stone-900 leading-[1.1] mb-3 font-normal">
              Konto erstellen
            </h1>

            <p class="text-[15px] text-stone-500 leading-[1.6]">
              Bereits registriert?
              <.link
                navigate={~p"/users/log-in"}
                class="font-semibold text-sky-600 hover:text-sky-700 transition-colors duration-150"
              >
                Jetzt anmelden
              </.link>
              und loslegen.
            </p>
          </div>
          <%= if @invitation do %>
            <%!-- Form Card --%>
            <div class="bg-white rounded-[16px] border border-stone-100 shadow-[0_2px_12px_rgba(0,0,0,0.08)] overflow-hidden">
              <.form
                for={@form}
                id="registration_form"
                phx-submit="save"
                phx-change="validate"
                action={~p"/users/log-in"}
                phx-trigger-action={@trigger_submit}
              >
                <div class="p-8 space-y-5">
                  <.input
                    field={@form[:firstname]}
                    type="text"
                    label="Vorname"
                    required
                    phx-mounted={JS.focus()}
                    class="w-full px-4 py-3 text-[15px] text-stone-900 bg-white border border-stone-200 rounded-[10px] transition-all duration-150 placeholder:text-stone-400 focus:outline-none focus:border-sky-400 focus:ring-4 focus:ring-sky-100"
                    placeholder="Max"
                  />

                  <.input
                    field={@form[:lastname]}
                    type="text"
                    label="Nachname"
                    required
                    class="w-full px-4 py-3 text-[15px] text-stone-900 bg-white border border-stone-200 rounded-[10px] transition-all duration-150 placeholder:text-stone-400 focus:outline-none focus:border-sky-400 focus:ring-4 focus:ring-sky-100"
                    placeholder="Mustermann"
                  />

                  <.input
                    field={@form[:email]}
                    type="email"
                    label="E-Mail"
                    autocomplete="username"
                    required
                    class="w-full px-4 py-3 text-[15px] text-stone-900 bg-white border border-stone-200 rounded-[10px] transition-all duration-150 placeholder:text-stone-400 focus:outline-none focus:border-sky-400 focus:ring-4 focus:ring-sky-100"
                    placeholder="max@beispiel.de"
                  />

                  <.input
                    field={@form[:password]}
                    type="password"
                    label="Passwort"
                    autocomplete="new-password"
                    required
                    class="w-full px-4 py-3 text-[15px] text-stone-900 bg-white border border-stone-200 rounded-[10px] transition-all duration-150 placeholder:text-stone-400 focus:outline-none focus:border-sky-400 focus:ring-4 focus:ring-sky-100"
                    placeholder="Mindestens 8 Zeichen"
                  />

                  <%= case @invitation do %>
                    <% {:class, class} -> %>
                      <.input
                        field={@form[:invitation_target]}
                        type="text"
                        label="Klasse"
                        value={class.name}
                        readonly
                        class="w-full px-4 py-3 text-[15px] text-stone-900 bg-stone-50 border border-stone-200 rounded-[10px] transition-all duration-150 cursor-not-allowed"
                      />
                    <% {:organization, organization} -> %>
                      <.input
                        field={@form[:invitation_target]}
                        type="text"
                        label="Organisation"
                        value={organization.name}
                        readonly
                        class="w-full px-4 py-3 text-[15px] text-stone-900 bg-stone-50 border border-stone-200 rounded-[10px] transition-all duration-150 cursor-not-allowed"
                      />
                      <div class="bg-sky-50 rounded-[10px] p-4 border border-sky-100">
                        <p class="text-[13px] text-stone-600 leading-[1.5]">
                          Du erstellst ein
                          <span class="font-semibold text-stone-800">Lehrpersonen-Konto</span>
                          für diese Organisation und siehst damit deren Klassen und Lernende.
                        </p>
                      </div>
                  <% end %>
                </div>

                <div class="px-8 pb-8">
                  <button
                    type="submit"
                    phx-disable-with="Konto wird erstellt..."
                    class="w-full inline-flex items-center justify-center gap-2 bg-sky-500 text-white text-[15px] font-semibold px-6 py-3.5 rounded-[10px] shadow-[0_2px_12px_rgba(14,165,233,0.3)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <svg
                      width="18"
                      height="18"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                      stroke-width="2"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                    Konto erstellen
                  </button>
                </div>
              </.form>
            </div>
          <% else %>
            <div class="bg-white rounded-[16px] border border-stone-100 shadow-[0_2px_12px_rgba(0,0,0,0.08)] p-8 text-center">
              <h2 class="text-[17px] font-semibold text-stone-900 mb-3">
                Einladungslink benötigt
              </h2>
              <p class="text-[14px] text-stone-600 leading-[1.6] mb-6">
                Die Registrierung ist nur über den Einladungslink deiner Schule möglich.
                Lernende erhalten den Link ihrer Klasse von ihrer Lehrperson,
                Lehrpersonen den Link ihrer Organisation von der Administration.
              </p>
              <.link
                navigate={~p"/users/log-in"}
                class="inline-flex items-center justify-center gap-2 bg-sky-500 text-white text-[15px] font-semibold px-6 py-3 rounded-[10px] shadow-[0_2px_12px_rgba(14,165,233,0.3)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
              >
                Zur Anmeldung
              </.link>
            </div>
          <% end %>
          <%!-- Footer Note --%>
          <div
            :if={@invitation}
            class="mt-6 flex items-center justify-center gap-2 text-[13px] text-stone-400"
          >
            <svg
              width="14"
              height="14"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
              />
            </svg>
            <span>Kostenlos · DSGVO-konform · Keine Kreditkarte nötig</span>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: TaskyWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

    socket =
      socket
      |> assign_form(changeset)
      |> assign(trigger_submit: false)
      |> assign_invitation(params)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", _params, %{assigns: %{invitation: nil}} = socket) do
    # No form is rendered without an invitation, so this is only reachable by a
    # crafted socket message. Fail closed rather than crash.
    {:noreply, put_flash(socket, :error, "Die Registrierung braucht einen Einladungslink.")}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params, socket.assigns.invitation) do
      {:ok, _user} ->
        changeset = Accounts.change_user_registration(%User{}, user_params)

        {:noreply,
         socket
         |> assign(trigger_submit: true)
         |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end

  # The link decides the role: a class slug makes a student, an organization
  # invite token makes a teacher. Nothing in the submitted params can influence
  # it — see `Tasky.Accounts.register_user/2`.
  defp assign_invitation(socket, %{"class" => slug}) when is_binary(slug) do
    case Classes.get_class_by_slug(slug) do
      nil -> reject_invitation(socket, "Die angegebene Klasse wurde nicht gefunden.")
      class -> assign(socket, invitation: {:class, class})
    end
  end

  defp assign_invitation(socket, %{"invite" => token}) when is_binary(token) do
    case Organizations.get_organization_by_invite_token(token) do
      nil -> reject_invitation(socket, "Dieser Einladungslink ist nicht mehr gültig.")
      organization -> assign(socket, invitation: {:organization, organization})
    end
  end

  defp assign_invitation(socket, _params), do: assign(socket, invitation: nil)

  defp reject_invitation(socket, message) do
    socket
    |> put_flash(:error, message)
    |> assign(invitation: nil)
  end
end
