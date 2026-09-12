defmodule TaskyWeb.ExamLive.Paper do
  @moduledoc """
  The paper version of an exam — the blank exam laid out for printing, as a
  fallback for when a laptop or the Safe Exam Browser dies mid-session.

  One module, two routes, two credentials:

    * `/exams/:id/paper` (param `"id"`, cookie auth) — the teacher sizes the
      answer boxes here and starts the export. It is also the browser-print
      fallback: the chrome is `print:hidden`, so Cmd/Ctrl+P prints the sheet
      as it stands, which still works when Gotenberg is down.
    * `/print/exam-paper/:exam_id` (param `"exam_id"`, signed token) — what
      Gotenberg's headless Chrome fetches, rendered read-only.

  The two `mount/3` clauses match on **different param names** rather than
  branching on "is someone logged in?", so which credential was meant is a
  structural fact instead of a runtime guess.

  Sizing the boxes is a locked edit: `EDITOR_MODES.paper` loads the same
  content lock the learner gets, and `stripAnswers` keeps answer content out
  of the skeleton it compares — so Enter inside a box passes and nothing else
  does. Only the line counts are persisted (`exam.paper_layout`); the exam
  document itself is never written from here.
  """

  use TaskyWeb, :live_view

  alias Tasky.ExamPaper
  alias Tasky.Exams
  alias Tasky.Exams.ExamPrintToken
  alias Tasky.Grading

  @impl true
  def render(%{error: error} = assigns) when not is_nil(error) do
    ~H"""
    <main class="min-h-screen flex items-center justify-center p-8 bg-white">
      <div class="max-w-md text-center">
        <h1 class="font-serif text-2xl text-stone-900 mb-2">Papierversion nicht verfügbar</h1>
        <p class="text-stone-500 text-sm">{@error}</p>
      </div>
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <main class="paper-view bg-white text-stone-900">
      <div
        :if={@editable}
        class="print:hidden sticky top-0 z-20 bg-white/95 backdrop-blur border-b border-stone-200 px-6 py-3"
      >
        <div class="max-w-[210mm] mx-auto flex items-center gap-4 flex-wrap">
          <.link
            navigate={~p"/exams/#{@exam}"}
            class="inline-flex items-center gap-1.5 text-sm text-stone-500 hover:text-stone-800 transition-colors duration-150"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" /> {@exam.name}
          </.link>

          <p class="text-sm text-stone-600 flex-1 min-w-[16rem]">
            Klicke in ein Antwortfeld und drücke <kbd class="kbd kbd-sm">Enter</kbd>, um es zu
            vergrössern.
          </p>

          <.link
            href={~p"/exams/#{@exam}/paper.pdf"}
            target="_blank"
            rel="noopener"
            class={[
              "inline-flex items-center gap-2 text-sm font-semibold px-4 py-2.5 rounded-lg transition-colors duration-150",
              if(@pdf_enabled,
                do: "text-stone-700 bg-white border border-stone-200 hover:bg-stone-50",
                else: "hidden"
              )
            ]}
          >
            <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> PDF erstellen
          </.link>

          <div
            :if={not @pdf_enabled}
            class="tooltip tooltip-bottom tooltip-delayed"
            data-tip="PDF-Dienst nicht verfügbar"
          >
            <button
              type="button"
              disabled
              class="inline-flex items-center gap-2 text-sm font-semibold text-stone-400 bg-stone-100 border border-stone-200 px-4 py-2.5 rounded-lg cursor-not-allowed"
            >
              <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> PDF erstellen
            </button>
          </div>

          <%!-- Never gated on @pdf_enabled: that flag reflects configuration,
               not reachability, so a configured-but-stopped Gotenberg leaves
               the button above enabled and failing. The browser path has to
               stay one click away. --%>
          <span class="text-sm text-stone-500">
            oder mit <kbd class="kbd kbd-sm">Cmd/Ctrl</kbd> + <kbd class="kbd kbd-sm">P</kbd> drucken
          </span>
        </div>
      </div>

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
          phx-hook={if @editable, do: "ExamPaperEditor", else: "ExamReadOnlyViewer"}
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

      <%!-- Marker for assets/js/print_ready.js. Only on the Gotenberg path:
           the editable page has no read-only viewers to wait for. --%>
      <div :if={not @editable} id="print-ready-signal" hidden></div>
    </main>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    {:ok, assign_paper(socket, exam, editable: true)}
  end

  def mount(%{"exam_id" => exam_id} = params, _session, socket) do
    case ExamPrintToken.verify(socket.endpoint, params["token"]) do
      {:ok, {user_id, ^exam_id, _opts}} ->
        # The signed token carries the requesting teacher's id — rebuild their
        # scope so the regular scoped accessor enforces ownership here too.
        scope = Tasky.Accounts.Scope.for_user(Tasky.Accounts.get_user!(user_id))
        exam = Exams.get_exam!(scope, exam_id)

        {:ok, assign_paper(socket, exam, editable: false)}

      {:ok, _other_payload} ->
        {:ok, assign_error(socket, "Token entspricht nicht der angeforderten Druckansicht.")}

      {:error, reason} ->
        {:ok, assign_error(socket, "Token ungültig oder abgelaufen (#{reason}).")}
    end
  end

  defp assign_paper(socket, exam, opts) do
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
    |> assign(:editable, Keyword.fetch!(opts, :editable))
    |> assign(:pdf_enabled, Tasky.PDF.Gotenberg.enabled?())
    |> assign(:error, nil)
  end

  defp assign_error(socket, message) do
    socket
    |> assign(:page_title, "Papierversion")
    |> assign(:error, message)
  end

  defp format_points(points), do: Grading.format_points(points)
end
