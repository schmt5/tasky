defmodule TaskyWeb.ExamLive.Correction do
  use TaskyWeb, :live_view

  import TaskyWeb.FileComponents

  alias Tasky.Exams
  alias Tasky.Grading

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-7xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Korrektur"}
            ]} />
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button navigate={~p"/exams/#{@exam}"} tooltip={"Zurück zu #{@exam.name}"} />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal flex-1">
              Korrektur
            </h1>
            <%= if @parts != [] and @submissions != [] and is_nil(@summary.first_uncorrected) do %>
              <.link
                navigate={~p"/exams/#{@exam}/correction/grading"}
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] focus:outline-none focus-visible:ring-4 focus-visible:ring-sky-600 focus-visible:ring-offset-2"
              >
                <.icon name="hero-academic-cap" class="w-4 h-4" /> Zur Benotung
              </.link>
            <% end %>
          </div>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-8 pb-8">
        <%= if @parts != [] and @submissions != [] do %>
          <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-5 mb-4 flex items-center gap-6">
            <div class="flex-1 min-w-0">
              <div class="flex items-center justify-between mb-2">
                <span class="text-xs font-semibold text-stone-500 uppercase tracking-wide">
                  Fortschritt
                </span>
                <span class="text-sm font-semibold text-stone-700 tabular-nums">
                  {@summary.corrected} / {@summary.total} {if @free_document,
                    do: "Abgaben",
                    else: "Teile"} erledigt
                </span>
              </div>
              <div class="h-2 bg-stone-100 rounded-full overflow-hidden">
                <div
                  class="h-full bg-green-500 transition-all duration-500"
                  style={"width: #{@summary.percent}%"}
                >
                </div>
              </div>
            </div>

            <div class="shrink-0">
              <%!-- Steps back to a secondary button once every part is done: the
                    "Zur Benotung" action in the header is the next step then. --%>
              <.link
                navigate={@resume_path}
                class={[
                  "inline-flex items-center gap-2 text-sm font-semibold px-5 py-2.5 rounded-lg transition-all duration-150 active:scale-[0.98] focus:outline-none focus-visible:ring-4 focus-visible:ring-offset-2",
                  if(is_nil(@summary.first_uncorrected),
                    do:
                      "text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-700 focus-visible:ring-stone-400",
                    else:
                      "bg-emerald-500 text-white shadow-[0_2px_8px_rgba(16,185,129,0.25)] hover:bg-emerald-600 focus-visible:ring-emerald-600"
                  )
                ]}
              >
                <.icon name="hero-play" class="w-4 h-4" />
                {cond do
                  @summary.corrected == 0 -> "Korrektur starten"
                  is_nil(@summary.first_uncorrected) -> "Korrektur überprüfen"
                  true -> "Korrektur fortsetzen"
                end}
              </.link>
            </div>
          </div>
        <% end %>

        <%= if match?({:running, _}, @bulk_status) do %>
          {render_auto_correction_progress(assigns)}
        <% end %>

        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <%= if @parts == [] do %>
            <div class="p-12 text-center text-stone-400">
              <.icon name="hero-document" class="w-10 h-10 mx-auto mb-3 text-stone-300" />
              <p class="text-sm font-medium">
                Noch keine Fragen erstellt. Füge im Editor eine Frage hinzu.
              </p>
            </div>
          <% else %>
            <%= if @submissions == [] do %>
              <div class="p-12 text-center text-stone-400">
                <.icon name="hero-user-group" class="w-10 h-10 mx-auto mb-3 text-stone-300" />
                <p class="text-sm font-medium">Keine Teilnehmenden vorhanden.</p>
              </div>
            <% else %>
              <%= if @free_document do %>
                {render_by_participant(assigns)}
              <% else %>
                {render_by_question(assigns)}
              <% end %>
            <% end %>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # One row per question, because the teacher works question by question: the
  # question column stays pinned while the participant columns scroll past.
  defp render_by_question(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table id="correction-by-question" class="w-full text-left border-collapse">
        <thead>
          <tr class="bg-stone-50 border-b border-stone-100">
            <th
              scope="col"
              class="sticky left-0 z-10 bg-stone-50 px-6 py-3 border-r border-stone-200 min-w-[34rem]"
            >
              <div class="flex items-center gap-4 text-xs font-semibold text-stone-500 uppercase tracking-wide">
                <span class="flex-1">Frage</span>
                <span class="w-32">Status</span>
                <span class="w-36">Aktion</span>
              </div>
            </th>
            <th
              :for={submission <- @submissions}
              id={"correction-participant-#{submission.id}"}
              scope="col"
              class="px-2 py-3 min-w-[84px] max-w-[96px]"
            >
              <div
                class={[
                  "flex flex-col items-center gap-1 tooltip tooltip-bottom tooltip-delayed",
                  !submission.submitted && "opacity-50"
                ]}
                data-tip={participant_tip(submission)}
              >
                <.participant_avatar person={submission} size="sm" />
                <span class="max-w-[80px] truncate text-[11px] font-semibold text-stone-600 normal-case">
                  {submission.firstname}
                </span>
              </div>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-stone-100">
          <tr
            :for={part <- @parts}
            id={"correction-part-#{part.id}"}
            data-status={part_status(@done_counts, part, @submissions)}
            class="group transition-colors duration-150 hover:bg-stone-50"
          >
            <th
              scope="row"
              class="sticky left-0 z-10 bg-white group-hover:bg-stone-50 px-6 py-3 border-r border-stone-200 font-normal transition-colors duration-150"
            >
              <div class="flex items-center gap-4">
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-semibold text-stone-800 line-clamp-2">{part.label}</p>
                  <p class="text-xs text-stone-400 mt-0.5 tabular-nums">
                    max. {max_points_label(@exam, part)}
                  </p>
                </div>
                <div class="w-32">
                  {render_part_status(%{
                    status: part_status(@done_counts, part, @submissions),
                    done: Map.get(@done_counts, part.id, 0),
                    total: length(@submissions)
                  })}
                </div>
                <div class="w-36">
                  <.link
                    id={"correction-action-#{part.id}"}
                    navigate={~p"/exams/#{@exam}/correction/bulk/#{part.id}"}
                    class={[
                      "inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-2 rounded-lg transition-all duration-150 active:scale-[0.98] focus:outline-none focus-visible:ring-4 focus-visible:ring-offset-2",
                      if(part_status(@done_counts, part, @submissions) == :done,
                        do:
                          "text-stone-600 border border-stone-200 bg-white hover:bg-stone-100 hover:border-stone-300 hover:text-stone-700 focus-visible:ring-stone-400",
                        else:
                          "bg-emerald-500 text-white shadow-[0_2px_8px_rgba(16,185,129,0.25)] hover:bg-emerald-600 focus-visible:ring-emerald-600"
                      )
                    ]}
                  >
                    <%= if part_status(@done_counts, part, @submissions) == :done do %>
                      <.icon name="hero-eye" class="w-4 h-4" /> Überprüfen
                    <% else %>
                      <.icon name="hero-pencil-square" class="w-4 h-4" /> Korrigieren
                    <% end %>
                  </.link>
                </div>
              </div>
            </th>
            <td :for={submission <- @submissions} class="px-2 py-3 text-center">
              <div
                class="tooltip tooltip-delayed"
                data-tip={"#{submission.firstname} #{submission.lastname}: #{part.label} ansehen"}
              >
                <.link
                  navigate={~p"/exams/#{@exam}/correction/#{submission.id}/parts/#{part.id}"}
                  data-corrected={to_string(part.id in (submission.corrected_parts || []))}
                  class="inline-flex items-center justify-center gap-1 h-8 min-w-[3.5rem] px-2 rounded-md transition-all duration-150 hover:bg-white hover:shadow-[0_0_0_1px_var(--color-stone-200)]"
                >
                  <%= if part.id in (submission.corrected_parts || []) do %>
                    <.icon name="hero-check-circle-solid" class="w-4 h-4 text-green-500 shrink-0" />
                  <% else %>
                    <span class="w-3.5 h-3.5 rounded-full border-2 border-dashed border-stone-300 shrink-0">
                    </span>
                  <% end %>
                  <span
                    :if={is_number((submission.points_per_part || %{})[part.id])}
                    class="font-mono text-xs font-semibold text-stone-600 tabular-nums"
                  >
                    {format_points(submission.points_per_part[part.id])}
                  </span>
                </.link>
              </div>
            </td>
          </tr>
        </tbody>
        <tfoot class="border-t-2 border-stone-200">
          <tr class="bg-stone-50">
            <th
              scope="row"
              class="sticky left-0 z-10 bg-stone-50 px-6 py-3 border-r border-stone-200 text-xs font-semibold text-stone-500 uppercase tracking-wide"
            >
              Total
              <span class="normal-case font-normal">(max. {format_points(@total_max_points)})</span>
            </th>
            <td
              :for={submission <- @submissions}
              id={"correction-total-#{submission.id}"}
              class="px-2 py-3 text-center font-mono text-sm font-semibold text-stone-700 tabular-nums"
            >
              {format_points(total_points(submission))}
            </td>
          </tr>
          <tr :if={@has_upload_fields} class="bg-stone-50 border-t border-stone-100">
            <th
              scope="row"
              class="sticky left-0 z-10 bg-stone-50 px-6 py-3 border-r border-stone-200 text-xs font-semibold text-stone-500 uppercase tracking-wide"
            >
              Dateien
            </th>
            <td :for={submission <- @submissions} class="px-2 py-3">
              <div class="flex flex-col items-center gap-1">
                <%= case Map.get(@submission_files, submission.id, []) do %>
                  <% [] -> %>
                    <span class="text-xs text-stone-300">—</span>
                  <% files -> %>
                    <div
                      :for={file <- files}
                      class="tooltip tooltip-delayed"
                      data-tip={"#{file.upload_field.label}: #{file.original_name} herunterladen"}
                    >
                      <a
                        href={~p"/exams/#{@exam.id}/submissions/#{submission.id}/files/#{file.id}"}
                        target="_blank"
                        rel="noopener"
                        class="inline-flex rounded transition-transform duration-150 hover:scale-110"
                      >
                        <.file_badge filename={file.stored_filename} size="sm" />
                      </a>
                    </div>
                <% end %>
              </div>
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  defp render_part_status(%{status: :done} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5 text-xs font-semibold text-green-700 bg-green-50 border border-green-200 rounded-full px-2.5 py-1">
      <.icon name="hero-check-badge" class="w-4 h-4" /> Erledigt
    </span>
    """
  end

  defp render_part_status(%{status: :partial} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5 text-xs font-semibold text-amber-700 bg-amber-50 border border-amber-200 rounded-full px-2.5 py-1 tabular-nums">
      <.icon name="hero-clock" class="w-4 h-4" /> {@done}/{@total}
    </span>
    """
  end

  defp render_part_status(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5 text-xs font-semibold text-stone-500 bg-stone-50 border border-stone-200 rounded-full px-2.5 py-1">
      <span class="w-2 h-2 rounded-full bg-stone-300"></span> Offen
    </span>
    """
  end

  defp max_points_label(exam, part) do
    case Map.get(exam.sample_solution_points || %{}, part.id, 0) do
      n when n == 1 -> "1 Punkt"
      n -> "#{format_points(n)} Punkte"
    end
  end

  defp participant_tip(submission) do
    name = "#{submission.firstname} #{submission.lastname}"
    if submission.submitted, do: name, else: "#{name} (nicht abgegeben)"
  end

  defp part_status(done_counts, part, submissions) do
    case Map.get(done_counts, part.id, 0) do
      0 -> :open
      n when n >= length(submissions) -> :done
      _ -> :partial
    end
  end

  # A free-document exam has one part and no grouped view to jump into, so it
  # keeps the list of participants with their files and points.
  defp render_by_participant(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-left border-collapse">
        <thead>
          <tr class="bg-stone-50 border-b border-stone-100">
            <th class="px-6 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide">
              Teilnehmer:in
            </th>
            <th class="px-4 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide">
              Punkte
            </th>
            <th
              :if={@has_upload_fields}
              class="px-4 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide"
            >
              Dateien
            </th>
            <th
              :for={part <- @parts}
              scope="col"
              class="px-3 py-3 text-center text-xs font-semibold text-stone-500 uppercase tracking-wide min-w-[100px] max-w-[160px]"
            >
              <span
                class="line-clamp-2 text-[12px] font-semibold text-stone-700 normal-case tooltip tooltip-bottom tooltip-delayed"
                data-tip={part.label}
              >
                {part.label}
              </span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-stone-100">
          <%!-- Submission Rows --%>
          <tr :for={submission <- @submissions} class="group hover:bg-stone-50/50">
            <td class="px-6 py-3">
              <div class="flex items-center gap-3">
                <.participant_avatar person={submission} />
                <div class="min-w-0">
                  <p class="text-sm font-semibold text-stone-800 truncate">
                    {submission.firstname} {submission.lastname}
                  </p>
                  <p class="text-xs text-stone-400 mt-0.5">
                    <%= if submission.submitted do %>
                      <span class="text-purple-500 font-medium">Abgegeben</span>
                    <% else %>
                      <span class="text-stone-400">Nicht abgegeben</span>
                    <% end %>
                  </p>
                </div>
              </div>
            </td>
            <td class="px-4 py-3">
              <span class="font-mono text-sm font-semibold text-stone-700">
                {format_points(total_points(submission))}
                <span class="text-stone-400 font-normal">
                  / {format_points(@total_max_points)}
                </span>
              </span>
            </td>
            <td :if={@has_upload_fields} class="px-4 py-3">
              <%= case Map.get(@submission_files, submission.id, []) do %>
                <% [] -> %>
                  <span class="text-xs text-stone-300">—</span>
                <% files -> %>
                  <div class="flex flex-col gap-1">
                    <div
                      :for={file <- files}
                      class="tooltip tooltip-right tooltip-delayed w-fit max-w-56"
                      data-tip={"#{file.original_name} herunterladen"}
                    >
                      <a
                        href={~p"/exams/#{@exam.id}/submissions/#{submission.id}/files/#{file.id}"}
                        target="_blank"
                        rel="noopener"
                        class="group flex items-center gap-1.5 min-w-0"
                      >
                        <.file_badge filename={file.stored_filename} size="sm" />
                        <span class="text-xs font-medium text-stone-600 truncate group-hover:text-sky-700 transition-colors duration-150">
                          {file.upload_field.label}
                        </span>
                        <.icon
                          name="hero-arrow-down-tray"
                          class="w-3.5 h-3.5 text-stone-300 group-hover:text-sky-600 shrink-0 transition-colors duration-150"
                        />
                      </a>
                    </div>
                  </div>
              <% end %>
            </td>
            <td :for={part <- @parts} class="px-3 py-3">
              <div class="flex items-center justify-center gap-2">
                <div
                  class="w-9 h-9 flex items-center justify-center shrink-0 tooltip tooltip-delayed"
                  data-tip={"#{part.label} ansehen"}
                >
                  <.link
                    navigate={~p"/exams/#{@exam}/correction/#{submission.id}/parts/#{part.id}"}
                    class="inline-flex items-center justify-center w-9 h-9 rounded-lg text-stone-500 border border-stone-200 opacity-0 group-hover:opacity-100 focus:opacity-100 transition-all duration-150 hover:bg-stone-100 hover:text-stone-700 hover:border-stone-300"
                  >
                    <.icon name="hero-eye" class="w-4 h-4" />
                  </.link>
                </div>
                <div class="w-9 h-9 flex items-center justify-center shrink-0">
                  <%= if part.id in (submission.auto_corrected_parts || []) do %>
                    <div
                      class="tooltip tooltip-delayed"
                      data-tip="Automatisch korrigiert"
                    >
                      <span class="inline-flex items-center justify-center w-7 h-7 rounded-full bg-purple-50 text-purple-500">
                        <.icon name="hero-sparkles" class="w-5 h-5" />
                      </span>
                    </div>
                  <% end %>
                </div>
                <div class="w-9 h-9 flex items-center justify-center shrink-0">
                  <%= if part.id in submission.corrected_parts do %>
                    <div class="tooltip tooltip-delayed" data-tip="Als erledigt markiert">
                      <span class="inline-flex items-center justify-center w-7 h-7 rounded-full bg-green-50 text-green-600">
                        <.icon name="hero-check-badge" class="w-5 h-5" />
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp render_auto_correction_progress(assigns) do
    {:running, %{done: done, total: total}} = assigns.bulk_status
    assigns = assign(assigns, done: done, total: total)

    ~H"""
    <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-5 mb-4">
      <div class="flex items-center gap-3 mb-3">
        <span class="relative flex h-2.5 w-2.5 shrink-0">
          <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75">
          </span>
          <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-amber-500"></span>
        </span>
        <p class="text-sm font-medium text-stone-700 animate-pulse">
          Auto-Korrektur läuft…
        </p>
        <p class="text-xs font-normal text-stone-500 tabular-nums ml-auto">
          <span class="font-semibold text-stone-700">{@done}</span>
          / <span class="font-semibold text-stone-700">{@total}</span>
        </p>
      </div>
      <div class="h-1.5 w-full bg-stone-100 rounded-full overflow-hidden">
        <div
          class="h-full bg-amber-500 transition-all duration-500 ease-out"
          style={"width: #{progress_percent(@done, @total)}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    if connected?(socket) do
      Exams.subscribe_correction(exam.id)
    end

    parts = Exams.split_content_into_parts(exam.content || %{}, exam.answer_mode)
    submissions = load_sorted_submissions(exam)

    submission_files =
      exam
      |> Exams.list_exam_submission_files()
      |> Enum.group_by(& &1.exam_submission_id)

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Korrektur")
     |> assign(:exam, exam)
     |> assign(:free_document, Exams.free_document?(exam))
     |> assign(:parts, parts)
     |> assign_progress(submissions)
     |> assign(:bulk_status, :idle)
     |> assign(:has_upload_fields, Exams.list_upload_fields(exam) != [])
     |> assign(:submission_files, submission_files)
     |> assign(:total_max_points, total_max_points(exam))}
  end

  @impl true
  def handle_info({:submission_corrected_parts_changed, submission}, socket) do
    submissions =
      Enum.map(socket.assigns.submissions, fn s ->
        if s.id == submission.id, do: submission, else: s
      end)

    {:noreply, assign_progress(socket, submissions)}
  end

  def handle_info({:bulk_correction_progress, %{done: done, total: total}}, socket) do
    {:noreply, assign(socket, :bulk_status, {:running, %{done: done, total: total}})}
  end

  def handle_info({:bulk_correction_done, %{total: total, errors: errors}}, socket) do
    submissions = load_sorted_submissions(socket.assigns.exam)

    socket =
      socket
      |> assign(:bulk_status, :idle)
      |> assign_progress(submissions)

    cond do
      # A crashed run reports no jobs but a non-empty error list; without this
      # branch it would clear the progress bar and say nothing at all, leaving
      # the teacher believing the exam had been corrected.
      total == 0 and errors != [] ->
        {:noreply,
         put_flash(socket, :error, "Auto-Korrektur fehlgeschlagen. Bitte erneut versuchen.")}

      total == 0 ->
        {:noreply, socket}

      errors == [] ->
        {:noreply, put_flash(socket, :info, "Auto-Korrektur abgeschlossen (#{total}).")}

      true ->
        {:noreply,
         put_flash(
           socket,
           :info,
           "Auto-Korrektur abgeschlossen: #{total - length(errors)}/#{total} ok, #{length(errors)} fehlgeschlagen."
         )}
    end
  end

  # All three delegate to `Tasky.Grading`, the single source of truth for
  # points math on screen and in the PDF. The local copies rendered 5.25 as
  # "5.3" — rounding away exactly the quarter-point precision the domain is
  # built on — and showed a genuine 0 as "—", i.e. indistinguishable from
  # ungraded.
  defp total_points(submission), do: Grading.sum_points(submission.points_per_part)

  defp total_max_points(exam), do: Grading.sum_points(exam.sample_solution_points)

  defp progress_percent(_done, 0), do: 0
  defp progress_percent(done, total), do: round(done * 100 / total)

  defp format_points(n), do: Grading.format_points(n)

  defp assign_progress(socket, submissions) do
    summary = correction_summary(socket.assigns.parts, submissions)

    socket
    |> assign(:submissions, submissions)
    |> assign(:summary, summary)
    |> assign(:done_counts, done_counts(socket.assigns.parts, submissions))
    |> assign(
      :resume_path,
      resume_path(socket.assigns.exam, socket.assigns.parts, submissions, summary)
    )
  end

  # "Korrektur fortsetzen" has to land on the part that is actually still open —
  # it used to always link to part 1, so continuing a half-corrected exam threw
  # the teacher back to the beginning.
  #
  # A free-document exam has a single part and no answer fields, so the grouped
  # view ("Korrektur nach Frage") has nothing to group and would only show
  # "Keine Antwortfelder in diesem Teil." There the resume link goes straight to
  # the submission the teacher still has to read.
  defp resume_path(exam, parts, submissions, summary) do
    if Exams.free_document?(exam) do
      case {summary.first_uncorrected, submissions} do
        {{submission, part}, _} -> ~p"/exams/#{exam}/correction/#{submission.id}/parts/#{part.id}"
        {nil, [s | _]} -> ~p"/exams/#{exam}/correction/#{s.id}/parts/#{hd(parts).id}"
        {nil, []} -> ~p"/exams/#{exam}/correction"
      end
    else
      ~p"/exams/#{exam}/correction/bulk/#{resume_part_id(parts, summary)}"
    end
  end

  defp resume_part_id([], _summary), do: nil

  defp resume_part_id(_parts, %{first_uncorrected: {_submission, part}}), do: part.id
  defp resume_part_id(parts, _summary), do: hd(parts).id

  defp correction_summary(parts, submissions) do
    total = length(parts) * length(submissions)

    corrected =
      Enum.reduce(submissions, 0, fn s, acc ->
        done = MapSet.new(s.corrected_parts || [])
        acc + Enum.count(parts, fn p -> p.id in done end)
      end)

    any_auto = Enum.any?(submissions, fn s -> (s.auto_corrected_parts || []) != [] end)
    manual_started = Enum.any?(submissions, fn s -> (s.corrected_parts || []) != [] end)
    first_uncorrected = find_first_uncorrected(parts, submissions)
    percent = if total == 0, do: 0, else: round(corrected * 100 / total)

    %{
      total: total,
      corrected: corrected,
      percent: percent,
      any_auto: any_auto,
      manual_started: manual_started,
      first_uncorrected: first_uncorrected
    }
  end

  defp done_counts(parts, submissions) do
    Map.new(parts, fn part ->
      {part.id, Enum.count(submissions, &(part.id in (&1.corrected_parts || [])))}
    end)
  end

  defp find_first_uncorrected(parts, submissions) do
    Enum.find_value(parts, fn part ->
      sub = Enum.find(submissions, fn s -> part.id not in (s.corrected_parts || []) end)
      if sub, do: {sub, part}, else: nil
    end)
  end

  defp load_sorted_submissions(exam) do
    exam
    |> Exams.list_exam_submissions()
    |> Enum.sort_by(fn s ->
      {String.downcase(s.firstname || ""), String.downcase(s.lastname || "")}
    end)
  end
end
