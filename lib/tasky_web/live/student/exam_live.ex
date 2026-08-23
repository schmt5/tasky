defmodule TaskyWeb.Student.ExamLive do
  @moduledoc """
  A corrected exam handed back to its assigned participant.

  What it shows is not this view's decision: the teacher picked the options
  when returning the exam, and they are stored on the exam. Sections come from
  `TaskyWeb.ExamSubmissionView`, the same module the PDF export goes through, so
  both surfaces agree for the same options.
  """

  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.Grading
  alias TaskyWeb.ExamSubmissionView

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/student/exams"}>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-4xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/student/exams"},
              %{label: @exam.name}
            ]} />
          </div>
          <div class="flex items-center gap-3">
            <.back_button navigate={~p"/student/exams"} tooltip="Zurück zu meinen Prüfungen" />
            <h1 class="font-serif text-[36px] text-stone-900 leading-[1.1] font-normal">
              {@exam.name}
            </h1>
          </div>
        </div>
      </div>

      <div class="max-w-4xl mx-auto px-8 pb-12 space-y-6">
        <%= if @options.show_points_and_mark do %>
          <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-6 flex items-center gap-10">
            <div>
              <span class="text-[10px] uppercase tracking-[0.12em] font-semibold text-stone-400 block mb-1">
                Punkte
              </span>
              <span class="font-mono text-2xl font-semibold text-stone-800">
                {Grading.format_points(@points)}
                <span class="text-stone-400 font-normal text-lg">
                  / {Grading.format_points(@max_points)}
                </span>
              </span>
            </div>
            <div>
              <span class="text-[10px] uppercase tracking-[0.12em] font-semibold text-stone-400 block mb-1">
                Note
              </span>
              <span class="font-mono text-2xl font-semibold text-stone-800">
                {Grading.format_mark(@mark)}
              </span>
            </div>
          </div>
        <% end %>

        <%= if @sections == [] do %>
          <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-12 text-center">
            <div class="w-14 h-14 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-5 mx-auto">
              <.icon name="hero-document-text" class="w-6 h-6" />
            </div>
            <h3 class="text-base font-semibold text-stone-700 mb-2">Keine Inhalte freigegeben</h3>
            <p class="text-sm text-stone-400 max-w-[360px] mx-auto leading-[1.6]">
              Deine Lehrperson hat für diese Prüfung keine Inhalte freigegeben.
            </p>
          </div>
        <% else %>
          <div
            :for={section <- @sections}
            class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]"
          >
            <div :if={section.heading} class="p-6 border-b border-stone-100">
              <h2 class="text-lg font-semibold text-stone-800">{section.heading}</h2>
            </div>
            <div class="p-6">
              <div
                id={"student-exam-viewer-#{@submission.id}-#{section.key}"}
                phx-hook="ExamReadOnlyViewer"
                phx-update="ignore"
                data-content={section.doc_json}
              >
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => exam_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Exams.get_submission_for_user(exam_id, user.id) do
      %{exam: exam} = submission ->
        if Exams.returned?(exam) do
          {:ok, mount_returned(socket, exam, submission)}
        else
          {:ok, redirect_away(socket, "Diese Prüfung ist noch nicht freigegeben.")}
        end

      nil ->
        {:ok, redirect_away(socket, "Diese Prüfung ist für dich nicht verfügbar.")}
    end
  end

  defp mount_returned(socket, exam, submission) do
    options = ExamSubmissionView.options_from_exam(exam)
    max_points = exam.grading_max_points || Grading.sum_points(exam.sample_solution_points)
    points = Grading.sum_points(submission.points_per_part)

    socket
    |> assign(:page_title, exam.name)
    |> assign(:exam, exam)
    |> assign(:submission, submission)
    |> assign(:options, options)
    |> assign(:points, points)
    |> assign(:max_points, max_points)
    |> assign(:mark, submission.mark || Grading.mark(points, max_points))
    |> assign(:sections, ExamSubmissionView.sections(exam, submission, options))
  end

  defp redirect_away(socket, message) do
    socket
    |> put_flash(:error, message)
    |> push_navigate(to: ~p"/student/exams")
  end
end
