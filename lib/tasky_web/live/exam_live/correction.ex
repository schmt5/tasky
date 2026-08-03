defmodule TaskyWeb.ExamLive.Correction do
  use TaskyWeb, :live_view

  import TaskyWeb.FileComponents

  alias Tasky.Exams

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
                class="inline-flex items-center gap-2 text-sm font-semibold text-white bg-gradient-to-r from-sky-500 to-indigo-500 hover:from-sky-600 hover:to-indigo-600 hover:shadow-md px-4 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 focus:outline-none focus:ring-4 focus:ring-sky-600 focus:ring-offset-2"
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
                  {@summary.corrected} / {@summary.total} Teile erledigt
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
              <.link
                navigate={~p"/exams/#{@exam}/correction/bulk/#{List.first(@parts).id}"}
                class="inline-flex items-center gap-2 text-sm font-semibold text-white bg-gradient-to-r from-green-500 to-emerald-500 hover:from-green-600 hover:to-emerald-600 hover:shadow-md px-4 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(34,197,94,0.25)] transition-all duration-150 focus:outline-none focus:ring-4 focus:ring-green-600 focus:ring-offset-2"
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
            <div class="overflow-x-auto">
              <table class="w-full text-left border-collapse">
                <thead>
                  <tr class="bg-stone-50 border-b border-stone-100">
                    <th class="px-6 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide">
                      Schüler/in
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
                        <div class="w-9 h-9 rounded-full bg-gradient-to-br from-blue-400 to-indigo-500 flex items-center justify-center text-white text-sm font-bold shadow-sm shrink-0">
                          {String.first(submission.firstname)}{String.first(submission.lastname)}
                        </div>
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
                                href={
                                  ~p"/exams/#{@exam.id}/submissions/#{submission.id}/files/#{file.id}"
                                }
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
                            navigate={
                              ~p"/exams/#{@exam}/correction/#{submission.id}/parts/#{part.id}"
                            }
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
          <% end %>
        </div>
      </div>
    </Layouts.app>
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
          class="h-full bg-gradient-to-r from-amber-400 to-orange-500 transition-all duration-500 ease-out"
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

    parts = Exams.split_content_into_parts(exam.content || %{})
    submissions = load_sorted_submissions(exam)

    submission_files =
      exam
      |> Exams.list_exam_submission_files()
      |> Enum.group_by(& &1.exam_submission_id)

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Korrektur")
     |> assign(:exam, exam)
     |> assign(:parts, parts)
     |> assign(:submissions, submissions)
     |> assign(:summary, correction_summary(parts, submissions))
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

    {:noreply,
     socket
     |> assign(:submissions, submissions)
     |> assign(:summary, correction_summary(socket.assigns.parts, submissions))}
  end

  def handle_info({:bulk_correction_progress, %{done: done, total: total}}, socket) do
    {:noreply, assign(socket, :bulk_status, {:running, %{done: done, total: total}})}
  end

  def handle_info({:bulk_correction_done, %{total: total, errors: errors}}, socket) do
    submissions = load_sorted_submissions(socket.assigns.exam)

    socket =
      socket
      |> assign(:bulk_status, :idle)
      |> assign(:submissions, submissions)
      |> assign(:summary, correction_summary(socket.assigns.parts, submissions))

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

  defp total_points(submission) do
    (submission.points_per_part || %{})
    |> Map.values()
    |> Enum.reduce(0, fn
      v, acc when is_number(v) -> acc + v
      _, acc -> acc
    end)
  end

  defp total_max_points(exam) do
    (exam.sample_solution_points || %{})
    |> Map.values()
    |> Enum.reduce(0, fn
      v, acc when is_number(v) -> acc + v
      _, acc -> acc
    end)
  end

  defp progress_percent(_done, 0), do: 0
  defp progress_percent(done, total), do: round(done * 100 / total)

  defp format_points(0), do: "—"
  defp format_points(n) when is_integer(n), do: Integer.to_string(n)

  defp format_points(n) when is_float(n) do
    if n == trunc(n),
      do: Integer.to_string(trunc(n)),
      else: :erlang.float_to_binary(n, decimals: 1)
  end

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
