defmodule TaskyWeb.TaskLive.Progress do
  use TaskyWeb, :live_view

  alias Tasky.Tasks
  alias Tasky.Courses
  alias Tasky.Repo
  alias Tasky.Tally.Client, as: TallyApi

  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-7xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-emerald-500">
              Aufgabenfortschritt
            </div>

            <div class="flex items-center gap-2">
              <.link
                navigate={~p"/courses/#{@task.course_id}/progress"}
                class="inline-flex items-center gap-1.5 text-[13px] font-semibold text-stone-600 hover:text-stone-900 transition-colors duration-150"
              >
                <.icon name="hero-arrow-left" class="w-4 h-4" /> Zurück zum Kursfortschritt
              </.link>
            </div>
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            {@task.name}
          </h1>

          <p class="text-[15px] text-stone-500 leading-[1.7]">
            Übersicht über den Fortschritt aller Studenten für diese Aufgabe
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
                        -
                      </th>

                      <th
                        :for={student <- @students}
                        scope="col"
                        class="px-4 py-4 text-center text-xs font-semibold text-stone-700 uppercase tracking-wider min-w-[120px]"
                      >
                        <div class="flex flex-col items-center gap-1">
                          <div class="w-8 h-8 rounded-full flex items-center justify-center shrink-0 bg-sky-100 text-sky-700 mx-auto mb-2 text-[11px] font-semibold">
                            {get_initials(student)}
                          </div>

                          <span class="line-clamp-2 text-[11px] text-stone-600">
                            {get_email_username(student.email)}
                          </span>
                        </div>
                      </th>
                    </tr>
                  </thead>

                  <tbody class="bg-white divide-y divide-stone-100">
                    <tr class="hover:bg-stone-50 transition-colors duration-150">
                      <td class="sticky left-0 z-10 bg-white group-hover:bg-stone-50 px-6 py-4 whitespace-nowrap border-r border-stone-200">
                        <div class="flex items-center gap-3">
                          <span class="text-[14px] font-medium text-stone-800">Fortschritt</span>
                        </div>
                      </td>

                      <td :for={student <- @students} class="px-4 py-4">
                        <div class="flex justify-center">
                          <%= case get_submission_status(@progress_map, student.id) do %>
                            <% :completed -> %>
                              <div
                                class="w-10 h-10 rounded-[8px] bg-emerald-500 flex items-center justify-center shadow-sm"
                                title="Abgeschlossen"
                              >
                                <.icon name="hero-check" class="w-5 h-5 text-white" />
                              </div>
                            <% :in_progress -> %>
                              <div
                                class="w-10 h-10 rounded-[8px] bg-sky-500 flex items-center justify-center shadow-sm"
                                title="In Bearbeitung"
                              >
                                <.icon name="hero-ellipsis-horizontal" class="w-5 h-5 text-white" />
                              </div>
                            <% :not_started -> %>
                              <div
                                class="w-10 h-10 rounded-[8px] bg-stone-200 flex items-center justify-center"
                                title="Nicht begonnen"
                              >
                                <.icon name="hero-minus" class="w-5 h-5 text-stone-400" />
                              </div>
                          <% end %>
                        </div>
                      </td>
                    </tr>
                    <%!-- Submission Actions Row --%>
                    <tr class="hover:bg-stone-50 transition-colors duration-150">
                      <td class="sticky left-0 z-10 bg-white group-hover:bg-stone-50 px-6 py-4 whitespace-nowrap border-r border-stone-200">
                        <div class="flex items-center gap-3">
                          <span class="text-[14px] font-medium text-stone-800">Antworten</span>
                        </div>
                      </td>

                      <td :for={student <- @students} class="px-4 py-4">
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
              <div class="flex items-center justify-center gap-8">
                <div class="flex items-center gap-2">
                  <div class="w-6 h-6 rounded-[6px] bg-emerald-500 flex items-center justify-center">
                    <.icon name="hero-check" class="w-4 h-4 text-white" />
                  </div>
                  <span class="text-[13px] text-stone-600">Abgeschlossen</span>
                </div>

                <div class="flex items-center gap-2">
                  <div class="w-6 h-6 rounded-[6px] bg-sky-500 flex items-center justify-center">
                    <.icon name="hero-ellipsis-horizontal" class="w-4 h-4 text-white" />
                  </div>
                  <span class="text-[13px] text-stone-600">In Bearbeitung</span>
                </div>

                <div class="flex items-center gap-2">
                  <div class="w-6 h-6 rounded-[6px] bg-stone-200 flex items-center justify-center">
                    <.icon name="hero-minus" class="w-4 h-4 text-stone-400" />
                  </div>
                  <span class="text-[13px] text-stone-600">Nicht begonnen</span>
                </div>
              </div>
            </div>
          <% else %>
            <div class="flex flex-col items-center text-center px-8 py-16">
              <div class="w-14 h-14 rounded-[14px] bg-emerald-50 flex items-center justify-center text-emerald-400 mb-5">
                <.icon name="hero-chart-bar" class="w-6 h-6" />
              </div>

              <h3 class="text-base font-semibold text-stone-700 mb-2">Keine Daten verfügbar</h3>

              <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6]">
                Schreiben Sie Studenten in den Kurs ein, um den Fortschritt zu verfolgen.
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
                    <h3 class="text-[18px] font-semibold text-stone-900 truncate leading-tight">
                      {@selected_student_name}
                    </h3>
                    <%= if @selected_student_email do %>
                      <p class="text-[12px] text-stone-500 truncate">{@selected_student_email}</p>
                    <% end %>
                    <%= if @submission_data do %>
                      <p class="text-[11px] text-stone-400 mt-0.5">
                        Eingereicht am: {format_datetime(@submission_data.submitted_at)}
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
              <div class="px-8 py-6 flex-1 overflow-y-auto">
                <%= if @loading_submission do %>
                  <div class="flex flex-col items-center justify-center py-12">
                    <div class="w-12 h-12 border-4 border-emerald-200 border-t-emerald-500 rounded-full animate-spin mb-4">
                    </div>

                    <p class="text-[14px] text-stone-500">Lade Einreichung...</p>
                  </div>
                <% else %>
                  <%= if @submission_error do %>
                    <div class="bg-red-50 border border-red-200 rounded-[12px] p-6 text-center">
                      <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-3">
                        <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
                      </div>

                      <h4 class="text-[16px] font-semibold text-red-900 mb-2">Fehler beim Laden</h4>

                      <p class="text-[14px] text-red-700">{@submission_error}</p>
                    </div>
                  <% else %>
                    <%= if @submission_data && @all_responses do %>
                      <%= if length(@all_responses) > 0 do %>
                        <div class="space-y-6">
                          <div :for={response <- @all_responses} class="space-y-2">
                            <%!-- Question Title --%>
                            <div class="text-[13px] font-semibold text-stone-700 uppercase tracking-wide">
                              {response.question_title}
                            </div>
                            <%!-- Answer based on type --%>
                            <%= cond do %>
                              <%!-- File Upload --%>
                              <% response.question_type == "FILE_UPLOAD" and is_list(response.answer) -> %>
                                <div class="space-y-3">
                                  <div
                                    :for={file <- response.answer}
                                    class="bg-white border border-stone-200 rounded-[10px] p-4 hover:border-stone-300 transition-colors"
                                  >
                                    <div class="flex items-center justify-between gap-4">
                                      <div class="flex items-center gap-3 flex-1 min-w-0">
                                        <div class="w-10 h-10 rounded-[8px] bg-stone-100 flex items-center justify-center shrink-0">
                                          <%= if String.starts_with?(file["mimeType"] || "", "image/") do %>
                                            <.icon name="hero-photo" class="w-5 h-5 text-stone-600" />
                                          <% else %>
                                            <.icon
                                              name="hero-document-text"
                                              class="w-5 h-5 text-stone-600"
                                            />
                                          <% end %>
                                        </div>

                                        <div class="flex-1 min-w-0">
                                          <p class="text-[14px] font-medium text-stone-900 truncate">
                                            {file["name"]}
                                          </p>

                                          <p class="text-[12px] text-stone-500">
                                            {format_file_size(file["size"])}
                                          </p>
                                        </div>
                                      </div>

                                      <a
                                        href={file["url"]}
                                        target="_blank"
                                        class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-stone-900 text-white text-[12px] font-medium rounded-[6px] hover:bg-stone-800 transition-colors shrink-0"
                                      >
                                        <.icon name="hero-arrow-down-tray" class="w-3.5 h-3.5" />
                                        Download
                                      </a>
                                    </div>
                                    <%!-- Image Preview --%>
                                    <%= if String.starts_with?(file["mimeType"] || "", "image/") do %>
                                      <div class="mt-3 rounded-[8px] overflow-hidden border border-stone-200 bg-stone-50">
                                        <img
                                          src={file["url"]}
                                          alt={file["name"]}
                                          class="w-full h-auto"
                                        />
                                      </div>
                                    <% end %>
                                  </div>
                                </div>
                                <%!-- Multiple Choice / Select --%>
                              <% response.question_type in ["MULTIPLE_CHOICE", "CHECKBOXES"] and is_list(response.answer) -> %>
                                <div class="bg-emerald-50 border border-emerald-200 rounded-[10px] px-4 py-3">
                                  <div class="flex flex-wrap gap-2">
                                    <span
                                      :for={item <- response.answer}
                                      class="inline-flex items-center gap-1.5 px-3 py-1 bg-white border border-emerald-300 rounded-full text-[13px] font-medium text-emerald-800"
                                    >
                                      <.icon name="hero-check-circle" class="w-4 h-4" /> {item}
                                    </span>
                                  </div>
                                </div>
                                <%!-- Text / Input answers --%>
                              <% is_binary(response.answer) -> %>
                                <div class="bg-stone-50 border border-stone-200 rounded-[10px] px-4 py-3">
                                  <p class="text-[14px] text-stone-800 whitespace-pre-wrap">
                                    {response.answer}
                                  </p>
                                </div>
                                <%!-- List of strings --%>
                              <% is_list(response.answer) -> %>
                                <div class="bg-stone-50 border border-stone-200 rounded-[10px] px-4 py-3">
                                  <ul class="list-disc list-inside space-y-1">
                                    <li
                                      :for={item <- response.answer}
                                      class="text-[14px] text-stone-800"
                                    >
                                      {inspect(item)}
                                    </li>
                                  </ul>
                                </div>
                                <%!-- Fallback for other types --%>
                              <% true -> %>
                                <div class="bg-stone-50 border border-stone-200 rounded-[10px] px-4 py-3">
                                  <p class="text-[14px] text-stone-800 font-mono">
                                    {inspect(response.answer)}
                                  </p>
                                </div>
                            <% end %>
                          </div>
                        </div>
                      <% else %>
                        <div class="bg-stone-50 border border-stone-200 rounded-[12px] p-8 text-center">
                          <div class="w-12 h-12 rounded-full bg-stone-200 flex items-center justify-center mx-auto mb-3">
                            <.icon name="hero-document" class="w-6 h-6 text-stone-400" />
                          </div>

                          <p class="text-[14px] text-stone-600">
                            Keine Antworten in dieser Einreichung
                          </p>
                        </div>
                      <% end %>
                    <% end %>
                  <% end %>
                <% end %>
              </div>
              <%!-- Modal Footer --%>
              <div class="bg-white px-8 py-4 border-t border-stone-200">
                <div class="flex justify-end">
                  <button
                    type="button"
                    phx-click="close_modal"
                    class="px-5 py-2 bg-stone-900 text-white text-[14px] font-medium rounded-[8px] hover:bg-stone-800 transition-colors"
                  >
                    Schließen
                  </button>
                </div>
              </div>
            </div>
          </dialog>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"task_id" => task_id}, _session, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, task_id) |> Repo.preload(:course)

    # Subscribe to real-time progress updates for this task's course
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tasky.PubSub, "course:#{task.course_id}:progress")
    end

    students = Courses.list_enrolled_students(task.course_id)

    progress_map = build_progress_map(task.id, students)

    has_data = length(students) > 0

    {:ok,
     socket
     |> assign(:page_title, "Fortschritt - #{task.name}")
     |> assign(:task, task)
     |> assign(:students, students)
     |> assign(:progress_map, progress_map)
     |> assign(:has_data, has_data)
     |> assign(:show_modal, false)
     |> assign(:loading_submission, false)
     |> assign(:submission_data, nil)
     |> assign(:submission_error, nil)
     |> assign(:file_uploads, [])
     |> assign(:all_responses, [])
     |> assign(:selected_student_id, nil)
     |> assign(:selected_student_name, nil)
     |> assign(:selected_student_email, nil)
     |> assign(:students_with_submissions, [])}
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

  def handle_info({:fetch_submission, student_id}, socket) do
    task = socket.assigns.task

    # Find the submission record to get tally_response_id
    submission =
      Repo.get_by(Tasks.TaskSubmission, student_id: student_id, task_id: task.id)

    socket =
      case submission do
        %{tally_response_id: tally_response_id} when not is_nil(tally_response_id) ->
          # Check if task has tally_form_id
          case task.tally_form_id do
            nil ->
              assign(socket,
                loading_submission: false,
                submission_error: "Kein Tally-Formular für diese Aufgabe konfiguriert"
              )

            form_id ->
              # Fetch from Tally API
              case TallyApi.fetch_submission(
                     socket.assigns.current_scope,
                     form_id,
                     tally_response_id
                   ) do
                {:ok, data} ->
                  metadata = TallyApi.extract_metadata(data)
                  files = TallyApi.extract_file_uploads(data)
                  all_responses = TallyApi.extract_all_responses(data)

                  assign(socket,
                    loading_submission: false,
                    submission_data: metadata,
                    file_uploads: files,
                    all_responses: all_responses,
                    submission_error: nil
                  )

                {:error, :not_found} ->
                  assign(socket,
                    loading_submission: false,
                    submission_error: "Einreichung wurde in Tally nicht gefunden"
                  )

                {:error, :unauthorized} ->
                  assign(socket,
                    loading_submission: false,
                    submission_error:
                      "Nicht autorisiert. Bitte überprüfen Sie Ihren Tally API-Schlüssel"
                  )

                {:error, :api_key_not_configured} ->
                  assign(socket,
                    loading_submission: false,
                    submission_error: "Tally API-Schlüssel ist nicht konfiguriert"
                  )

                {:error, _reason} ->
                  assign(socket,
                    loading_submission: false,
                    submission_error: "Fehler beim Laden der Einreichung von Tally"
                  )
              end
          end

        _ ->
          assign(socket,
            loading_submission: false,
            submission_error: "Keine Tally-Einreichung für diesen Studenten gefunden"
          )
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_submission", %{"student-id" => student_id}, socket) do
    student_id = String.to_integer(student_id)
    student = Enum.find(socket.assigns.students, &(&1.id == student_id))

    if student do
      students_with_submissions =
        Enum.filter(socket.assigns.students, fn s ->
          has_submission?(socket.assigns.progress_map, s.id)
        end)

      socket =
        socket
        |> assign(:show_modal, true)
        |> assign(:loading_submission, true)
        |> assign(:selected_student_id, student_id)
        |> assign(:selected_student_name, get_student_full_name(student))
        |> assign(:selected_student_email, student.email)
        |> assign(:students_with_submissions, students_with_submissions)
        |> assign(:submission_error, nil)

      send(self(), {:fetch_submission, student_id})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
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

    next_student = Enum.at(students, next_index)

    if next_student do
      socket =
        socket
        |> assign(:loading_submission, true)
        |> assign(:selected_student_id, next_student.id)
        |> assign(:selected_student_name, get_student_full_name(next_student))
        |> assign(:selected_student_email, next_student.email)
        |> assign(:submission_data, nil)
        |> assign(:submission_error, nil)
        |> assign(:file_uploads, [])
        |> assign(:all_responses, [])

      send(self(), {:fetch_submission, next_student.id})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_modal, false)
     |> assign(:submission_data, nil)
     |> assign(:submission_error, nil)
     |> assign(:file_uploads, [])
     |> assign(:all_responses, [])
     |> assign(:loading_submission, false)
     |> assign(:selected_student_id, nil)
     |> assign(:selected_student_email, nil)
     |> assign(:students_with_submissions, [])}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  # Private Functions

  defp build_progress_map(task_id, students) do
    student_ids = Enum.map(students, & &1.id)

    submissions =
      Repo.all(
        from s in Tasky.Tasks.TaskSubmission,
          where: s.student_id in ^student_ids and s.task_id == ^task_id,
          select: %{
            student_id: s.student_id,
            status: s.status,
            tally_response_id: s.tally_response_id
          }
      )

    Enum.reduce(submissions, %{}, fn submission, acc ->
      Map.put(acc, submission.student_id, %{
        status: submission.status,
        tally_response_id: submission.tally_response_id
      })
    end)
  end

  defp get_submission_status(progress_map, student_id) do
    case Map.get(progress_map, student_id) do
      %{status: "completed"} -> :completed
      %{status: "in_progress"} -> :in_progress
      %{status: "open"} -> :in_progress
      nil -> :not_started
      _ -> :not_started
    end
  end

  defp has_submission?(progress_map, student_id) do
    case Map.get(progress_map, student_id) do
      %{tally_response_id: tally_response_id} when not is_nil(tally_response_id) -> true
      _ -> false
    end
  end

  defp get_initials(student) do
    first_initial =
      case student.firstname do
        nil -> "?"
        "" -> "?"
        name -> name |> String.first() |> String.upcase()
      end

    last_initial =
      case student.lastname do
        nil -> "?"
        "" -> "?"
        name -> name |> String.first() |> String.upcase()
      end

    "#{first_initial}#{last_initial}"
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

  defp format_datetime(nil), do: "Unbekannt"

  defp format_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} ->
        Calendar.strftime(datetime, "%d.%m.%Y um %H:%M Uhr")

      _ ->
        datetime_string
    end
  end

  defp format_datetime(_), do: "Unbekannt"

  defp format_file_size(nil), do: "Unbekannt"

  defp format_file_size(size) when is_integer(size) do
    cond do
      size < 1024 -> "#{size} B"
      size < 1024 * 1024 -> "#{Float.round(size / 1024, 1)} KB"
      size < 1024 * 1024 * 1024 -> "#{Float.round(size / (1024 * 1024), 1)} MB"
      true -> "#{Float.round(size / (1024 * 1024 * 1024), 1)} GB"
    end
  end

  defp format_file_size(_), do: "Unbekannt"
end
