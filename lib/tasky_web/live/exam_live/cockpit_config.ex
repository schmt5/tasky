defmodule TaskyWeb.ExamLive.CockpitConfig do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.Exams.Exam
  alias TaskyWeb.ExamComponents
  alias TaskyWeb.SebGuard

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

                  <%!-- The admin password gates SEB's own settings window. It is
                        never spoken aloud, so it is hidden behind a toggle
                        rather than printed like the quit password. --%>
                  <div
                    :if={@exam.seb_admin_password}
                    class="bg-stone-50 rounded-xl p-4 border border-stone-200"
                  >
                    <div class="flex items-start gap-3">
                      <.icon name="hero-lock-closed" class="w-5 h-5 text-stone-400 shrink-0 mt-0.5" />
                      <div class="min-w-0">
                        <h3 class="text-sm font-semibold text-stone-700 mb-1">Admin-Passwort</h3>
                        <p class="text-xs text-stone-500 leading-relaxed mb-2">
                          Sperrt das Einstellungsfenster von SEB. Nur für dich — <span class="font-semibold">nie den Teilnehmenden nennen</span>.
                          Du brauchst es beim Probelauf, um den Config Key in SEB abzulesen.
                        </p>
                        <button
                          type="button"
                          phx-click="toggle_admin_password"
                          class="text-xs font-semibold text-sky-600 hover:text-sky-700"
                        >
                          {if @show_admin_password?, do: "Verbergen", else: "Anzeigen"}
                        </button>
                        <p
                          :if={@show_admin_password?}
                          class="mt-2 font-mono text-sm text-stone-800 break-all select-all"
                        >
                          {@exam.seb_admin_password}
                        </p>
                      </div>
                    </div>
                  </div>

                  <%!-- Enforcement. "observe" is what makes it safe to turn SEB
                        on at all: it reports without ever blocking, so the
                        Config Key derivation can be confirmed against the SEB
                        build in the room before it is allowed to lock anyone
                        out. --%>
                  <div class="rounded-xl border border-stone-200 p-4 space-y-3">
                    <div>
                      <h3 class="text-sm font-semibold text-stone-700">Serverseitige Prüfung</h3>
                      <p class="text-xs text-stone-500 leading-relaxed mt-0.5">
                        Solange nur gemeldet wird, genügt ein manipulierter Browser-Kennstring,
                        um die Prüfung im normalen Browser zu schreiben. Erst «Erzwingen»
                        schliesst das.
                      </p>
                    </div>

                    <div class="space-y-2">
                      <label
                        :for={{value, title, hint} <- enforcement_options()}
                        class="flex items-start gap-3 cursor-pointer"
                      >
                        <input
                          type="radio"
                          name="seb_enforcement"
                          value={value}
                          checked={@exam.seb_enforcement == value}
                          phx-click="set_enforcement"
                          phx-value-mode={value}
                          class="mt-0.5 w-[18px] h-[18px] border-stone-300 text-sky-500 focus:ring-sky-500/30 focus:ring-offset-0 cursor-pointer shrink-0"
                        />
                        <span class="min-w-0">
                          <span class="block text-sm font-medium text-stone-700">{title}</span>
                          <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">
                            {hint}
                          </span>
                        </span>
                      </label>
                    </div>

                    <div
                      :if={@exam.seb_enforcement == "enforce"}
                      class="bg-red-50 rounded-lg p-3 border border-red-100"
                    >
                      <p class="text-xs text-red-700 leading-relaxed mb-2">
                        Falls während der Prüfung niemand mehr hineinkommt: hiermit die Prüfung
                        sofort für 15 Minuten entsperren. Danach greift sie wieder von selbst.
                      </p>
                      <button
                        type="button"
                        id="seb-bypass-btn"
                        phx-click="bypass_seb"
                        class="inline-flex items-center gap-2 bg-red-500 text-white text-xs font-semibold px-3 py-2 rounded-lg transition-colors hover:bg-red-600"
                      >
                        <.icon name="hero-lock-open" class="w-4 h-4" /> SEB-Zwang 15 Minuten aussetzen
                      </button>
                      <p :if={@bypass_active?} class="text-xs text-red-800 font-semibold mt-2">
                        Zwang ausgesetzt bis {Calendar.strftime(@exam.seb_bypass_until, "%H:%M")} Uhr.
                      </p>
                    </div>

                    <%!-- Observe mode's payoff: what real clients actually sent,
                          so a value we derive wrongly can be blessed instead of
                          ending the exam for the class. --%>
                    <div :if={@observations != []} class="border-t border-stone-100 pt-3">
                      <h4 class="text-xs font-semibold text-stone-600 mb-2">
                        Beobachtete SEB-Schlüssel
                      </h4>
                      <div
                        :for={{hash, count} <- @observations}
                        class="flex items-center gap-2 mb-1.5"
                      >
                        <code class="text-[11px] font-mono text-stone-500 truncate flex-1">
                          {String.slice(hash, 0, 24)}…
                        </code>
                        <span class="text-[11px] text-stone-400 shrink-0">{count}×</span>
                        <button
                          type="button"
                          phx-click="accept_config_key"
                          phx-value-hash={hash}
                          class="text-[11px] font-semibold text-sky-600 hover:text-sky-700 shrink-0"
                        >
                          Akzeptieren
                        </button>
                      </div>
                    </div>

                    <p
                      :if={@exam.seb_accepted_config_keys != []}
                      class="text-xs text-stone-400"
                    >
                      {length(@exam.seb_accepted_config_keys)} Schlüssel manuell akzeptiert.
                    </p>
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

    # Observed Config Key hashes are exam-day diagnostics, not an audit trail:
    # they live in this LiveView's own state and are gone when it closes.
    if connected?(socket), do: Phoenix.PubSub.subscribe(Tasky.PubSub, SebGuard.topic(exam))

    {:ok,
     socket
     |> assign(:exam, exam)
     |> assign(:form, form)
     |> assign(:changed?, false)
     |> assign(:show_admin_password?, false)
     |> assign(:observed_counts, %{})
     |> assign_observations()
     |> assign_bypass()
     |> assign_mode()
     |> assign_chrome()}
  end

  @doc """
  The enforcement modes, in the order they appear on the config page.

  Two rather than three: there used to be an "Aus" that required SEB without
  checking it, which after the guard fix let exactly the same people in as
  `observe` while reporting nothing. "No Safe Exam Browser" is the checkbox
  above, not a mode.

  `observe` is the default on purpose: the Config Key derivation has to be
  confirmed against the SEB build actually installed in the exam room before it
  is allowed to lock anybody out.
  """
  def enforcement_options do
    [
      {"observe", "Melden",
       "Prüft und zeigt im Cockpit an, wer verifiziert ist — blockiert aber niemanden. " <>
         "Damit den Probelauf machen."},
      {"enforce", "Erzwingen",
       "Ohne gültigen SEB-Schlüssel kein Zugriff, auch nicht auf Speichern und Abgeben. " <>
         "Erst einschalten, wenn der Probelauf mit echtem SEB sauber war."}
    ]
  end

  # Only hashes that are not already accepted are worth offering.
  defp assign_observations(socket) do
    accepted = socket.assigns.exam.seb_accepted_config_keys || []

    observations =
      socket.assigns.observed_counts
      |> Enum.reject(fn {hash, _count} -> hash in accepted end)
      |> Enum.sort_by(fn {_hash, count} -> -count end)

    assign(socket, :observations, observations)
  end

  defp assign_bypass(socket),
    do: assign(socket, :bypass_active?, SebGuard.bypassed?(socket.assigns.exam))

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
    params = maybe_generate_seb_passwords(params, exam)

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

    params = maybe_generate_seb_passwords(params, exam)

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

  # Both SEB passwords are minted here, server-side, and only ever reach the
  # changeset from this function — they are never form input.
  #
  # Regenerating either one changes the SEB Config Key, which instantly
  # invalidates every `.seb` file already downloaded. That is why they are only
  # minted when missing, never refreshed on an ordinary save.
  def handle_event("toggle_admin_password", _params, socket) do
    {:noreply, update(socket, :show_admin_password?, &(not &1))}
  end

  def handle_event("set_enforcement", %{"mode" => mode}, socket) do
    case Exams.set_seb_enforcement(socket.assigns.current_scope, socket.assigns.exam, mode) do
      {:ok, exam} ->
        {:noreply, socket |> assign(:exam, exam) |> assign_bypass()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Modus konnte nicht gespeichert werden.")}
    end
  end

  def handle_event("bypass_seb", _params, socket) do
    case Exams.bypass_seb(socket.assigns.current_scope, socket.assigns.exam, 15) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> assign(:exam, exam)
         |> assign_bypass()
         |> put_flash(:info, "SEB-Zwang für 15 Minuten ausgesetzt.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Aussetzen fehlgeschlagen.")}
    end
  end

  def handle_event("accept_config_key", %{"hash" => hash}, socket) do
    case Exams.accept_seb_config_key(socket.assigns.current_scope, socket.assigns.exam, hash) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> assign(:exam, exam)
         # Re-filter, or the hash keeps being offered after it was accepted.
         |> assign_observations()
         |> put_flash(:info, "Schlüssel akzeptiert.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Schlüssel konnte nicht akzeptiert werden.")}
    end
  end

  @impl true
  def handle_info({:seb_observation, %{observed: observed}}, socket) when is_binary(observed) do
    counts = Map.update(socket.assigns.observed_counts, String.downcase(observed), 1, &(&1 + 1))

    {:noreply, socket |> assign(:observed_counts, counts) |> assign_observations()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp maybe_generate_seb_passwords(params, exam) do
    if params["seb_enabled"] in ["true", true] do
      params
      |> put_missing("seb_quit_password", exam.seb_quit_password, &Exams.generate_quit_password/0)
      |> put_missing(
        "seb_admin_password",
        exam.seb_admin_password,
        &Exams.generate_admin_password/0
      )
    else
      params
      |> Map.put("seb_quit_password", nil)
      |> Map.put("seb_admin_password", nil)
    end
  end

  defp put_missing(params, key, current, generator) do
    if current in [nil, ""], do: Map.put(params, key, generator.()), else: params
  end
end
