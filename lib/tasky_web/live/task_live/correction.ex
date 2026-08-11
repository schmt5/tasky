defmodule TaskyWeb.TaskLive.Correction do
  @moduledoc """
  Die Lehrperson annotiert das Antwortdokument einer/eines Lernenden.

  Eigene Seite statt eines Editors im Fortschritts-Modal: das Modal wechselt
  Lernende an Ort und Stelle, während das Editor-Island `phx-update="ignore"`
  ist — ein laufender Autosave ginge beim Wechsel verloren, und das
  `data-content` der nächsten Person erreichte den ignorierten DOM-Knoten nie.
  Die Prüfungsseite umgeht dasselbe Problem mit einer Seite pro Abgabe.
  """
  use TaskyWeb, :live_view

  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/progress/#{@task.id}"}
    >
      <div class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 h-[54px] flex items-center">
        <div class="max-w-7xl mx-auto w-full flex items-center justify-between gap-4">
          <div class="flex items-center gap-2 min-w-0">
            <.back_button
              navigate={~p"/progress/#{@task.id}"}
              tooltip="Zurück zum Fortschritt"
              size="sm"
            />
            <.breadcrumbs crumbs={[
              %{label: "Kurse", navigate: ~p"/courses"},
              %{label: @task.course.name, navigate: ~p"/courses/#{@task.course_id}"},
              %{label: @task.name, navigate: ~p"/progress/#{@task.id}"},
              %{label: @student_name}
            ]} />
          </div>

          <div class="flex items-center gap-3 shrink-0">
            <span class="text-[12px] text-stone-500 hidden sm:inline">
              {@current_index + 1}/{length(@submissions)}
            </span>
            <.link
              :if={@prev_path}
              navigate={@prev_path}
              class="inline-flex items-center justify-center w-8 h-8 rounded-lg border border-stone-200 text-stone-500 hover:bg-stone-50"
              title="Vorherige/r Lernende/r"
            >
              <.icon name="hero-chevron-up" class="w-4 h-4" />
            </.link>
            <.link
              :if={@next_path}
              navigate={@next_path}
              class="inline-flex items-center justify-center w-8 h-8 rounded-lg border border-stone-200 text-stone-500 hover:bg-stone-50"
              title="Nächste/r Lernende/r"
            >
              <.icon name="hero-chevron-down" class="w-4 h-4" />
            </.link>
          </div>
        </div>
      </div>

      <%!-- Freigabe-Leiste --%>
      <div class="border-b border-stone-100 bg-white px-8 py-3">
        <div class="max-w-7xl mx-auto w-full flex flex-wrap items-center gap-x-3 gap-y-2">
          <.icon name="hero-pencil-square" class="w-4 h-4 text-sky-500" />
          <span class="text-[13px] text-stone-600">
            Anmerkungen werden automatisch gespeichert. Sichtbar werden sie erst mit der
            Freigabe der Musterlösung.
          </span>
          <span class="ml-auto text-[12px] text-stone-500">
            {solution_release_label(@task, @submission)}
          </span>
          <button
            :if={releasable?(@task, @submission)}
            type="button"
            phx-click="release_solution"
            class="inline-flex items-center gap-1.5 px-3.5 py-1.5 bg-white border border-sky-300 text-sky-700 text-[12px] font-semibold rounded-[8px] hover:bg-sky-50 transition-colors"
          >
            <.icon name="hero-lock-open" class="w-3.5 h-3.5" /> Freigeben
          </button>
        </div>
      </div>

      <div
        id={"task-correction-editor-#{@submission.id}"}
        phx-hook="TaskCorrectionEditor"
        phx-update="ignore"
        data-task-id={@task.id}
        data-submission-id={@submission.id}
        data-content={@correction_json}
      >
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"task_id" => task_id}, _session, socket) do
    task = Tasks.get_task_with_course!(socket.assigns.current_scope, task_id)

    submissions =
      socket.assigns.current_scope
      |> Tasks.list_task_submissions(task.id)
      |> Enum.filter(&(&1.status in reviewable_statuses()))
      |> Enum.sort_by(&student_sort_key/1)

    {:ok,
     socket
     |> assign(:task, task)
     |> assign(:submissions, submissions)}
  end

  @impl true
  def handle_params(%{"submission_id" => submission_id}, _uri, socket) do
    %{task: task, submissions: submissions} = socket.assigns

    case Tasks.get_submission(task, submission_id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Abgabe nicht gefunden.")
         |> push_navigate(to: ~p"/progress/#{task.id}")}

      submission ->
        index = Enum.find_index(submissions, &(&1.id == submission.id)) || 0

        {:noreply,
         socket
         |> assign(:submission, submission)
         |> assign(:student_name, student_name(Enum.at(submissions, index) || submission))
         |> assign(:current_index, index)
         |> assign(:page_title, "Korrektur – #{task.name}")
         |> assign(:correction_json, Jason.encode!(Tasks.correction_content(submission)))
         |> assign(:prev_path, sibling_path(task, submissions, index - 1))
         |> assign(:next_path, sibling_path(task, submissions, index + 1))}
    end
  end

  @impl true
  def handle_event("release_solution", _params, socket) do
    %{task: task, submission: submission} = socket.assigns

    case Tasks.release_solution(socket.assigns.current_scope, task, submission.id) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:submission, updated)
         |> put_flash(:info, "Musterlösung für #{socket.assigns.student_name} freigegeben.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Freigabe fehlgeschlagen.")}
    end
  end

  defp reviewable_statuses, do: ~w(completed in_revision review_approved review_denied)

  defp sibling_path(_task, _submissions, index) when index < 0, do: nil

  defp sibling_path(task, submissions, index) do
    case Enum.at(submissions, index) do
      nil -> nil
      sibling -> ~p"/progress/#{task.id}/correction/#{sibling.id}"
    end
  end

  defp student_sort_key(%{student: student}) do
    {String.downcase(student.lastname || ""), String.downcase(student.firstname || ""),
     String.downcase(student.email || "")}
  end

  defp student_name(%{student: student}) do
    case {student.firstname, student.lastname} do
      {first, last} when first not in [nil, ""] and last not in [nil, ""] -> "#{first} #{last}"
      {first, _} when first not in [nil, ""] -> first
      {_, last} when last not in [nil, ""] -> last
      _ -> student.email |> to_string() |> String.split("@") |> List.first()
    end
  end

  defp student_name(_), do: "Lernende/r"

  defp releasable?(task, submission) do
    task.solution_release_mode != "never" and not Tasks.solution_visible?(task, submission)
  end

  defp solution_release_label(%{solution_release_mode: "never"}, _submission),
    do: "Musterlösung ist für diese Lerneinheit ausgeblendet"

  defp solution_release_label(_task, %{solution_released_at: %DateTime{} = at}),
    do: "Freigegeben am #{Calendar.strftime(at, "%d.%m.%Y um %H:%M Uhr")}"

  defp solution_release_label(task, submission) do
    if Tasks.solution_visible?(task, submission),
      do: "Automatisch freigegeben (als erledigt markiert)",
      else: "Noch nicht freigegeben"
  end
end
