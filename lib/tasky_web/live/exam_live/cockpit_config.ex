defmodule TaskyWeb.ExamLive.CockpitConfig do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.Exams.Exam

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Cockpit", navigate: ~p"/exams/#{@exam}/cockpit"},
              %{label: "Konfiguration"}
            ]} />
          </div>
          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Konfiguration
          </h1>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8">
        <div class="max-w-2xl">
          <%!-- SEB Config Card --%>
          <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
            <div class="p-6 border-b border-stone-100">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-sky-50 flex items-center justify-center shrink-0">
                  <.icon name="hero-shield-check" class="w-5 h-5 text-sky-500" />
                </div>
                <div>
                  <h2 class="text-lg font-semibold text-stone-800">Safe Exam Browser</h2>
                  <p class="text-sm text-stone-500">Sichere Prüfungsumgebung konfigurieren</p>
                </div>
              </div>
            </div>

            <.form for={@form} id="seb-config-form" phx-change="validate" phx-submit="save">
              <div class="p-6 space-y-6">
                <%!-- Checkbox --%>
                <div>
                  <.input
                    field={@form[:seb_enabled]}
                    type="checkbox"
                    label="Safe Exam Browser aktivieren"
                  />
                  <p class="text-sm text-stone-500 mt-1 ml-6">
                    Wenn aktiviert, können Teilnehmende die Prüfung nur im Safe Exam Browser (SEB) ablegen.
                    SEB sperrt den Computer in einen Kiosk-Modus und verhindert den Zugriff auf andere
                    Anwendungen, Screenshots und Copy-Paste.
                  </p>
                </div>

                <%!-- Quit Password (shown when SEB is enabled) --%>
                <%= if @exam.seb_enabled and @exam.seb_quit_password do %>
                  <div class="bg-amber-50 rounded-xl p-4 border border-amber-100">
                    <div class="flex items-start gap-3">
                      <.icon name="hero-key" class="w-5 h-5 text-amber-500 shrink-0 mt-0.5" />
                      <div>
                        <h3 class="text-sm font-semibold text-amber-800 mb-1">Quit-Passwort</h3>
                        <p class="text-2xl font-mono font-bold text-amber-900 tracking-widest mb-2">
                          {@exam.seb_quit_password}
                        </p>
                        <p class="text-xs text-amber-700 leading-relaxed">
                          Mit diesem Passwort können Teilnehmende den Safe Exam Browser vorzeitig beenden
                          (Ctrl+Q / Cmd+Q). Teile dieses Passwort nur bei Bedarf mündlich mit.
                          Nach Abgabe der Prüfung wird SEB automatisch beendet.
                        </p>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>

              <div class="px-6 py-4 bg-stone-50 border-t border-stone-100 flex items-center justify-between">
                <.link
                  navigate={~p"/exams/#{@exam}/cockpit"}
                  class="text-sm font-semibold text-stone-500 hover:text-stone-700 transition-colors"
                >
                  ← Zurück zum Cockpit
                </.link>
                <button
                  type="submit"
                  id="save-seb-config-btn"
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-xl shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-check" class="w-4 h-4" /> Speichern
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)
    changeset = Exam.changeset(exam, %{})
    form = to_form(changeset, as: :config)

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Konfiguration")
     |> assign(:exam, exam)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"config" => params}, socket) do
    changeset = Exam.changeset(socket.assigns.exam, params)
    {:noreply, assign(socket, :form, to_form(changeset, as: :config, action: :validate))}
  end

  def handle_event("save", %{"config" => params}, socket) do
    exam = socket.assigns.exam

    params = maybe_generate_quit_password(params, exam)

    case Exams.update_exam(exam, params) do
      {:ok, updated_exam} ->
        changeset = Exam.changeset(updated_exam, %{})

        {:noreply,
         socket
         |> assign(:exam, updated_exam)
         |> assign(:form, to_form(changeset, as: :config))
         |> put_flash(:info, "Konfiguration gespeichert.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :config))}
    end
  end

  defp maybe_generate_quit_password(params, exam) do
    seb_enabled = params["seb_enabled"] in ["true", true]

    cond do
      seb_enabled and (is_nil(exam.seb_quit_password) or exam.seb_quit_password == "") ->
        Map.put(params, "seb_quit_password", generate_quit_password())

      !seb_enabled ->
        Map.put(params, "seb_quit_password", nil)

      true ->
        params
    end
  end

  defp generate_quit_password do
    (:rand.uniform(899_999) + 100_000) |> Integer.to_string()
  end
end
