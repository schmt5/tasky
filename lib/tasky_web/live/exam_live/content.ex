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
        <pre class="text-sm text-stone-700 bg-stone-50 p-6 rounded-[14px] border border-stone-200 overflow-x-auto leading-relaxed"><code phx-no-curly-interpolation>{@content_json}</code></pre>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    content_json =
      if exam.content && exam.content != %{} do
        Jason.encode!(exam.content, pretty: true)
      else
        "{}"
      end

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Inhalt")
     |> assign(:exam, exam)
     |> assign(:content_json, content_json)}
  end
end
