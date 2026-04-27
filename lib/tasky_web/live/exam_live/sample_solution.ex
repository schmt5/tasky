defmodule TaskyWeb.ExamLive.SampleSolution do
  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/exams/#{@exam}/sample-solution"}
    >
      <%!-- Page Header --%>
      <div class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 h-[54px] flex items-center">
        <div class="max-w-6xl mx-auto w-full flex items-center justify-between gap-4">
          <.breadcrumbs crumbs={[
            %{label: "Prüfungen", navigate: ~p"/exams"},
            %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
            %{label: "Musterlösung"}
          ]} />
        </div>
      </div>

      <div
        id={"exam-sample-solution-editor-#{@exam.id}"}
        phx-hook="ExamSampleSolutionEditor"
        phx-update="ignore"
        data-exam-id={@exam.id}
        data-content={@content_json}
      >
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    initial_content =
      if exam.sample_solution && exam.sample_solution != %{},
        do: exam.sample_solution,
        else: exam.content || %{}

    content_json = Jason.encode!(initial_content)

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Musterlösung")
     |> assign(:exam, exam)
     |> assign(:content_json, content_json)}
  end
end
