defmodule TaskyWeb.ExamLive.Paper do
  @moduledoc """
  The paper version of an exam — the blank exam laid out for printing, as a
  fallback for when a laptop or the Safe Exam Browser dies mid-session.

  The teacher sizes the answer boxes here and downloads the PDF
  (`TaskyWeb.ExamPaperController`, rendered by `Tasky.ExamPaperPdf`). The sheet
  on screen is a preview with the PDF's text column (A4, 14 mm side margins),
  so a box sized here wraps the same way on paper.

  Sizing the boxes is a locked edit: `EDITOR_MODES.paper` loads the same
  content lock the learner gets, and `stripAnswers` keeps answer content out
  of the skeleton it compares — so Enter inside a box passes and nothing else
  does. Only the line counts are persisted (`exam.paper_layout`); the exam
  document itself is never written from here.
  """

  use TaskyWeb, :live_view

  alias Tasky.ExamPaper
  alias Tasky.Exams
  alias Tasky.Grading

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Papierversion"}
            ]} />
          </div>

          <div class="flex items-center justify-between gap-4 flex-wrap">
            <div class="flex items-center gap-3">
              <.back_button navigate={~p"/exams/#{@exam}"} tooltip="Zurück zur Prüfung" />
              <div>
                <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
                  Papierversion
                </h1>
                <p class="text-sm text-stone-500 mt-1">
                  Klicke in ein Antwortfeld und drücke <kbd class="kbd kbd-sm">Enter</kbd>, um es zu
                  vergrössern.
                </p>
              </div>
            </div>

            <.link
              id="paper-pdf-download"
              href={~p"/exams/#{@exam}/paper.pdf"}
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
            >
              <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> PDF erstellen
            </.link>
          </div>
        </div>
      </div>

      <div class="paper-view px-8 pb-12 text-stone-900">
        <div class="paper-sheet">
          <header class="mb-8">
            <p class="text-[10px] uppercase tracking-[0.14em] text-stone-500 mb-1">Papierversion</p>
            <h1 class="font-serif text-[26px] leading-tight text-stone-900 mb-6">{@exam.name}</h1>

            <div class="flex items-end gap-6 text-sm">
              <label class="flex-[2] min-w-0">
                <span class="block text-xs text-stone-500 mb-1">Name</span>
                <span class="paper-field block"></span>
              </label>
              <label class="flex-1 min-w-0">
                <span class="block text-xs text-stone-500 mb-1">Klasse</span>
                <span class="paper-field block"></span>
              </label>
              <label class="flex-1 min-w-0">
                <span class="block text-xs text-stone-500 mb-1">Datum</span>
                <span class="paper-field block"></span>
              </label>
            </div>

            <div class="flex items-end gap-6 text-sm mt-4">
              <label class="flex-1 min-w-0">
                <span class="block text-xs text-stone-500 mb-1">
                  Punkte <span :if={@max_points}>von {format_points(@max_points)}</span>
                </span>
                <span class="paper-field block"></span>
              </label>
              <label class="flex-1 min-w-0">
                <span class="block text-xs text-stone-500 mb-1">Note</span>
                <span class="paper-field block"></span>
              </label>
            </div>
          </header>

          <div
            id={"exam-paper-#{@exam.id}"}
            phx-hook="ExamPaperEditor"
            phx-update="ignore"
            data-exam-id={@exam.id}
            data-content={@doc_json}
          >
          </div>

          <%!-- A free document has no answer fields to size, so the writing
             space has to be blank pages instead. --%>
          <section
            :for={page <- 1..@lined_pages//1}
            :if={@free_document}
            class="paper-lined-page"
          >
            <div class="flex items-end gap-6 text-sm mb-6">
              <label class="flex-[2] min-w-0">
                <span class="block text-xs text-stone-500 mb-1">Name</span>
                <span class="paper-field block"></span>
              </label>
              <span class="text-xs text-stone-500 pb-1 whitespace-nowrap">
                Seite {page + 1} von {@lined_pages + 1}
              </span>
            </div>
            <div :for={_ <- 1..@rules_per_page//1} class="paper-rule"></div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    {:ok, assign_paper(socket, exam)}
  end

  defp assign_paper(socket, exam) do
    doc =
      ExamPaper.paper_doc(exam.content,
        layout: exam.paper_layout,
        sample_solution_points: exam.sample_solution_points,
        sample_solution_block_points: exam.sample_solution_block_points,
        answer_mode: exam.answer_mode
      )

    free_document = Exams.free_document?(exam)

    socket
    |> assign(:page_title, "#{exam.name} – Papierversion")
    |> assign(:exam, exam)
    |> assign(:doc_json, Jason.encode!(doc))
    |> assign(:max_points, Exams.grading_max_points(exam))
    |> assign(:free_document, free_document)
    |> assign(:lined_pages, if(free_document, do: ExamPaper.lined_page_count(), else: 0))
    |> assign(:rules_per_page, ExamPaper.rules_per_page())
  end

  defp format_points(points), do: Grading.format_points(points)
end
