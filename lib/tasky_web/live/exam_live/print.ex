defmodule TaskyWeb.ExamLive.Print do
  @moduledoc """
  Token-authenticated print view of one submission, designed to be fetched
  by Gotenberg's headless Chrome and converted to PDF.

  Auth: validates a `?token=...` query param signed by
  `Tasky.Exams.PrintToken`. No session cookie required.
  """

  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.Exams.PrintToken
  alias Tasky.Grading
  alias TaskyWeb.ExamSubmissionView

  @impl true
  def render(%{error: error} = assigns) when not is_nil(error) do
    ~H"""
    <main class="min-h-screen flex items-center justify-center p-8 bg-white">
      <div class="max-w-md text-center">
        <h1 class="font-serif text-2xl text-stone-900 mb-2">Druckansicht nicht verfügbar</h1>
        <p class="text-stone-500 text-sm">{@error}</p>
      </div>
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <main class="bg-white text-stone-900 print-view">
      <header class="px-8 pt-8 pb-6 border-b border-stone-200">
        <h1 class="font-serif text-2xl text-stone-900 mb-1">{@exam.name}</h1>
        <p class="text-sm text-stone-600">
          {@submission.firstname} {@submission.lastname}
        </p>
        <%= if @show_points_and_mark do %>
          <div class="mt-4 flex items-center gap-6 text-sm">
            <div>
              <span class="text-xs uppercase tracking-wide text-stone-500 block">Punkte</span>
              <span class="font-mono font-semibold text-stone-800">
                {format_points(@points)}
                <span class="text-stone-400 font-normal">/ {format_points(@max_points)}</span>
              </span>
            </div>
            <div>
              <span class="text-xs uppercase tracking-wide text-stone-500 block">Note</span>
              <span class="font-mono font-semibold text-stone-800">
                {format_mark(@mark)}
              </span>
            </div>
          </div>
        <% end %>
      </header>

      <%= if @sections == [] do %>
        <section class="px-8 py-8 text-stone-400 text-sm italic">
          Keine Inhalte zum Anzeigen ausgewählt.
        </section>
      <% else %>
        <%= for {section, idx} <- Enum.with_index(@sections) do %>
          <section class={[
            "px-8 py-8",
            idx > 0 && "break-before-page"
          ]}>
            <%= if section.heading do %>
              <h2 class="font-serif text-xl text-stone-900 mb-4">{section.heading}</h2>
            <% end %>
            <div
              id={"print-viewer-#{@submission.id}-#{section.key}"}
              phx-hook="ExamReadOnlyViewer"
              phx-update="ignore"
              data-content={section.doc_json}
            >
            </div>
          </section>
        <% end %>
      <% end %>

      <%!-- Marker for assets/js/print_ready.js: tells Gotenberg when we are
           ready to be printed (viewers rendered, images loaded). Kept in the
           bundle instead of an inline script so the CSP stays strict. --%>
      <div id="print-ready-signal" hidden></div>
    </main>
    """
  end

  @impl true
  def mount(%{"exam_id" => exam_id, "submission_id" => submission_id} = params, _session, socket) do
    case PrintToken.verify(socket.endpoint, params["token"]) do
      {:ok, {user_id, ^exam_id, ^submission_id, opts}} ->
        mount_with_data(user_id, exam_id, submission_id, opts, socket)

      {:ok, _other_payload} ->
        {:ok, assign_error(socket, "Token entspricht nicht der angeforderten Druckansicht.")}

      {:error, reason} ->
        {:ok, assign_error(socket, "Token ungültig oder abgelaufen (#{reason}).")}
    end
  end

  defp mount_with_data(user_id, exam_id, submission_id, opts, socket) do
    # The signed token carries the requesting teacher's id — rebuild their
    # scope so the regular scoped accessors enforce ownership here too.
    scope = Tasky.Accounts.Scope.for_user(Tasky.Accounts.get_user!(user_id))
    exam = Exams.get_exam!(scope, exam_id)
    submission = Exams.get_submission!(exam, submission_id)

    sample_solution_total = sum_map_points(exam.sample_solution_points)
    max_points = exam.grading_max_points || sample_solution_total
    points = total_points(submission)
    mark = submission.mark || calculate_mark(points, max_points)

    sections = ExamSubmissionView.sections(exam, submission, opts)

    {:ok,
     socket
     |> assign(:page_title, "#{exam.name} – #{submission.firstname} #{submission.lastname}")
     |> assign(:exam, exam)
     |> assign(:submission, submission)
     |> assign(:points, points)
     |> assign(:max_points, max_points)
     |> assign(:mark, mark)
     |> assign(:show_points_and_mark, Map.get(opts, :show_points_and_mark, true))
     |> assign(:sections, sections)
     |> assign(:error, nil)}
  end

  defp assign_error(socket, message) do
    socket
    |> assign(:page_title, "Druckansicht")
    |> assign(:error, message)
  end

  defp sum_map_points(map), do: Grading.sum_points(map)

  defp total_points(submission), do: Grading.sum_points(submission.points_per_part)

  # One mark formula for screen and PDF — Tasky.Grading is the source of truth.
  defp calculate_mark(points, max), do: Grading.mark(points, max)

  defp format_mark(mark), do: Grading.format_mark(mark)

  defp format_points(points), do: Grading.format_points(points)
end
