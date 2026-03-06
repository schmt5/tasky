defmodule TaskyWeb.UserLive.Confirmation do
  use TaskyWeb, :live_view

  alias Tasky.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-gradient-to-br from-sky-50 via-white to-stone-50 flex items-center justify-center px-4 py-12">
        <div class="w-full max-w-[480px]">
          <%!-- Header --%>
          <div class="text-center mb-8">
            <h1 class="font-serif text-[38px] text-stone-900 leading-[1.1] mb-3 font-normal">
              Angemeldet bleiben?
            </h1>

            <p class="text-[15px] text-stone-700 leading-[1.6] font-medium">
              {@user.email}
            </p>

            <p class="text-[13px] text-stone-500 leading-[1.6] mt-2">
              <%= if @user.confirmed_at do %>
                Ihr Konto wurde bereits bestätigt.
              <% else %>
                Bestätigen Sie Ihr Konto und melden Sie sich an.
              <% end %>
            </p>
          </div>
          <%!-- Form Card --%>
          <div class="bg-white rounded-[16px] border border-stone-100 shadow-[0_2px_12px_rgba(0,0,0,0.08)] overflow-hidden">
            <%!-- Not yet confirmed - show confirmation options --%>
            <.form
              :if={!@user.confirmed_at}
              for={@form}
              id="confirmation_form"
              phx-mounted={JS.focus_first()}
              phx-submit="submit"
              action={~p"/users/log-in?_action=confirmed"}
              phx-trigger-action={@trigger_submit}
            >
              <input type="hidden" name={@form[:token].name} value={@form[:token].value} />

              <div class="p-8 space-y-3">
                <div class="bg-sky-50 rounded-[12px] p-4 border border-sky-100 mb-6">
                  <div class="flex items-start gap-3">
                    <div class="w-8 h-8 bg-sky-100 rounded-[8px] flex items-center justify-center shrink-0">
                      <svg
                        width="18"
                        height="18"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                        stroke-width="2"
                        class="text-sky-600"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                    </div>
                    <div class="flex-1">
                      <p class="text-[13px] font-semibold text-sky-900 mb-1">
                        Konto bestätigen
                      </p>
                      <p class="text-[13px] text-sky-800 leading-[1.5]">
                        Wählen Sie, wie Sie sich anmelden möchten. Sie können sich auf diesem Gerät dauerhaft angemeldet bleiben.
                      </p>
                    </div>
                  </div>
                </div>

                <button
                  type="submit"
                  name={@form[:remember_me].name}
                  value="true"
                  phx-disable-with="Wird bestätigt..."
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
                  Bestätigen und angemeldet bleiben
                </button>

                <button
                  type="submit"
                  phx-disable-with="Wird bestätigt..."
                  class="w-full inline-flex items-center justify-center gap-2 bg-white text-stone-700 text-[15px] font-semibold px-6 py-3.5 rounded-[10px] border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Nur diesmal anmelden
                </button>
              </div>
            </.form>
            <%!-- Already confirmed - show login options --%>
            <.form
              :if={@user.confirmed_at}
              for={@form}
              id="login_form"
              phx-submit="submit"
              phx-mounted={JS.focus_first()}
              action={~p"/users/log-in"}
              phx-trigger-action={@trigger_submit}
            >
              <input type="hidden" name={@form[:token].name} value={@form[:token].value} />

              <div class="p-8 space-y-3">
                <%= if @current_scope do %>
                  <%!-- Simple login for reauthentication --%>
                  <button
                    type="submit"
                    phx-disable-with="Wird angemeldet..."
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
                  </button>
                <% else %>
                  <%!-- Login options with remember me --%>
                  <div class="bg-sky-50 rounded-[12px] p-4 border border-sky-100 mb-6">
                    <div class="flex items-start gap-3">
                      <div class="w-8 h-8 bg-sky-100 rounded-[8px] flex items-center justify-center shrink-0">
                        <svg
                          width="18"
                          height="18"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke="currentColor"
                          stroke-width="2"
                          class="text-sky-600"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
                          />
                        </svg>
                      </div>
                      <div class="flex-1">
                        <p class="text-[13px] font-semibold text-sky-900 mb-1">
                          Anmeldung bestätigen
                        </p>
                        <p class="text-[13px] text-sky-800 leading-[1.5]">
                          Wählen Sie, ob Sie auf diesem Gerät angemeldet bleiben möchten.
                        </p>
                      </div>
                    </div>
                  </div>

                  <button
                    type="submit"
                    name={@form[:remember_me].name}
                    value="true"
                    phx-disable-with="Wird angemeldet..."
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
                        d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
                      />
                    </svg>
                    Auf diesem Gerät angemeldet bleiben
                  </button>

                  <button
                    type="submit"
                    phx-disable-with="Wird angemeldet..."
                    class="w-full inline-flex items-center justify-center gap-2 bg-white text-stone-700 text-[15px] font-semibold px-6 py-3.5 rounded-[10px] border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Nur diesmal anmelden
                  </button>
                <% end %>
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
                d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
              />
            </svg>
            <span>Sicherer Magic-Link · DSGVO-konform</span>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Der Magic-Link ist ungültig oder abgelaufen.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
