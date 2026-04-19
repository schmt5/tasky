defmodule TaskyWeb.UserLive.Login do
  use TaskyWeb, :live_view

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
                  d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
                />
              </svg>
            </div>

            <h1 class="font-serif text-[38px] text-stone-900 leading-[1.1] mb-3 font-normal">
              Anmelden
            </h1>

            <p class="text-[15px] text-stone-500 leading-[1.6]">
              Noch kein Konto?
              <.link
                navigate={~p"/users/register"}
                class="font-semibold text-sky-600 hover:text-sky-700 transition-colors duration-150"
              >
                Jetzt registrieren
              </.link>
              und loslegen.
            </p>
          </div>

          <%!-- Form Card --%>
          <div class="bg-white rounded-[16px] border border-stone-100 shadow-[0_2px_12px_rgba(0,0,0,0.08)] overflow-hidden">
            <.form
              for={@form}
              id="login_form"
              action={~p"/users/log-in"}
              phx-submit="submit"
              phx-trigger-action={@trigger_submit}
            >
              <div class="p-8 space-y-5">
                <.input
                  field={@form[:email]}
                  type="email"
                  label="E-Mail"
                  autocomplete="username"
                  required
                  phx-mounted={JS.focus()}
                  class="w-full px-4 py-3 text-[15px] text-stone-900 bg-white border border-stone-200 rounded-[10px] transition-all duration-150 placeholder:text-stone-400 focus:outline-none focus:border-sky-400 focus:ring-4 focus:ring-sky-100"
                  placeholder="max@beispiel.de"
                />

                <.input
                  field={@form[:password]}
                  type="password"
                  label="Passwort"
                  autocomplete="current-password"
                  required
                  class="w-full px-4 py-3 text-[15px] text-stone-900 bg-white border border-stone-200 rounded-[10px] transition-all duration-150 placeholder:text-stone-400 focus:outline-none focus:border-sky-400 focus:ring-4 focus:ring-sky-100"
                  placeholder="••••••••"
                />
              </div>

              <div class="px-8 pb-8">
                <button
                  type="submit"
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
                      d="M11 16l-4-4m0 0l4-4m-4 4h14m-5 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h7a3 3 0 013 3v1"
                    />
                  </svg>
                  Anmelden
                  <svg
                    width="16"
                    height="16"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    stroke-width="2.5"
                    class="ml-1"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M14 5l7 7m0 0l-7 7m7-7H3"
                    />
                  </svg>
                </button>
              </div>
            </.form>
          </div>

          <%!-- Footer Note --%>
          <div class="mt-6 flex items-center justify-center gap-2 text-[13px] text-stone-400">
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
            <span>Sicher · DSGVO-konform</span>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email || "", "password" => ""}, as: "user")
    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit", %{"user" => user_params}, socket) do
    {:noreply, assign(socket, form: to_form(user_params, as: "user"), trigger_submit: true)}
  end
end
