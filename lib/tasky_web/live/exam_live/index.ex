defmodule TaskyWeb.ExamLive.Index do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias TaskyWeb.ExamComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams"}>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-sky-500 mb-3">
            Prüfungsverwaltung
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Meine <em class="italic text-sky-500">Prüfungen</em>
          </h1>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Verwalte deine Prüfungen, Inhalte und Musterlösungen.
          </p>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
        <div class="flex items-center justify-between gap-4 flex-wrap p-6 border-b border-stone-100">
          <div>
            <h2 class="text-lg font-semibold text-stone-800">Alle Prüfungen</h2>

            <p class="text-sm text-stone-500 mt-1">{@exam_count} Prüfungen insgesamt</p>
          </div>

          <div class="flex items-center gap-2">
            <.link
              id="archive-link"
              navigate={~p"/exams/archive"}
              class="inline-flex items-center gap-2 text-stone-600 text-sm font-semibold px-4 py-2.5 rounded-[10px] border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-700 active:scale-[0.98]"
            >
              <.icon name="hero-archive-box" class="w-4 h-4" /> Archiv
              <span class="text-xs font-semibold tabular-nums px-1.5 py-0.5 rounded-full bg-stone-100 text-stone-500">
                {@archived_count}
              </span>
            </.link>

            <.link
              navigate={~p"/exams/new"}
              class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
            >
              <.icon name="hero-plus" class="w-4 h-4" /> Neue Prüfung
            </.link>
          </div>
        </div>

        <div :if={@has_exams} class="px-6 pt-5 pb-1">
          <div
            id="status-filter"
            role="group"
            aria-label="Nach Status filtern"
            class="inline-flex items-center flex-wrap gap-1 p-1 bg-stone-100 rounded-lg"
          >
            <.link
              :for={{value, label} <- @status_filter_options}
              id={"status-filter-#{value}"}
              patch={status_path(value)}
              replace
              aria-pressed={to_string(@status_filter == value)}
              class={[
                "inline-flex items-center gap-1.5 text-sm font-semibold px-3 py-1.5 rounded-md transition-all duration-150",
                if(@status_filter == value,
                  do: "bg-white text-stone-800 shadow-[0_1px_2px_rgba(0,0,0,0.08)]",
                  else: "text-stone-500 hover:text-stone-700"
                )
              ]}
            >
              {label}
              <span class={[
                "text-xs font-semibold tabular-nums px-1.5 py-0.5 rounded-full",
                if(@status_filter == value,
                  do: "bg-stone-100 text-stone-600",
                  else: "bg-stone-200/70 text-stone-500"
                )
              ]}>
                {Map.get(@status_counts, value, 0)}
              </span>
            </.link>
          </div>
        </div>

        <ul :if={@has_exams} id="exams" phx-update="stream" class="list-none p-0 m-0">
          <li
            id="exams-empty"
            class="hidden only:flex flex-col items-center text-center px-8 py-14"
          >
            <.icon name="hero-funnel" class="w-8 h-8 mb-3 text-stone-300" />
            <p class="text-sm font-medium text-stone-500">Keine Prüfungen mit diesem Status.</p>
          </li>
          <li
            :for={{id, exam} <- @streams.exams}
            id={id}
            class="flex items-start gap-5 px-6 py-5 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 hover:bg-stone-50"
          >
            <.link
              navigate={~p"/exams/#{exam}"}
              class="w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5 bg-sky-100 text-sky-600"
            >
              <.icon name="hero-document-text" class="w-5 h-5" />
            </.link>
            <.link
              navigate={~p"/exams/#{exam}"}
              class="flex-1 min-w-0 flex flex-col gap-1.5"
            >
              <div class="flex items-center gap-2.5 flex-wrap">
                <h3 class="text-[15px] font-semibold text-stone-800 leading-[1.4]">{exam.name}</h3>

                <.exam_status_chip status={exam.status} />
              </div>

              <div class="flex items-center gap-2 mt-1">
                <span class="text-[13px] text-stone-400 flex items-center gap-1">
                  <.icon name="hero-user" class="w-3.5 h-3.5" /> {exam.teacher.email}
                </span>
                <%= if exam.enrollment_token do %>
                  <span class="text-xs text-stone-300">·</span>
                  <span class="text-[13px] text-stone-400 flex items-center gap-1">
                    <.icon name="hero-key" class="w-3.5 h-3.5" /> Token vorhanden
                  </span>
                <% end %>
              </div>
            </.link>
            <div class="flex items-center gap-1 shrink-0 pt-0.5">
              <%!-- Only finished exams offer it here: archiving is the step
                    after an exam is done. The exam page archives any status. --%>
              <button
                :if={exam.status == "finished"}
                id={"archive-#{exam.id}"}
                type="button"
                phx-click="archive"
                phx-value-id={exam.id}
                class="inline-flex items-center gap-2 bg-transparent text-stone-500 text-[13px] font-medium px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-stone-100 hover:text-stone-700"
              >
                <.icon name="hero-archive-box" class="w-4 h-4" /> Archivieren
              </button>
              <button
                id={"duplicate-#{exam.id}"}
                type="button"
                phx-click="duplicate"
                phx-value-id={exam.id}
                phx-disable-with="Kopiert…"
                class="inline-flex items-center gap-2 bg-transparent text-stone-500 text-[13px] font-medium px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-stone-100 hover:text-stone-700"
              >
                <.icon name="hero-document-duplicate" class="w-4 h-4" /> Duplizieren
              </button>
              <.link
                id={"view-#{exam.id}"}
                navigate={~p"/exams/#{exam}"}
                class="group/view inline-flex items-center gap-1.5 text-sky-600 text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] border border-sky-200 bg-sky-50/50 transition-all duration-150 hover:bg-sky-50 hover:border-sky-300 hover:text-sky-700"
              >
                Ansehen
                <.icon
                  name="hero-arrow-right"
                  class="w-3.5 h-3.5 transition-transform duration-150 group-hover/view:translate-x-0.5"
                />
              </.link>
            </div>
          </li>
        </ul>

        <div :if={!@has_exams} class="flex flex-col items-center text-center px-8 py-16 bg-white">
          <div class="w-14 h-14 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-5">
            <.icon name="hero-document-text" class="w-6 h-6" />
          </div>

          <h3 class="text-base font-semibold text-stone-700 mb-2">Noch keine Prüfungen</h3>

          <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6] mb-6">
            Erstelle deine erste Prüfung, um loszulegen.
          </p>

          <.link
            navigate={~p"/exams/new"}
            class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Erste Prüfung erstellen
          </.link>
        </div>
      </div>

      <ExamComponents.rename_exam_modal
        :if={@renaming_exam}
        exam={@renaming_exam}
        form={@rename_form}
        source_name={@rename_source_name}
      />
    </Layouts.app>
    """
  end

  @status_filter_options [
    {"all", "Alle"},
    {"draft", "Entwurf"},
    {"open", "Offen"},
    {"running", "Laufend"},
    {"finished", "Beendet"}
  ]

  @status_filters Enum.map(@status_filter_options, &elem(&1, 0))

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Prüfungen")
     |> assign(:status_filter_options, @status_filter_options)
     |> close_rename()}
  end

  # The filter lives in the URL, so it survives a reload and the way back from
  # an exam page. Anything not on the list falls back to "all".
  @impl true
  def handle_params(params, _uri, socket) do
    status = if params["status"] in @status_filters, do: params["status"], else: "all"

    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign_exams()}
  end

  @impl true
  def handle_event("archive", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    exam = Exams.get_exam!(scope, id)

    case Exams.archive_exam(scope, exam) do
      {:ok, _exam} ->
        {:noreply,
         socket
         |> put_flash(:info, "„#{exam.name}“ wurde archiviert.")
         |> assign_exams()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Die Prüfung konnte nicht archiviert werden.")}
    end
  end

  # The copy goes straight into the rename dialog: "Kopie von — …" is only a
  # placeholder until the teacher gives it a name of its own.
  def handle_event("duplicate", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    source = Exams.get_exam!(scope, id)

    case Exams.duplicate_exam(scope, source, "Kopie von — #{source.name}") do
      {:ok, copy} ->
        {:noreply,
         socket
         |> assign_exams()
         |> open_rename(copy, source.name)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Prüfung konnte nicht kopiert werden.")}
    end
  end

  def handle_event("close_rename", _params, socket) do
    {:noreply, close_rename(socket)}
  end

  def handle_event("validate_rename", %{"exam" => %{"name" => name}}, socket) do
    changeset = Exams.change_exam(socket.assigns.renaming_exam, %{"name" => name})
    {:noreply, assign(socket, :rename_form, to_form(changeset, action: :validate, as: :exam))}
  end

  def handle_event("save_rename", %{"exam" => %{"name" => name}}, socket) do
    scope = socket.assigns.current_scope

    case Exams.update_exam(scope, socket.assigns.renaming_exam, %{"name" => name}) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> put_flash(:info, "„#{exam.name}“ gespeichert.")
         |> close_rename()
         |> assign_exams()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :rename_form, to_form(changeset, as: :exam))}
    end
  end

  defp open_rename(socket, exam, source_name) do
    socket
    |> assign(:renaming_exam, exam)
    |> assign(:rename_source_name, source_name)
    |> assign(:rename_form, to_form(Exams.change_exam(exam), as: :exam))
  end

  defp close_rename(socket) do
    socket
    |> assign(:renaming_exam, nil)
    |> assign(:rename_source_name, nil)
    |> assign(:rename_form, nil)
  end

  defp assign_exams(socket) do
    scope = socket.assigns.current_scope
    exams = Exams.list_exams(scope)
    status = socket.assigns.status_filter

    counts =
      exams
      |> Enum.frequencies_by(& &1.status)
      |> Map.put("all", length(exams))

    visible = if status == "all", do: exams, else: Enum.filter(exams, &(&1.status == status))

    socket
    |> assign(:exam_count, length(exams))
    |> assign(:has_exams, exams != [])
    |> assign(:status_counts, counts)
    |> assign(:archived_count, Exams.count_archived_exams(scope))
    |> stream(:exams, visible, reset: true)
  end

  defp status_path("all"), do: ~p"/exams"
  defp status_path(status), do: ~p"/exams?#{[status: status]}"
end
