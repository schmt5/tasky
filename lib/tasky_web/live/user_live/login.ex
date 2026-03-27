defmodule TaskyWeb.UserLive.Login do
  use TaskyWeb, :live_view

  alias Tasky.Accounts

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
                  d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"
                />
              </svg>
            </div>

            <h1 class="font-serif text-[38px] text-stone-900 leading-[1.1] mb-3 font-normal">
              <%= if @current_scope do %>
                Erneut anmelden
              <% else %>
                Anmelden
              <% end %>
            </h1>

            <p class="text-[15px] text-stone-500 leading-[1.6]">
              <%= if @current_scope do %>
                Sie müssen sich erneut authentifizieren, um sensible Aktionen durchzuführen.
              <% else %>
                Noch kein Konto?
                <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-sky-600 hover:text-sky-700 transition-colors duration-150"
                >
                  Jetzt registrieren
                </.link>
                und loslegen.
              <% end %>
            </p>
          </div>

          <%!-- Success banner — appears after submit --%>
          <%= if @submitted do %>
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
                      d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                    />
                  </svg>
                </div>
                <div class="flex-1">
                  <p class="text-[13px] font-semibold text-emerald-900 mb-1">E-Mail verschickt!</p>
                  <p class="text-[13px] text-emerald-800 leading-[1.5]">
                    Falls ein Konto für <strong>{@submitted_email}</strong>
                    existiert, haben wir einen Magic Link gesendet. Bitte prüfe dein Postfach.
                  </p>
                  <%= if @magic_link do %>
                    <div class="mt-3 pt-3 border-t border-emerald-200">
                      <p class="text-[12px] text-emerald-700 mb-1.5 font-medium">
                        Demo — direkt anmelden:
                      </p>
                      <.link
                        href={@magic_link}
                        class="inline-flex items-center gap-1.5 text-[13px] font-semibold text-emerald-900 underline hover:text-emerald-950 break-all"
                      >
                        <svg
                          width="14"
                          height="14"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke="currentColor"
                          stroke-width="2.5"
                          class="shrink-0"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="M14 5l7 7m0 0l-7 7m7-7H3"
                          />
                        </svg>
                        Jetzt anmelden
                      </.link>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Form Card --%>
          <div class="bg-white rounded-[16px] border border-stone-100 shadow-[0_2px_12px_rgba(0,0,0,0.08)] overflow-hidden">
            <.form
              :let={f}
              for={@form}
              id="login_form"
              action={~p"/users/log-in"}
              phx-submit="submit"
            >
              <div class="p-8 space-y-5">
                <.input
                  readonly={!!@current_scope}
                  field={f[:email]}
                  type="email"
                  label="E-Mail"
                  autocomplete="email"
                  required
                  phx-mounted={JS.focus()}
                  class="w-full px-4 py-3 text-[15px] text-stone-900 bg-white border border-stone-200 rounded-[10px] transition-all duration-150 placeholder:text-stone-400 focus:outline-none focus:border-sky-400 focus:ring-4 focus:ring-sky-100"
                  placeholder="max@beispiel.de"
                />
              </div>

              <div class="px-8 pb-8">
                <button
                  type="submit"
                  disabled={@submitted}
                  class="w-full inline-flex items-center justify-center gap-2 bg-sky-500 text-white text-[15px] font-semibold px-6 py-3.5 rounded-[10px] shadow-[0_2px_12px_rgba(14,165,233,0.3)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <%= if @submitted do %>
                    <svg
                      width="18"
                      height="18"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2.5"
                      class="animate-spin"
                    >
                      <circle cx="12" cy="12" r="10" class="opacity-25" />
                      <path d="M12 2a10 10 0 0110 10" stroke-linecap="round" />
                    </svg>
                    E-Mail wird gesendet…
                  <% else %>
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
                        d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                      />
                    </svg>
                    Mit E-Mail anmelden
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
                  <% end %>
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
            <span>Passwortlos · Sicher · DSGVO-konform</span>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, submitted: false, magic_link: nil, submitted_email: nil)}
  end

  @impl true
  def handle_event("submit", %{"user" => %{"email" => email}}, socket) do
    magic_link =
      if user = Accounts.get_user_by_email(email) do
        if local_mail_adapter?() do
          Phoenix.PubSub.subscribe(Tasky.PubSub, "magic_link:#{email}")
        end

        Accounts.deliver_login_instructions(
          user,
          &url(~p"/users/log-in/#{&1}")
        )

        if local_mail_adapter?() do
          receive do
            {:magic_link, url} -> url
          after
            3000 -> nil
          end
        end
      end

    {:noreply, assign(socket, submitted: true, submitted_email: email, magic_link: magic_link)}
  end

  defp local_mail_adapter? do
    Application.get_env(:tasky, Tasky.Mailer)[:adapter] == Swoosh.Adapters.Logger
  end
end
