defmodule TaskyWeb.ExamLive.CockpitConfig do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.Exams.Exam
  alias TaskyWeb.ExamComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={@crumbs} />
          </div>
          <div class="flex items-center gap-3 mb-3">
            <.back_button navigate={@back_to} tooltip={@back_tooltip} />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              {@heading}
            </h1>
          </div>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <%!-- Participation Mode Card --%>
        <div class="max-w-3xl bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6 border-b border-stone-100">
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 rounded-xl bg-sky-50 flex items-center justify-center shrink-0">
                <.icon name="hero-user-group" class="w-5 h-5 text-sky-500" />
              </div>
              <div>
                <h2 class="text-lg font-semibold text-stone-800">Teilnehmende</h2>
                <p class="text-sm text-stone-500">Wer an dieser Durchführung teilnimmt</p>
              </div>
            </div>
          </div>
          <div class="p-6">
            <ExamComponents.participation_mode_picker
              value={@participation_mode}
              readonly={not @draft?}
            />
          </div>
        </div>

        <div class="max-w-3xl">
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
                <label class="flex items-start gap-3 cursor-pointer">
                  <input type="hidden" name={@form[:seb_enabled].name} value="false" />
                  <input
                    type="checkbox"
                    id={@form[:seb_enabled].id}
                    name={@form[:seb_enabled].name}
                    value="true"
                    checked={Phoenix.HTML.Form.normalize_value("checkbox", @form[:seb_enabled].value)}
                    class="mt-0.5 w-[18px] h-[18px] rounded-md border-stone-300 text-sky-500 focus:ring-sky-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150 shrink-0"
                  />
                  <span class="min-w-0">
                    <span class="block text-sm font-medium text-stone-700">
                      Safe Exam Browser aktivieren
                    </span>
                    <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                      Wenn aktiviert, können Teilnehmende die Prüfung nur im Safe Exam Browser (SEB)
                      ablegen. SEB sperrt den Computer in einen Kiosk-Modus und verhindert den Zugriff
                      auf andere Anwendungen, Screenshots und Copy-Paste.
                    </span>
                  </span>
                </label>

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
                  navigate={@back_to}
                  class="text-sm font-semibold text-stone-500 hover:text-stone-700 transition-colors"
                >
                  ← {@back_tooltip}
                </.link>
                <%= if @draft? do %>
                  <button
                    type="submit"
                    id="open-session-btn"
                    class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-xl shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                  >
                    <.icon name="hero-play" class="w-4 h-4" /> Durchführung eröffnen
                  </button>
                <% else %>
                  <button
                    type="submit"
                    id="save-seb-config-btn"
                    disabled={not @changed?}
                    class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-xl shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-40 disabled:cursor-not-allowed disabled:shadow-none disabled:hover:bg-sky-500 disabled:active:scale-100"
                  >
                    <.icon name="hero-check" class="w-4 h-4" /> Speichern
                  </button>
                <% end %>
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
     |> assign(:exam, exam)
     |> assign(:form, form)
     |> assign(:changed?, false)
     |> assign_mode()
     |> assign_chrome()}
  end

  # A draft has no cockpit yet, so the page is titled after what it does —
  # opening the session — and leads back to the exam instead.
  defp assign_chrome(socket) do
    exam = socket.assigns.exam

    if socket.assigns.draft? do
      socket
      |> assign(:page_title, exam.name <> " – Durchführung")
      |> assign(:heading, "Durchführung")
      |> assign(:back_to, ~p"/exams/#{exam}")
      |> assign(:back_tooltip, "Zurück zur Prüfung")
      |> assign(:crumbs, [
        %{label: "Prüfungen", navigate: ~p"/exams"},
        %{label: exam.name, navigate: ~p"/exams/#{exam}"},
        %{label: "Durchführung"}
      ])
    else
      socket
      |> assign(:page_title, exam.name <> " – Konfiguration")
      |> assign(:heading, "Konfiguration")
      |> assign(:back_to, ~p"/exams/#{exam}/cockpit")
      |> assign(:back_tooltip, "Zurück zum Cockpit")
      |> assign(:crumbs, [
        %{label: "Prüfungen", navigate: ~p"/exams"},
        %{label: exam.name, navigate: ~p"/exams/#{exam}"},
        %{label: "Cockpit", navigate: ~p"/exams/#{exam}/cockpit"},
        %{label: "Konfiguration"}
      ])
    end
  end

  # `assigned` is the pre-selection for a fresh session; an already-opened exam
  # shows what it actually runs as.
  defp assign_mode(socket) do
    exam = socket.assigns.exam
    draft? = exam.status == "draft"

    socket
    |> assign(:draft?, draft?)
    |> assign(:participation_mode, if(draft?, do: "assigned", else: exam.participation_mode))
  end

  @impl true
  def handle_event("validate", %{"config" => params}, socket) do
    changeset = Exam.changeset(socket.assigns.exam, params)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :config, action: :validate))
     |> assign(:changed?, changeset.changes != %{})}
  end

  # Only reachable while the exam is a draft — after that the mode is fixed, and
  # `open_exam_session/3` is the only writer of the column anyway.
  def handle_event("select_mode", %{"mode" => mode}, %{assigns: %{draft?: true}} = socket) do
    mode =
      case mode do
        "assigned" -> "assigned"
        "anonymous" -> "anonymous"
        _ -> socket.assigns.participation_mode
      end

    {:noreply, assign(socket, :participation_mode, mode)}
  end

  def handle_event("select_mode", _params, socket), do: {:noreply, socket}

  # Opening persists the pending SEB params first: the SEB form only saves on
  # its own submit, so without this a teacher who ticks SEB and opens straight
  # away would silently lose the setting.
  def handle_event("save", %{"config" => params}, %{assigns: %{draft?: true}} = socket) do
    exam = socket.assigns.exam
    scope = socket.assigns.current_scope
    params = maybe_generate_quit_password(params, exam)

    with {:ok, exam} <- Exams.update_exam(scope, exam, params),
         {:ok, exam} <- Exams.open_exam_session(scope, exam, socket.assigns.participation_mode) do
      {:noreply,
       socket
       |> put_flash(:info, "Durchführung eröffnet.")
       |> push_navigate(to: ~p"/exams/#{exam}/cockpit")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :config))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Durchführung konnte nicht eröffnet werden.")}
    end
  end

  def handle_event("save", %{"config" => params}, socket) do
    exam = socket.assigns.exam

    params = maybe_generate_quit_password(params, exam)

    case Exams.update_exam(socket.assigns.current_scope, exam, params) do
      {:ok, updated_exam} ->
        changeset = Exam.changeset(updated_exam, %{})

        {:noreply,
         socket
         |> assign(:exam, updated_exam)
         |> assign(:form, to_form(changeset, as: :config))
         |> assign(:changed?, false)
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

  defp generate_quit_password, do: Tasky.Exams.generate_quit_password()
end
