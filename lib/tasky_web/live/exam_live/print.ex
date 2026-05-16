defmodule TaskyWeb.ExamLive.Print do
  @moduledoc """
  Token-authenticated print view of one submission, designed to be fetched
  by Gotenberg's headless Chrome and converted to PDF.

  Auth: validates a `?token=...` query param signed by
  `Tasky.Exams.PrintToken`. No session cookie required.
  """

  use TaskyWeb, :live_view

  alias Tasky.Exams.{PrintToken, ExamSubmission}
  alias Tasky.Repo

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
      </header>

      <%= if @combined_doc do %>
        <section class="px-8 py-8">
          <div
            id={"print-viewer-#{@submission.id}"}
            phx-hook="ExamReadOnlyViewer"
            phx-update="ignore"
            data-content={@combined_doc_json}
          >
          </div>
        </section>
      <% else %>
        <section class="px-8 py-8 text-stone-400 text-sm italic">
          Keine Inhalte zum Anzeigen ausgewählt.
        </section>
      <% end %>

      <%!-- Tells Gotenberg we are ready to be printed. Small delay lets the
           React-based TipTap viewer finish its first render. --%>
      <script>
        window.printReady = false;
        setTimeout(function () {
          window.requestAnimationFrame(function () {
            window.requestAnimationFrame(function () {
              window.printReady = true;
            });
          });
        }, 600);
      </script>
    </main>
    """
  end

  @impl true
  def mount(%{"exam_id" => exam_id, "submission_id" => submission_id} = params, _session, socket) do
    case PrintToken.verify(socket.endpoint, params["token"]) do
      {:ok, {_user_id, ^exam_id, ^submission_id, opts}} ->
        mount_with_data(exam_id, submission_id, opts, socket)

      {:ok, _other_payload} ->
        {:ok, assign_error(socket, "Token entspricht nicht der angeforderten Druckansicht.")}

      {:error, reason} ->
        {:ok, assign_error(socket, "Token ungültig oder abgelaufen (#{reason}).")}
    end
  end

  defp mount_with_data(exam_id, submission_id, opts, socket) do
    exam = Repo.get!(Tasky.Exams.Exam, exam_id)
    submission = Repo.get_by!(ExamSubmission, id: submission_id, exam_id: exam.id)

    sample_solution_total = sum_map_points(exam.sample_solution_points)
    max_points = exam.grading_max_points || sample_solution_total
    points = total_points(submission)
    mark = submission.mark || calculate_mark(points, max_points)

    combined_doc = build_combined_doc(exam, submission, opts)
    combined_doc_json = if combined_doc, do: Jason.encode!(combined_doc), else: nil

    {:ok,
     socket
     |> assign(:page_title, "#{exam.name} – #{submission.firstname} #{submission.lastname}")
     |> assign(:exam, exam)
     |> assign(:submission, submission)
     |> assign(:points, points)
     |> assign(:max_points, max_points)
     |> assign(:mark, mark)
     |> assign(:combined_doc, combined_doc)
     |> assign(:combined_doc_json, combined_doc_json)
     |> assign(:error, nil)}
  end

  defp assign_error(socket, message) do
    socket
    |> assign(:page_title, "Druckansicht")
    |> assign(:error, message)
  end

  # Builds a single TipTap doc containing the optional submission content
  # followed by the optional sample solution, with a heading separating
  # them. Returns nil when nothing is requested.
  defp build_combined_doc(exam, submission, opts) do
    sections = []

    sections =
      if opts[:show_content] do
        nodes =
          if opts[:show_correction] do
            submission_nodes(submission.corrected_content || submission.content)
          else
            submission_nodes(submission.content)
          end

        sections ++ [{:content_heading?, false, nodes}]
      else
        sections
      end

    sections =
      if opts[:show_sample_solution] do
        sample_nodes = submission_nodes(exam.sample_solution)
        heading? = sections != []
        sections ++ [{:sample_heading?, heading?, sample_nodes}]
      else
        sections
      end

    case sections do
      [] ->
        nil

      sections ->
        nodes =
          Enum.flat_map(sections, fn
            {:content_heading?, true, nodes} -> [heading_node("Inhalt") | nodes]
            {:content_heading?, false, nodes} -> nodes
            {:sample_heading?, true, nodes} -> [heading_node("Musterlösung") | nodes]
            {:sample_heading?, false, nodes} -> nodes
          end)

        %{"type" => "doc", "content" => nodes}
    end
  end

  defp submission_nodes(doc) when is_map(doc), do: Map.get(doc, "content", [])
  defp submission_nodes(_), do: []

  defp heading_node(text) do
    %{
      "type" => "heading",
      "attrs" => %{"level" => 2},
      "content" => [%{"type" => "text", "text" => text}]
    }
  end

  defp sum_map_points(nil), do: 0

  defp sum_map_points(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.reduce(0, fn
      v, acc when is_number(v) -> acc + v
      _, acc -> acc
    end)
  end

  defp total_points(submission) do
    sum_map_points(submission.points_per_part)
  end

  # Swiss 1–6 scale, rounded to 0.25, clamped.
  defp calculate_mark(_, max) when max in [nil, 0, 0.0], do: nil

  defp calculate_mark(points, max) when is_number(points) and is_number(max) do
    raw = points / max * 5 + 1
    raw |> Float.round(2) |> then(&(Float.round(&1 * 4) / 4)) |> clamp_mark()
  end

  defp calculate_mark(_, _), do: nil

  defp clamp_mark(n) when n < 1.0, do: 1.0
  defp clamp_mark(n) when n > 6.0, do: 6.0
  defp clamp_mark(n), do: n

  defp format_mark(nil), do: "—"

  defp format_mark(n) when is_number(n) do
    n = n * 1.0

    if n == trunc(n),
      do: :erlang.float_to_binary(n, decimals: 1),
      else: :erlang.float_to_binary(n, decimals: 2)
  end

  defp format_points(nil), do: "—"
  defp format_points(0), do: "0"
  defp format_points(n) when is_integer(n), do: Integer.to_string(n)

  defp format_points(n) when is_float(n) do
    if n == trunc(n),
      do: Integer.to_string(trunc(n)),
      else: :erlang.float_to_binary(n, decimals: 1)
  end

end
