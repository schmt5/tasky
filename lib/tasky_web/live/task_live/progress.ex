defmodule TaskyWeb.TaskLive.Progress do
  @moduledoc """
  Teacher view of one learning unit's progress: a per-student status grid and
  a review modal showing the student's answer doc (read-only), their uploaded
  files, the feedback field and the approve / send-back verdict actions.
  """
  use TaskyWeb, :live_view

  import TaskyWeb.FileComponents

  alias Tasky.Courses
  alias Tasky.Tasks
  alias Tasky.Uploads

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/progress/#{@task.id}"}
    >
      <%!-- Page Header --%>
      <div class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-7xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Kurse", navigate: ~p"/courses"},
              %{label: @task.course.name, navigate: ~p"/courses/#{@task.course_id}"},
              %{label: "Fortschritt", navigate: ~p"/courses/#{@task.course_id}/progress"},
              %{label: @task.name}
            ]} />
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button
              navigate={~p"/courses/#{@task.course_id}/progress"}
              tooltip="Zurück zum Fortschritt"
            />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              {@task.name}
            </h1>
          </div>

          <p class="text-[15px] text-stone-500 leading-[1.7]">
            Übersicht über den Fortschritt aller Lernenden für diese Aufgabe
          </p>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-8 pb-8">
        <%!-- Progress Grid --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <%= if @has_data do %>
            <div class="overflow-x-auto">
              <div class="inline-block min-w-full align-middle">
                <table class="min-w-full divide-y divide-stone-200">
                  <thead class="bg-stone-50">
                    <tr>
                      <th
                        scope="col"
                        class="sticky left-0 z-10 bg-stone-50 px-6 py-4 text-left text-xs font-semibold text-stone-700 uppercase tracking-wider border-r border-stone-200"
                      >
                        <button
                          type="button"
                          phx-click="toggle_anonymize"
                          class="inline-flex items-center gap-2 px-2 py-1 rounded-lg hover:bg-stone-200 transition-colors"
                          title={
                            if @anonymized,
                              do: "Namen anzeigen",
                              else: "Namen ausblenden"
                          }
                        >
                          <.icon
                            name={if @anonymized, do: "hero-eye-slash", else: "hero-eye"}
                            class="w-4 h-4 text-stone-600"
                          />
                          <span class="text-xs font-semibold text-stone-700 uppercase tracking-wider">
                            Lernende
                          </span>
                        </button>
                      </th>

                      <th
                        scope="col"
                        class="px-4 py-4 text-center text-xs font-semibold text-stone-700 uppercase tracking-wider min-w-[140px]"
                      >
                        Fortschritt
                      </th>

                      <th
                        scope="col"
                        class="px-4 py-4 text-center text-xs font-semibold text-stone-700 uppercase tracking-wider min-w-[140px]"
                      >
                        Antworten
                      </th>
                    </tr>
                  </thead>

                  <tbody class="bg-white divide-y divide-stone-100">
                    <tr
                      :for={{student, index} <- Enum.with_index(@students)}
                      class="hover:bg-stone-50 transition-colors duration-150"
                    >
                      <td class="sticky left-0 z-10 bg-white px-6 py-4 whitespace-nowrap border-r border-stone-200">
                        <div class="flex items-center gap-3">
                          <div class="w-8 h-8 rounded-full flex items-center justify-center shrink-0 bg-sky-100 text-sky-700 text-[11px] font-semibold">
                            {if @anonymized, do: "?", else: initials(student)}
                          </div>
                          <span class="text-[14px] font-medium text-stone-800">
                            {if @anonymized,
                              do: "Lernende #{index + 1}",
                              else: get_student_full_name(student)}
                          </span>
                        </div>
                      </td>

                      <td class="px-4 py-4">
                        <div class="flex justify-center">
                          <.status_cell status={submission_status(@progress_map, student.id)} />
                        </div>
                      </td>

                      <td class="px-4 py-4">
                        <div class="flex justify-center">
                          <%= if has_submission?(@progress_map, student.id) do %>
                            <button
                              type="button"
                              phx-click="show_submission"
                              phx-value-student-id={student.id}
                              class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-emerald-500 text-white text-[12px] font-semibold rounded-[6px] hover:bg-emerald-600 transition-colors duration-150"
                            >
                              <.icon name="hero-document-text" class="w-3.5 h-3.5" /> Anzeigen
                            </button>
                          <% else %>
                            <span class="text-[12px] text-stone-400">-</span>
                          <% end %>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
            <%!-- Legend --%>
            <div class="border-t border-stone-200 bg-stone-50 px-6 py-4">
              <div class="flex items-center justify-center gap-8 flex-wrap">
                <.legend_item status={:not_started} />
                <.legend_item status={:in_progress} />
                <.legend_item status={:completed} />
                <.legend_item status={:review_denied} />
                <.legend_item status={:in_revision} />
                <.legend_item status={:review_approved} />
              </div>
            </div>
          <% else %>
            <div class="flex flex-col items-center text-center px-8 py-16">
              <div class="w-14 h-14 rounded-[14px] bg-emerald-50 flex items-center justify-center text-emerald-400 mb-5">
                <.icon name="hero-chart-bar" class="w-6 h-6" />
              </div>

              <h3 class="text-base font-semibold text-stone-700 mb-2">Keine Daten verfügbar</h3>

              <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6]">
                Schreiben Sie Lernende in den Kurs ein, um den Fortschritt zu verfolgen.
              </p>
            </div>
          <% end %>
        </div>
        <%!-- Submission Modal --%>
        <%= if @show_modal do %>
          <dialog
            id="submission-modal"
            class="modal modal-open"
            phx-window-keydown="close_modal"
            phx-key="escape"
          >
            <%!-- Modal backdrop --%>
            <div class="modal-backdrop bg-stone-900/50" phx-click="close_modal"></div>
            <%!-- Modal box --%>
            <div class="modal-box w-[96vw] max-w-[96vw] h-[94vh] max-h-[94vh] p-0 bg-white rounded-[16px] shadow-2xl flex flex-col">
              <%!-- Modal Header --%>
              <div class="bg-white border-b border-stone-200 px-6 py-4">
                <div class="flex items-center gap-3">
                  <%!-- Avatar --%>
                  <div class="w-10 h-10 rounded-full bg-emerald-100 flex items-center justify-center shrink-0">
                    <.icon name="hero-document-check" class="w-5 h-5 text-emerald-600" />
                  </div>
                  <%!-- Student info --%>
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2.5">
                      <h3 class="text-[18px] font-semibold text-stone-900 truncate leading-tight">
                        {@selected_student_name}
                      </h3>
                      <.status_badge
                        :if={@selected_submission_record}
                        status={@selected_submission_record.status}
                      />
                    </div>
                    <%= if @selected_student_email do %>
                      <p class="text-[12px] text-stone-500 truncate">{@selected_student_email}</p>
                    <% end %>
                    <%= if @selected_submission_record && @selected_submission_record.completed_at do %>
                      <p class="text-[11px] text-stone-400 mt-0.5">
                        Eingereicht am: {format_datetime(@selected_submission_record.completed_at)}
                      </p>
                    <% end %>
                  </div>
                  <%!-- Compact nav group --%>
                  <%= if length(@students_with_submissions) > 1 do %>
                    <% current_nav_index =
                      Enum.find_index(@students_with_submissions, &(&1.id == @selected_student_id)) %>
                    <div class="flex items-center gap-1 bg-stone-100 rounded-[8px] px-1 py-1 shrink-0">
                      <button
                        type="button"
                        phx-click="navigate_submission"
                        phx-value-direction="prev"
                        disabled={current_nav_index == 0}
                        class={[
                          "inline-flex items-center justify-center w-7 h-7 rounded-[6px] transition-colors duration-150",
                          if(current_nav_index == 0,
                            do: "text-stone-300 cursor-not-allowed",
                            else: "text-stone-600 hover:bg-white hover:shadow-sm hover:text-stone-900"
                          )
                        ]}
                      >
                        <.icon name="hero-chevron-left" class="w-4 h-4" />
                      </button>
                      <span class="text-[12px] font-semibold text-stone-500 tabular-nums px-1 select-none">
                        {current_nav_index + 1}/{length(@students_with_submissions)}
                      </span>
                      <button
                        type="button"
                        phx-click="navigate_submission"
                        phx-value-direction="next"
                        disabled={current_nav_index == length(@students_with_submissions) - 1}
                        class={[
                          "inline-flex items-center justify-center w-7 h-7 rounded-[6px] transition-colors duration-150",
                          if(current_nav_index == length(@students_with_submissions) - 1,
                            do: "text-stone-300 cursor-not-allowed",
                            else: "text-stone-600 hover:bg-white hover:shadow-sm hover:text-stone-900"
                          )
                        ]}
                      >
                        <.icon name="hero-chevron-right" class="w-4 h-4" />
                      </button>
                    </div>
                  <% end %>
                  <%!-- Close button --%>
                  <button
                    type="button"
                    phx-click="close_modal"
                    class="shrink-0 text-stone-400 hover:text-stone-600 transition-colors"
                  >
                    <.icon name="hero-x-mark" class="w-5 h-5" />
                  </button>
                </div>
              </div>
              <%!-- Modal Body --%>
              <div class="px-8 py-6 flex-1 overflow-y-auto bg-stone-50">
                <%= if @selected_submission_record do %>
                  <div class="max-w-4xl mx-auto space-y-6">
                    <%!-- Answer doc (read-only) --%>
                    <%= if @answers_json do %>
                      <div class="bg-white rounded-[14px] border border-stone-200">
                        <div
                          id={"submission-viewer-#{@selected_submission_record.id}"}
                          phx-hook="ExamReadOnlyViewer"
                          phx-update="ignore"
                          data-content={@answers_json}
                        >
                        </div>
                      </div>
                    <% else %>
                      <div class="bg-white border border-stone-200 rounded-[12px] p-8 text-center">
                        <div class="w-12 h-12 rounded-full bg-stone-100 flex items-center justify-center mx-auto mb-3">
                          <.icon name="hero-document" class="w-6 h-6 text-stone-400" />
                        </div>
                        <p class="text-[14px] text-stone-600">
                          Noch keine Antworten erfasst
                        </p>
                      </div>
                    <% end %>

                    <%!-- Uploaded files --%>
                    <div
                      :if={@submission_files != []}
                      class="bg-white rounded-[14px] border border-stone-200 p-6"
                    >
                      <div class="flex items-center gap-2.5 mb-4">
                        <.icon name="hero-arrow-up-tray" class="w-5 h-5 text-sky-500" />
                        <h4 class="text-base font-semibold text-stone-800">Datei-Abgaben</h4>
                      </div>
                      <div class="space-y-2.5">
                        <div
                          :for={%{field: field, file: file} <- @submission_files}
                          class="flex items-center gap-4 rounded-xl border border-stone-200 px-4 py-3"
                        >
                          <.file_badge :if={file} filename={file.stored_filename} />
                          <div class="flex-1 min-w-0">
                            <p class="text-sm font-semibold text-stone-800 truncate">
                              {(file && file.original_name) || "—"}
                            </p>
                            <p class="text-xs text-stone-400 mt-0.5">
                              {field.label}
                              <span :if={field.required} class="text-amber-600">· Pflicht</span>
                              <span :if={file}> ·  {Uploads.format_size(file.size)}</span>
                            </p>
                          </div>
                          <a
                            :if={file}
                            href={
                              ~p"/tasks/#{@task.id}/submissions/#{@selected_submission_record.id}/files/#{file.id}"
                            }
                            target="_blank"
                            rel="noopener"
                            class="inline-flex items-center gap-2 border border-stone-200 text-stone-600 text-sm font-semibold px-3.5 py-2 rounded-lg transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 shrink-0"
                          >
                            <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Herunterladen
                          </a>
                          <span :if={!file} class="text-[12px] text-stone-400 italic shrink-0">
                            Nicht hochgeladen
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
              <%!-- Modal Footer: Feedback + Verdict --%>
              <div class="bg-stone-50 px-8 py-5 border-t border-stone-200">
                <div class="max-w-4xl mx-auto">
                  <div class="flex items-center gap-2 mb-3">
                    <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4 text-stone-500" />
                    <span class="text-[13px] font-semibold text-stone-700">
                      Feedback an Lernende
                    </span>
                    <%= if @feedback_saved do %>
                      <span class="inline-flex items-center gap-1 text-[12px] font-medium text-emerald-600 ml-1">
                        <.icon name="hero-check-circle" class="w-3.5 h-3.5" /> Gespeichert
                      </span>
                    <% end %>
                  </div>
                  <.form
                    for={@feedback_form}
                    id={"feedback-form-#{@selected_student_id}"}
                    phx-submit="save_feedback"
                  >
                    <.input
                      type="textarea"
                      field={@feedback_form[:feedback]}
                      placeholder="Schreibe hier dein Feedback für die/den Lernende/n..."
                      rows="3"
                      maxlength={Tasks.max_feedback_chars()}
                      class="w-full text-[13px] text-stone-800 bg-white border border-stone-200 rounded-[8px] px-3 py-2 resize-none focus:outline-none focus:ring-2 focus:ring-emerald-400 focus:border-transparent placeholder:text-stone-300 transition"
                    />
                    <div class="flex items-center justify-between gap-3 mt-3 flex-wrap">
                      <div class="flex items-center gap-2">
                        <button
                          type="submit"
                          name="verdict"
                          value="review_denied"
                          data-confirm="Aufgabe zur Überarbeitung an die/den Lernende/n zurückgeben?"
                          class="inline-flex items-center gap-1.5 px-4 py-2 bg-white border border-rose-200 text-rose-600 text-[13px] font-semibold rounded-[8px] hover:bg-rose-50 transition-colors"
                        >
                          <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" /> Zurückgeben
                        </button>
                        <button
                          type="submit"
                          name="verdict"
                          value="review_approved"
                          class="inline-flex items-center gap-1.5 px-4 py-2 bg-white border border-emerald-300 text-emerald-700 text-[13px] font-semibold rounded-[8px] hover:bg-emerald-50 transition-colors"
                        >
                          <.icon name="hero-check-badge" class="w-3.5 h-3.5" /> Genehmigen
                        </button>
                      </div>
                      <div class="flex items-center gap-3">
                        <button
                          type="button"
                          phx-click="close_modal"
                          class="px-4 py-2 text-[13px] font-medium text-stone-600 hover:text-stone-900 transition-colors"
                        >
                          Schliessen
                        </button>
                        <button
                          type="submit"
                          class="inline-flex items-center gap-1.5 px-4 py-2 bg-emerald-500 text-white text-[13px] font-semibold rounded-[8px] hover:bg-emerald-600 transition-colors shadow-sm"
                        >
                          <.icon name="hero-paper-airplane" class="w-3.5 h-3.5" /> Feedback speichern
                        </button>
                      </div>
                    </div>
                  </.form>
                </div>
              </div>
            </div>
          </dialog>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true

  defp status_cell(assigns) do
    assigns = assign(assigns, :meta, status_meta(assigns.status))

    ~H"""
    <div
      class={["w-10 h-10 rounded-[8px] flex items-center justify-center shadow-sm", @meta.bg]}
      title={@meta.label}
    >
      <.icon name={@meta.icon} class={["w-5 h-5", @meta.fg]} />
    </div>
    """
  end

  attr :status, :atom, required: true

  defp legend_item(assigns) do
    assigns = assign(assigns, :meta, status_meta(assigns.status))

    ~H"""
    <div class="flex items-center gap-2">
      <div class={["w-6 h-6 rounded-[6px] flex items-center justify-center", @meta.bg]}>
        <.icon name={@meta.icon} class={["w-4 h-4", @meta.fg]} />
      </div>
      <span class="text-[13px] text-stone-600">{@meta.label}</span>
    </div>
    """
  end

  attr :status, :string, required: true

  defp status_badge(assigns) do
    assigns = assign(assigns, :meta, status_meta(status_atom(assigns.status)))

    ~H"""
    <span class={[
      "inline-flex items-center gap-1 text-[11px] font-semibold px-2.5 py-0.5 rounded-full whitespace-nowrap",
      @meta.badge
    ]}>
      {@meta.label}
    </span>
    """
  end

  defp status_meta(:review_approved),
    do: %{
      label: "Genehmigt",
      icon: "hero-check-badge",
      bg: "bg-emerald-500",
      fg: "text-white",
      badge: "bg-emerald-100 text-emerald-700"
    }

  defp status_meta(:completed),
    do: %{
      label: "Wartet auf Review",
      icon: "hero-inbox-arrow-down",
      bg: "bg-amber-400",
      fg: "text-white",
      badge: "bg-amber-100 text-amber-700"
    }

  defp status_meta(:review_denied),
    do: %{
      label: "Zurückgegeben",
      icon: "hero-arrow-uturn-left",
      bg: "bg-rose-400",
      fg: "text-white",
      badge: "bg-rose-100 text-rose-700"
    }

  defp status_meta(:in_revision),
    do: %{
      label: "In Überarbeitung",
      icon: "hero-pencil-square",
      bg: "bg-amber-500",
      fg: "text-white",
      badge: "bg-amber-100 text-amber-700"
    }

  defp status_meta(:in_progress),
    do: %{
      label: "In Bearbeitung",
      icon: "hero-ellipsis-horizontal",
      bg: "bg-sky-500",
      fg: "text-white",
      badge: "bg-sky-100 text-sky-700"
    }

  defp status_meta(:not_started),
    do: %{
      label: "Nicht begonnen",
      icon: "hero-minus",
      bg: "bg-stone-200",
      fg: "text-stone-400",
      badge: "bg-stone-100 text-stone-500"
    }

  defp status_atom("completed"), do: :completed
  defp status_atom("review_approved"), do: :review_approved
  defp status_atom("review_denied"), do: :review_denied
  defp status_atom("in_revision"), do: :in_revision
  defp status_atom("in_progress"), do: :in_progress
  defp status_atom(_), do: :not_started

  @impl true
  def mount(%{"task_id" => task_id}, _session, socket) do
    task = Tasks.get_task_with_course!(socket.assigns.current_scope, task_id)

    # Subscribe to real-time progress updates for this task's course
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tasky.PubSub, "course:#{task.course_id}:progress")
    end

    students = Courses.list_enrolled_students(task.course_id)

    progress_map = build_progress_map(task.id, students)

    has_data = students != []

    {:ok,
     socket
     |> assign(:page_title, "Fortschritt - #{task.name}")
     |> assign(:task, task)
     |> assign(:upload_fields, Tasks.list_task_upload_fields(task))
     |> assign(:students, students)
     |> assign(:progress_map, progress_map)
     |> assign(:has_data, has_data)
     |> assign(:anonymized, false)
     |> reset_modal_assigns()}
  end

  @impl true
  def handle_info({:submission_updated, updated_submission}, socket) do
    # Only rebuild if the update is for this task
    if updated_submission.task_id == socket.assigns.task.id do
      progress_map = build_progress_map(socket.assigns.task.id, socket.assigns.students)
      {:noreply, assign(socket, :progress_map, progress_map)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_anonymize", _params, socket) do
    {:noreply, assign(socket, :anonymized, !socket.assigns.anonymized)}
  end

  def handle_event("show_submission", %{"student-id" => student_id}, socket) do
    student_id = TaskyWeb.Params.int(student_id)
    student = Enum.find(socket.assigns.students, &(&1.id == student_id))

    if student do
      students_with_submissions =
        Enum.filter(socket.assigns.students, fn s ->
          has_submission?(socket.assigns.progress_map, s.id)
        end)

      {:noreply,
       socket
       |> assign(:show_modal, true)
       |> assign(:students_with_submissions, students_with_submissions)
       |> select_student(student)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "save_feedback",
        %{"submission" => %{"feedback" => feedback_text}} = params,
        socket
      ) do
    case socket.assigns.selected_submission_record do
      nil ->
        {:noreply, put_flash(socket, :error, "Keine Einreichung gefunden")}

      record ->
        verdict = params["verdict"]
        scope = socket.assigns.current_scope

        result =
          case verdict do
            v when v in ["review_approved", "review_denied"] ->
              Tasks.review_submission(scope, record.id, v, %{feedback: feedback_text})

            _ ->
              Tasks.save_feedback(scope, record.id, %{feedback: feedback_text})
          end

        case {result, verdict} do
          # Ein Verdikt beendet das Review: Modal zu, Bestätigung als Flash.
          {{:ok, _updated}, verdict} when verdict in ["review_approved", "review_denied"] ->
            {:noreply,
             socket
             |> put_flash(:info, verdict_flash(verdict, socket.assigns.selected_student_name))
             |> assign(
               :progress_map,
               build_progress_map(socket.assigns.task.id, socket.assigns.students)
             )
             |> reset_modal_assigns()}

          {{:ok, updated}, _no_verdict} ->
            {:noreply,
             socket
             |> assign(:selected_submission_record, updated)
             |> assign(
               :feedback_form,
               to_form(%{"feedback" => updated.feedback || ""}, as: :submission)
             )
             |> assign(:feedback_saved, true)
             |> assign(
               :progress_map,
               build_progress_map(socket.assigns.task.id, socket.assigns.students)
             )}

          {{:error, reason}, _} ->
            {:noreply, put_flash(socket, :error, save_error_message(reason))}
        end
    end
  end

  def handle_event("navigate_submission", %{"direction" => direction}, socket) do
    students = socket.assigns.students_with_submissions
    current_id = socket.assigns.selected_student_id

    current_index = Enum.find_index(students, &(&1.id == current_id))

    next_index =
      case direction do
        "prev" -> current_index - 1
        "next" -> current_index + 1
        _ -> current_index
      end

    case Enum.at(students, next_index) do
      nil -> {:noreply, socket}
      next_student when next_index >= 0 -> {:noreply, select_student(socket, next_student)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, reset_modal_assigns(socket)}
  end

  # Private Functions

  defp verdict_flash("review_approved", name), do: "Lerneinheit von #{name} genehmigt"

  defp verdict_flash("review_denied", name),
    do: "Lerneinheit an #{name} zur Überarbeitung zurückgegeben"

  defp save_error_message(:unauthorized),
    do: "Du kannst diese Lerneinheit nicht beurteilen"

  defp save_error_message(:not_reviewable),
    do: "Diese Lerneinheit wurde noch nicht eingereicht"

  defp save_error_message(%Ecto.Changeset{} = changeset) do
    case changeset.errors[:feedback] do
      nil -> "Feedback konnte nicht gespeichert werden"
      _ -> "Feedback ist zu lang (max. #{Tasks.max_feedback_chars()} Zeichen)"
    end
  end

  defp save_error_message(_reason), do: "Feedback konnte nicht gespeichert werden"

  # Loads the selected student's submission incl. answer doc and files into
  # the modal assigns.
  defp select_student(socket, student) do
    task = socket.assigns.task
    submission = Tasks.get_submission_for_student(task.id, student.id)

    answers_json =
      case submission && submission.content do
        content when is_map(content) and map_size(content) > 0 -> Jason.encode!(content)
        _ -> nil
      end

    files_by_field =
      case submission do
        nil ->
          %{}

        submission ->
          submission |> Tasks.list_submission_files() |> Map.new(&{&1.upload_field_id, &1})
      end

    submission_files =
      Enum.map(socket.assigns.upload_fields, fn field ->
        %{field: field, file: Map.get(files_by_field, field.id)}
      end)

    socket
    |> assign(:selected_student_id, student.id)
    |> assign(:selected_student_name, get_student_full_name(student))
    |> assign(:selected_student_email, student.email)
    |> assign(:selected_submission_record, submission)
    |> assign(:answers_json, answers_json)
    |> assign(:submission_files, submission_files)
    |> assign(
      :feedback_form,
      to_form(%{"feedback" => (submission && submission.feedback) || ""}, as: :submission)
    )
    |> assign(:feedback_saved, false)
  end

  defp reset_modal_assigns(socket) do
    socket
    |> assign(:show_modal, false)
    |> assign(:selected_student_id, nil)
    |> assign(:selected_student_name, nil)
    |> assign(:selected_student_email, nil)
    |> assign(:selected_submission_record, nil)
    |> assign(:answers_json, nil)
    |> assign(:submission_files, [])
    |> assign(:students_with_submissions, [])
    |> assign(:feedback_form, to_form(%{"feedback" => ""}, as: :submission))
    |> assign(:feedback_saved, false)
  end

  defp build_progress_map(task_id, students) do
    student_ids = Enum.map(students, & &1.id)
    Tasks.get_progress_map_for_task(task_id, student_ids)
  end

  defp submission_status(progress_map, student_id) do
    case Map.get(progress_map, student_id) do
      %{status: status} -> status_atom(status)
      nil -> :not_started
    end
  end

  # A submission is worth opening once the student has typed answers,
  # uploaded files (implies a record) or completed the unit.
  defp has_submission?(progress_map, student_id) do
    case Map.get(progress_map, student_id) do
      %{has_content: true} -> true
      %{status: status} when status in ["completed", "review_approved", "review_denied"] -> true
      _ -> false
    end
  end

  defp get_email_username(email) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp get_email_username(_), do: ""

  defp get_student_full_name(student) do
    case {student.firstname, student.lastname} do
      {nil, nil} -> get_email_username(student.email)
      {"", ""} -> get_email_username(student.email)
      {first, nil} -> first
      {nil, last} -> last
      {"", last} -> last
      {first, ""} -> first
      {first, last} -> "#{first} #{last}"
    end
  end

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%d.%m.%Y um %H:%M Uhr")
  end

  defp format_datetime(_), do: "Unbekannt"
end
