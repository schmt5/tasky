defmodule TaskyWeb.ExamLive.Content do
  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}/content"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Inhalt"}
            ]} />
          </div>
          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
            {@exam.name} – Inhalt
          </h1>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8">
        <div
          id={"exam-content-editor-#{@exam.id}"}
          phx-hook="ExamContentEditor"
          phx-update="ignore"
          data-exam-id={@exam.id}
          data-content={@content_json}
        >
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    content_json = Jason.encode!(exam.content || %{})

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Inhalt")
     |> assign(:exam, exam)
     |> assign(:content_json, content_json)}
  end
end
