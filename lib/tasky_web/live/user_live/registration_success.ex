defmodule TaskyWeb.UserLive.RegistrationSuccess do
  use TaskyWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-gradient-to-br from-sky-50 via-white to-stone-50 flex items-center justify-center px-4 py-12">
        <div class="w-full max-w-[440px]">
          <%!-- Header --%>
          <div class="text-center mb-8">
            <div class="inline-flex items-center justify-center w-16 h-16 rounded-[16px] bg-gradient-to-br from-emerald-400 to-emerald-600 shadow-[0_4px_16px_rgba(16,185,129,0.25)] mb-6">
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
                  d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
            </div>
            
            <h1 class="font-serif text-[38px] text-stone-900 leading-[1.1] mb-3 font-normal">
              Registrierung erfolgreich
            </h1>
            
            <p class="text-[15px] text-stone-500 leading-[1.6]">
              Dein Konto wurde erstellt. Fast geschafft!
            </p>
          </div>
           <%!-- Demo / Dev: show green mailbox info box --%>
          <%= if local_mail_adapter?() do %>
            <div class="mb-6 bg-gradient-to-br from-emerald-50 to-teal-50 rounded-[12px] border border-emerald-200 p-4 shadow-[0_2px_8px_rgba(16,185,129,0.1)] animate-[fadeSlideIn_0.35s_ease-out]">
              <div class="flex items-start gap-3">
                <div class="w-8 h-8 bg-emerald-100 rounded-[8px] flex items-center justify-center shrink-0 mt-0.5">
                  <svg
                    width="18"
                    height="18"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    stroke-width="2"
                    class="text-emerald-600"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                </div>
                
                <div class="flex-1">
                  <p class="text-[13px] font-semibold text-emerald-900 mb-1">Demo Instanz</p>
                  
                  <p class="text-[13px] text-emerald-800 leading-[1.5]">
                    Das E-Mail für das Login findest du unter <.link
                      href="/dev/mailbox"
                      class="font-semibold text-emerald-900 underline hover:text-emerald-950"
                    >
                      Mail aufrufen
                    </.link>.
                  </p>
                </div>
              </div>
            </div>
          <% else %>
            <%!-- Production: show email instruction card --%>
            <div class="mb-6 bg-white rounded-[16px] border border-stone-100 shadow-[0_2px_12px_rgba(0,0,0,0.08)] p-6 animate-[fadeSlideIn_0.35s_ease-out]">
              <div class="flex items-start gap-4">
                <div class="w-10 h-10 bg-sky-100 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5">
                  <svg
                    width="20"
                    height="20"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    stroke-width="2"
                    class="text-sky-600"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                    />
                  </svg>
                </div>
                
                <div class="flex-1">
                  <p class="text-[14px] font-semibold text-stone-800 mb-1">
                    Bestätige deine E-Mail-Adresse
                  </p>
                  
                  <p class="text-[13px] text-stone-500 leading-[1.6]">
                    Wir haben einen Anmeldelink an
                  </p>
                  
                  <p class="text-[14px] font-semibold text-sky-600 mt-1 mb-2 break-all">{@email}</p>
                  
                  <p class="text-[13px] text-stone-500 leading-[1.6]">
                    gesendet. Bitte öffne dein Postfach und klicke auf den Link, um dich anzumelden.
                  </p>
                </div>
              </div>
            </div>
          <% end %>
           <%!-- Back to login link --%>
          <div class="text-center">
            <.link
              navigate={~p"/users/log-in"}
              class="inline-flex items-center gap-2 text-[14px] font-semibold text-sky-600 hover:text-sky-700 transition-colors duration-150"
            >
              <svg
                width="16"
                height="16"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                stroke-width="2.5"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M10 19l-7-7m0 0l7-7m-7 7h18"
                />
              </svg>
              Zur Anmeldeseite
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"email" => email}, _session, socket) do
    {:ok, assign(socket, email: email)}
  end

  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: ~p"/users/register")}
  end

  defp local_mail_adapter? do
    Application.get_env(:tasky, Tasky.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
