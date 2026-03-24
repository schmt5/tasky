defmodule TaskyWeb.UserLive.TallySettings do
  use TaskyWeb, :live_view

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
              Integration
            </div>
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Tally.so API Einstellungen
          </h1>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Verwalten Sie Ihre Tally.so API-Integration für Formulare und Aufgaben
          </p>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <%!-- API Key Section --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="flex items-center justify-between p-6 border-b border-stone-100">
            <div>
              <h2 class="text-lg font-semibold text-stone-800">Tally API Key</h2>

              <p class="text-sm text-stone-500 mt-1">
                Geben Sie Ihren persönlichen Tally.so API-Schlüssel ein
              </p>
            </div>
          </div>

          <div class="p-6">
            <.form
              for={@tally_form}
              id="tally_api_key_form"
              phx-submit="update_tally_api_key"
              phx-change="validate_tally_api_key"
              class="space-y-5"
            >
              <div>
                <.input
                  field={@tally_form[:tally_api_key]}
                  type="text"
                  label="API Key"
                  placeholder="tly-..."
                  autocomplete="off"
                  required
                />
                <p class="mt-2 text-sm text-stone-500">
                  Ihren API-Schlüssel finden Sie in Ihrem Tally.so Dashboard unter Einstellungen → API
                </p>
              </div>

              <div class="bg-blue-50 border border-blue-200 rounded-[10px] p-4">
                <div class="flex items-start gap-3">
                  <.icon
                    name="hero-information-circle"
                    class="w-5 h-5 text-blue-600 mt-0.5 shrink-0"
                  />
                  <div class="text-sm text-blue-800 leading-[1.6] space-y-2">
                    <p class="font-semibold">Was ist ein Tally API Key?</p>

                    <p>
                      Mit Ihrem persönlichen API-Schlüssel kann Tasky auf Ihre Tally.so Formulare zugreifen
                      und Einreichungen automatisch verarbeiten. Der Schlüssel wird sicher in Ihrem Konto gespeichert.
                    </p>
                  </div>
                </div>
              </div>

              <div class="flex items-center justify-between pt-2">
                <button
                  :if={@tally_form.data.tally_api_key}
                  type="button"
                  phx-click="clear_tally_api_key"
                  class="text-sm text-red-600 hover:text-red-700 font-medium transition-colors"
                >
                  API Key entfernen
                </button>
                <div class="flex-1"></div>

                <.button
                  variant="primary"
                  phx-disable-with="Saving..."
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-check" class="w-4 h-4" /> API Key speichern
                </.button>
              </div>
            </.form>
          </div>
        </div>
        <%!-- Status Section --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6">
            <div class="flex items-center gap-3">
              <%= if @tally_form.data.tally_api_key do %>
                <div class="flex items-center gap-2 text-green-600">
                  <.icon name="hero-check-circle" class="w-5 h-5" />
                  <span class="text-sm font-medium">API Key konfiguriert</span>
                </div>
              <% else %>
                <div class="flex items-center gap-2 text-amber-600">
                  <.icon name="hero-exclamation-circle" class="w-5 h-5" />
                  <span class="text-sm font-medium">Kein API Key hinterlegt</span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        <%!-- Help Section --%>
        <div class="bg-stone-50 rounded-[14px] border border-stone-200 p-6">
          <h3 class="text-sm font-semibold text-stone-800 mb-3">Hilfe & Dokumentation</h3>

          <div class="space-y-2 text-sm text-stone-600">
            <p><strong>So erhalten Sie Ihren API Key:</strong></p>

            <ol class="list-decimal list-inside space-y-1 ml-2">
              <li>Melden Sie sich bei Tally.so an</li>

              <li>Öffnen Sie die Einstellungen</li>

              <li>Navigieren Sie zum Bereich "API"</li>

              <li>Erstellen Sie einen neuen API-Schlüssel oder kopieren Sie einen bestehenden</li>

              <li>Fügen Sie den Schlüssel hier ein</li>
            </ol>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    tally_changeset = Accounts.change_user_tally_api_key(user, %{})

    socket =
      socket
      |> assign(:tally_form, to_form(tally_changeset))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_tally_api_key", params, socket) do
    %{"user" => user_params} = params

    tally_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_tally_api_key(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, tally_form: tally_form)}
  end

  def handle_event("update_tally_api_key", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    case Accounts.update_user_tally_api_key(user, user_params) do
      {:ok, updated_user} ->
        info = "Tally API Key erfolgreich gespeichert."
        tally_changeset = Accounts.change_user_tally_api_key(updated_user, %{})

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> assign(:tally_form, to_form(tally_changeset))}

      {:error, changeset} ->
        {:noreply, assign(socket, :tally_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("clear_tally_api_key", _params, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_tally_api_key(user, %{tally_api_key: nil}) do
      {:ok, updated_user} ->
        info = "Tally API Key erfolgreich entfernt."

        tally_changeset = Accounts.change_user_tally_api_key(updated_user, %{})

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> assign(:tally_form, to_form(tally_changeset))}

      {:error, changeset} ->
        {:noreply, assign(socket, :tally_form, to_form(changeset, action: :insert))}
    end
  end
end
