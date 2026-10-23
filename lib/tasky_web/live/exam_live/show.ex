defmodule TaskyWeb.ExamLive.Show do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias TaskyWeb.ExamComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={
              if(@archived?,
                do: [
                  %{label: "Prüfungen", navigate: ~p"/exams"},
                  %{label: "Archiv", navigate: ~p"/exams/archive"},
                  %{label: @exam.name}
                ],
                else: [%{label: "Prüfungen", navigate: ~p"/exams"}, %{label: @exam.name}]
              )
            } />

            <div class="flex items-center gap-2">
              <button
                type="button"
                popovertarget="exam-actions-menu"
                style="anchor-name:--exam-actions-anchor"
                aria-label="Aktionen"
                class="inline-flex items-center justify-center w-9 h-9 rounded-[6px] text-stone-500 border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-700"
              >
                <.icon name="hero-ellipsis-vertical" class="w-5 h-5" />
              </button>
              <ul
                popover
                id="exam-actions-menu"
                style="position-anchor:--exam-actions-anchor"
                class="dropdown dropdown-end menu z-[60] p-2 shadow-lg bg-white rounded-[10px] w-56 border border-stone-100"
              >
                <li>
                  <button
                    id="rename-exam"
                    type="button"
                    phx-click="rename"
                    popovertarget="exam-actions-menu"
                    popovertargetaction="hide"
                    class="flex items-center gap-2 text-sm text-stone-700"
                  >
                    <.icon name="hero-pencil" class="w-4 h-4 text-stone-400" /> Umbenennen
                  </button>
                </li>
                <li>
                  <%!-- Here as well as in the cockpit: the paper copies are
                       prepared *before* the session is opened, while the exam
                       is still a draft and the cockpit is not yet the
                       affordance in front of the teacher. --%>
                  <.link
                    navigate={~p"/exams/#{@exam}/paper"}
                    class="flex items-center gap-2 text-sm text-stone-700"
                  >
                    <.icon name="hero-printer" class="w-4 h-4 text-stone-400" /> Papierversion
                  </.link>
                </li>
                <li>
                  <button
                    id="duplicate-exam"
                    type="button"
                    phx-click="duplicate_exam"
                    popovertarget="exam-actions-menu"
                    popovertargetaction="hide"
                    class="flex items-center gap-2 text-sm text-stone-700"
                  >
                    <.icon name="hero-document-duplicate" class="w-4 h-4 text-stone-400" />
                    Duplizieren
                  </button>
                </li>
                <li>
                  <%!-- Any status: archiving only takes the exam off the
                       list, so even a running session may go — the confirm
                       says that it keeps running. --%>
                  <%= if @archived? do %>
                    <button
                      id="unarchive-exam"
                      type="button"
                      phx-click="unarchive"
                      popovertarget="exam-actions-menu"
                      popovertargetaction="hide"
                      class="flex items-center gap-2 text-sm text-stone-700"
                    >
                      <.icon name="hero-arrow-uturn-left" class="w-4 h-4 text-stone-400" />
                      Wiederherstellen
                    </button>
                  <% else %>
                    <button
                      id="archive-exam"
                      type="button"
                      phx-click="archive"
                      popovertarget="exam-actions-menu"
                      popovertargetaction="hide"
                      data-confirm={
                        @exam.status in ["open", "running"] &&
                          "Die Durchführung läuft weiter, die Prüfung verschwindet nur aus deiner Liste. Trotzdem archivieren?"
                      }
                      class="flex items-center gap-2 text-sm text-stone-700"
                    >
                      <.icon name="hero-archive-box" class="w-4 h-4 text-stone-400" /> Archivieren
                    </button>
                  <% end %>
                </li>
                <li>
                  <button
                    type="button"
                    phx-click="delete"
                    data-confirm="Bist du sicher, dass du diese Prüfung löschen möchtest?"
                    class="flex items-center gap-2 text-sm text-red-600 hover:bg-red-50"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" /> Löschen
                  </button>
                </li>
              </ul>
              <%= if @exam.status in ["open", "running"] do %>
                <.link
                  navigate={~p"/exams/#{@exam}/cockpit"}
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-computer-desktop" class="w-4 h-4" /> Cockpit
                </.link>
              <% end %>
            </div>
          </div>

          <div class="flex items-center gap-3 mb-3">
            <%= if @archived? do %>
              <.back_button navigate={~p"/exams/archive"} tooltip="Zurück zum Archiv" />
            <% else %>
              <.back_button navigate={~p"/exams"} tooltip="Zurück zu Prüfungen" />
            <% end %>
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              {@exam.name}
            </h1>
          </div>

          <div class="flex items-center gap-3 mt-2">
            <.exam_status_chip status={@exam.status} />
            <%!-- Beim Erstellen einmal entschieden und danach fix, deshalb hier
                 als Feststellung statt als Bedienelement. --%>
            <span
              class="tooltip tooltip-bottom tooltip-delayed text-[13px] text-stone-400 flex items-center gap-1"
              data-tip={@answer_mode_option.summary}
            >
              <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
              {@answer_mode_option.state_label}
            </span>
            <span class="text-[13px] text-stone-400 flex items-center gap-1">
              <.icon name="hero-user" class="w-3.5 h-3.5" /> {@exam.teacher.email}
            </span>
          </div>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <div
          :if={@archived?}
          id="archived-notice"
          class="flex items-center gap-4 flex-wrap bg-stone-50 border border-stone-200 rounded-[14px] px-6 py-4"
        >
          <div class="w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 bg-white text-stone-400 ring-1 ring-stone-200">
            <.icon name="hero-archive-box" class="w-5 h-5" />
          </div>
          <p class="flex-1 min-w-0 text-sm text-stone-600">
            Archiviert am {Calendar.strftime(@exam.archived_at, "%d.%m.%Y")}. Die Prüfung erscheint nicht mehr in deiner Prüfungsliste.
          </p>
          <button
            id="archived-notice-unarchive"
            type="button"
            phx-click="unarchive"
            class="inline-flex items-center gap-2 bg-white text-stone-700 text-sm font-semibold px-4 py-2 rounded-[10px] border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 active:scale-[0.98]"
          >
            <.icon name="hero-arrow-uturn-left" class="w-4 h-4" /> Wiederherstellen
          </button>
        </div>

        <%!-- Status Card --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6">
            <div class="flex items-start gap-4">
              <div class={[
                "w-12 h-12 rounded-[12px] flex items-center justify-center shrink-0",
                @exam.status == "draft" && "bg-amber-50 text-amber-500",
                @exam.status == "open" && "bg-blue-50 text-blue-600",
                @exam.status == "running" && "bg-emerald-50 text-emerald-500",
                @exam.status == "finished" && "bg-stone-100 text-stone-500"
              ]}>
                <.icon name="hero-signal" class="w-6 h-6" />
              </div>
              <div class="flex-1">
                <h3 class="text-base font-semibold text-stone-800 mb-1.5">
                  Status
                </h3>
                <p class="text-sm text-stone-500 leading-relaxed">
                  <%= cond do %>
                    <% @exam.status == "draft" -> %>
                      Die Prüfung ist ein Entwurf. Sobald du bereit bist, kannst du die Durchführung öffnen und dabei festlegen, wer teilnimmt.
                    <% @exam.status == "open" && @exam.participation_mode == "assigned" -> %>
                      Die Durchführung ist offen. Die zugewiesenen Lernenden sehen die Prüfung auf ihrem Dashboard und befinden sich im Warteraum.
                    <% @exam.status == "open" -> %>
                      Die Durchführung ist offen. Teilnehmende können sich über den Einschreibelink einschreiben und befinden sich im Warteraum.
                    <% @exam.status == "running" -> %>
                      Die Prüfung läuft. Lernende bearbeiten gerade die Prüfung.
                    <% @exam.status == "finished" -> %>
                      Die Prüfung ist beendet. Keine weiteren Abgaben möglich.
                  <% end %>
                </p>
                <%= if @exam.status == "draft" do %>
                  <div class="mt-4 flex items-center gap-3">
                    <.link
                      navigate={~p"/exams/#{@exam}/cockpit/config"}
                      class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                    >
                      Durchführung öffnen
                    </.link>
                  </div>
                <% end %>
                <%= if @exam.status in ["open", "running"] do %>
                  <div class="mt-4 flex items-center gap-3">
                    <.link
                      navigate={~p"/exams/#{@exam}/cockpit"}
                      class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                    >
                      <.icon name="hero-computer-desktop" class="w-4 h-4" /> Zum Cockpit
                    </.link>
                  </div>
                <% end %>
                <%!-- One primary action per row: as long as parts are open the
                      correction is the next step; once every part is corrected the
                      grading takes over and the correction becomes a revisit. --%>
                <%= if @exam.status == "finished" do %>
                  <div class="mt-4 flex items-center gap-3">
                    <.link
                      navigate={~p"/exams/#{@exam}/correction"}
                      class={[
                        "inline-flex items-center gap-2 text-sm font-semibold px-5 py-2.5 rounded-[10px] transition-all duration-150 active:scale-[0.98]",
                        if(@grading_available,
                          do:
                            "text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-700",
                          else:
                            "bg-sky-500 text-white shadow-[0_2px_8px_rgba(14,165,233,0.25)] hover:bg-sky-600"
                        )
                      ]}
                    >
                      <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4" /> Zur Korrektur
                    </.link>
                    <.link
                      :if={@grading_available}
                      navigate={~p"/exams/#{@exam}/correction/grading"}
                      class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                    >
                      <.icon name="hero-academic-cap" class="w-4 h-4" /> Zur Benotung
                    </.link>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <%!-- Content: the whole exam as learners will see it, read-only. --%>
        <div
          id="exam-content-card"
          class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]"
        >
          <div class="flex justify-end px-6 pt-6">
            <.link
              id="edit-exam-content"
              navigate={~p"/exams/#{@exam}/content"}
              class={[
                "inline-flex items-center gap-2 text-sm font-semibold px-5 py-2.5 rounded-[10px] transition-all duration-150 active:scale-[0.98]",
                if(@exam.status == "draft",
                  do:
                    "bg-sky-500 text-white shadow-[0_2px_8px_rgba(14,165,233,0.25)] hover:bg-sky-600",
                  else:
                    "text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-700"
                )
              ]}
            >
              <.icon name="hero-pencil" class="w-4 h-4" /> Bearbeiten
            </.link>
          </div>
          <div class="px-6 pb-6">
            <%= if @content_json do %>
              <div
                id={"exam-content-viewer-#{@exam.id}"}
                phx-hook="ExamReadOnlyViewer"
                phx-update="ignore"
                data-content={@content_json}
              >
              </div>
            <% else %>
              <div
                id="exam-content-empty"
                class="flex flex-col items-center text-center py-12"
              >
                <.icon name="hero-document-text" class="w-8 h-8 mb-3 text-stone-300" />
                <p class="text-sm font-medium text-stone-500">Noch kein Inhalt vorhanden.</p>
              </div>
            <% end %>
          </div>
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

  # nil for an exam without blocks, so the card shows its empty state instead
  # of a blank viewer.
  defp content_json(%{"content" => [_ | _]} = content), do: Jason.encode!(content)
  defp content_json(_content), do: nil

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, exam.name)
     |> assign_exam(exam)
     |> assign(:answer_mode_option, ExamComponents.answer_mode_option(exam.answer_mode))
     |> assign(:grading_available, grading_available?(exam))
     |> close_rename()}
  end

  defp grading_available?(exam) do
    parts = Exams.split_content_into_parts(exam.content || %{}, exam.answer_mode)
    submissions = Exams.list_exam_submissions(exam)

    parts != [] and submissions != [] and
      Enum.all?(submissions, fn s ->
        done = MapSet.new(s.corrected_parts || [])
        Enum.all?(parts, fn p -> p.id in done end)
      end)
  end

  defp assign_exam(socket, exam) do
    socket
    |> assign(:exam, exam)
    |> assign(:archived?, Exams.archived?(exam))
    |> assign(:content_json, content_json(exam.content))
  end

  @impl true
  def handle_event("archive", _params, socket) do
    case Exams.archive_exam(socket.assigns.current_scope, socket.assigns.exam) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> assign_exam(exam)
         |> put_flash(:info, "Prüfung archiviert")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Die Prüfung konnte nicht archiviert werden.")}
    end
  end

  def handle_event("unarchive", _params, socket) do
    case Exams.unarchive_exam(socket.assigns.current_scope, socket.assigns.exam) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> assign_exam(exam)
         |> put_flash(:info, "Prüfung wiederhergestellt")}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "Die Prüfung konnte nicht wiederhergestellt werden.")}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Exams.delete_exam(socket.assigns.current_scope, socket.assigns.exam)

    {:noreply,
     socket
     |> put_flash(:info, "Prüfung erfolgreich gelöscht")
     |> push_navigate(to: ~p"/exams")}
  end

  @impl true
  def handle_event("duplicate_exam", _params, socket) do
    case Exams.duplicate_exam(
           socket.assigns.current_scope,
           socket.assigns.exam,
           "Kopie von — #{socket.assigns.exam.name}"
         ) do
      # Named here, over the original, and only then off to the copy — however
      # the dialog is left, since the copy exists either way.
      {:ok, new_exam} ->
        {:noreply, open_rename(socket, new_exam, socket.assigns.exam.name)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Prüfung konnte nicht kopiert werden.")}
    end
  end

  def handle_event("rename", _params, socket) do
    {:noreply, open_rename(socket, socket.assigns.exam, nil)}
  end

  def handle_event("close_rename", _params, socket) do
    case socket.assigns.renaming_exam do
      %{id: id} = copy when id != socket.assigns.exam.id ->
        {:noreply, push_navigate(socket, to: ~p"/exams/#{copy}")}

      _ ->
        {:noreply, close_rename(socket)}
    end
  end

  def handle_event("validate_rename", %{"exam" => %{"name" => name}}, socket) do
    changeset = Exams.change_exam(socket.assigns.renaming_exam, %{"name" => name})
    {:noreply, assign(socket, :rename_form, to_form(changeset, action: :validate, as: :exam))}
  end

  def handle_event("save_rename", %{"exam" => %{"name" => name}}, socket) do
    renaming = socket.assigns.renaming_exam

    case Exams.update_exam(socket.assigns.current_scope, renaming, %{"name" => name}) do
      {:ok, exam} when exam.id == socket.assigns.exam.id ->
        {:noreply,
         socket
         |> put_flash(:info, "Prüfung umbenannt")
         |> assign(:page_title, exam.name)
         |> assign_exam(exam)
         |> close_rename()}

      {:ok, copy} ->
        {:noreply, push_navigate(socket, to: ~p"/exams/#{copy}")}

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
end
