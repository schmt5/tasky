defmodule TaskyWeb.ExamLive.CorrectionPart do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.Repo
  alias Tasky.Exams.ExamSubmission

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <div class="bg-white min-h-screen">
      <%!-- Compact Header --%>
      <div class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 py-3">
        <div class="max-w-7xl mx-auto flex items-center justify-between gap-4">
          <.breadcrumbs crumbs={[
            %{label: "Prüfungen", navigate: ~p"/exams"},
            %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
            %{label: "Korrektur", navigate: ~p"/exams/#{@exam}/correction"},
            %{label: "#{@submission.firstname} #{@submission.lastname} – #{@current_part.label}"}
          ]} />

          <div class="flex items-center gap-2 shrink-0">
            <.nav_chevron
              direction="up"
              target={@prev_submission_path}
              title="Vorheriger Teilnehmer"
            />
            <.nav_chevron
              direction="down"
              target={@next_submission_path}
              title="Nächster Teilnehmer"
            />
            <span class="w-px h-6 bg-stone-200 mx-1" />
            <.nav_chevron direction="left" target={@prev_part_path} title="Vorheriger Teil" />
            <.nav_chevron direction="right" target={@next_part_path} title="Nächster Teil" />
          </div>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-8 py-6">
        <div class="grid grid-cols-4 gap-6 items-start">
          <%!-- Editor (3/4) --%>
          <div class="col-span-3 min-w-0">
            <div
              id={"correction-part-editor-#{@submission.id}-#{@current_part.id}"}
              phx-hook="ExamCorrectionEditor"
              phx-update="ignore"
              data-exam-id={@exam.id}
              data-submission-id={@submission.id}
              data-part-id={@current_part.id}
              data-content={@part_doc_json}
            >
            </div>
          </div>

          <%!-- Sidebar (1/4, sticky) --%>
          <aside class="col-span-1 sticky top-[72px]">
            <div class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
              <div class="p-5 border-b border-stone-100">
                <h2 class="text-base font-semibold text-stone-800 truncate">
                  {@current_part.label}
                </h2>
                <p class="text-xs text-stone-500 mt-1">
                  <span class="font-medium text-stone-700">
                    {@submission.firstname} {@submission.lastname}
                  </span>
                  <span class="text-stone-300 mx-1">·</span>
                  <%= if @submission.submitted do %>
                    <span class="text-purple-500 font-medium">Abgegeben</span>
                  <% else %>
                    <span class="text-stone-400">Nicht abgegeben</span>
                  <% end %>
                </p>
              </div>

              <div class="p-5 border-b border-stone-100">
                <form phx-change="set_points" phx-submit="set_points">
                  <label
                    for="part-points-input"
                    class="block text-xs font-semibold text-stone-500 uppercase tracking-wide mb-2"
                  >
                    Punkte
                  </label>
                  <input
                    id="part-points-input"
                    type="number"
                    name="points"
                    value={@points || ""}
                    step="0.5"
                    min="0"
                    inputmode="decimal"
                    phx-debounce="500"
                    placeholder="—"
                    class="w-full font-mono text-base text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-purple-300 focus:border-purple-400"
                  />
                </form>
              </div>

              <div class="p-5">
                <button
                  type="button"
                  phx-click="toggle_corrected"
                  class={[
                    "w-full inline-flex items-center justify-center gap-2 text-sm font-semibold px-4 py-2.5 rounded-lg transition-all duration-150 active:scale-[0.98]",
                    if(@is_corrected,
                      do:
                        "bg-purple-500 text-white shadow-[0_2px_8px_rgba(168,85,247,0.25)] hover:bg-purple-600",
                      else:
                        "text-stone-600 border border-stone-200 hover:bg-stone-50 hover:border-stone-300"
                    )
                  ]}
                >
                  <.icon name="hero-check-badge" class="w-4 h-4" />
                  <%= if @is_corrected, do: "Korrigiert", else: "Als korrigiert markieren" %>
                </button>
              </div>
            </div>
          </aside>
        </div>
      </div>
      </div>
    </Layouts.app>
    """
  end

  attr :direction, :string, required: true
  attr :target, :string, default: nil
  attr :title, :string, required: true

  defp nav_chevron(assigns) do
    icon =
      case assigns.direction do
        "up" -> "hero-chevron-up"
        "down" -> "hero-chevron-down"
        "left" -> "hero-chevron-left"
        "right" -> "hero-chevron-right"
      end

    assigns = assign(assigns, :icon, icon)

    ~H"""
    <%= if @target do %>
      <.link
        patch={@target}
        title={@title}
        class="inline-flex items-center justify-center w-9 h-9 rounded-lg text-stone-600 border border-stone-200 transition-all duration-150 hover:bg-stone-50 hover:border-stone-300 hover:text-stone-800"
      >
        <.icon name={@icon} class="w-4 h-4" />
      </.link>
    <% else %>
      <span
        title={@title}
        class="inline-flex items-center justify-center w-9 h-9 rounded-lg text-stone-300 border border-stone-100 cursor-not-allowed"
      >
        <.icon name={@icon} class="w-4 h-4" />
      </span>
    <% end %>
    """
  end

  @impl true
  def mount(%{"id" => exam_id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, exam_id)

    submissions =
      exam
      |> Exams.list_exam_submissions()
      |> Enum.sort_by(fn s ->
        {String.downcase(s.firstname || ""), String.downcase(s.lastname || "")}
      end)

    {:ok,
     socket
     |> assign(:exam, exam)
     |> assign(:submissions, submissions)}
  end

  @impl true
  def handle_params(%{"submission_id" => submission_id, "part_id" => part_id}, _uri, socket) do
    %{exam: exam, submissions: submissions} = socket.assigns

    submission =
      Repo.get_by!(ExamSubmission, id: submission_id, exam_id: exam.id)

    parts =
      submission
      |> Exams.correction_content()
      |> Exams.split_content_into_parts()

    current_part =
      Enum.find(parts, &(&1.id == part_id)) ||
        fallback_part_from_exam(exam, part_id)

    if is_nil(current_part) do
      {:noreply,
       socket
       |> put_flash(:error, "Teil nicht gefunden.")
       |> push_navigate(to: ~p"/exams/#{exam}/correction")}
    else
      part_doc = %{"type" => "doc", "content" => current_part.nodes}
      part_doc_json = Jason.encode!(part_doc)

      part_index = Enum.find_index(parts, &(&1.id == current_part.id))
      submission_index = Enum.find_index(submissions, &(&1.id == submission.id))

      {:noreply,
       socket
       |> assign(:page_title, "#{exam.name} – #{current_part.label}")
       |> assign(:submission, submission)
       |> assign(:parts, parts)
       |> assign(:current_part, current_part)
       |> assign(:part_doc_json, part_doc_json)
       |> assign(:is_corrected, current_part.id in (submission.corrected_parts || []))
       |> assign(:points, Map.get(submission.points_per_part || %{}, current_part.id))
       |> assign(:prev_part_path, sibling_part_path(exam, submission, parts, part_index, -1))
       |> assign(:next_part_path, sibling_part_path(exam, submission, parts, part_index, +1))
       |> assign(
         :prev_submission_path,
         sibling_submission_path(exam, submissions, submission_index, current_part.id, -1)
       )
       |> assign(
         :next_submission_path,
         sibling_submission_path(exam, submissions, submission_index, current_part.id, +1)
       )}
    end
  end

  @impl true
  def handle_event("set_points", %{"points" => raw}, socket) do
    %{submission: submission, current_part: part} = socket.assigns

    points = parse_points(raw)

    case Exams.set_part_points(submission, part.id, points) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:submission, updated)
         |> assign(:points, points)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Punkte konnten nicht gespeichert werden.")}
    end
  end

  def handle_event("toggle_corrected", _params, socket) do
    %{submission: submission, current_part: part} = socket.assigns

    result =
      if part.id in (submission.corrected_parts || []) do
        Exams.unmark_part_corrected(submission, part.id)
      else
        Exams.mark_part_corrected(submission, part.id)
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:submission, updated)
         |> assign(:is_corrected, part.id in (updated.corrected_parts || []))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Status konnte nicht aktualisiert werden.")}
    end
  end

  defp parse_points(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        nil

      trimmed ->
        case Float.parse(trimmed) do
          {n, ""} -> if n == trunc(n), do: trunc(n), else: n
          _ -> nil
        end
    end
  end

  defp parse_points(_), do: nil

  defp sibling_part_path(_exam, _submission, _parts, nil, _delta), do: nil

  defp sibling_part_path(exam, submission, parts, idx, delta) do
    target = idx + delta

    if target < 0 or target >= length(parts) do
      nil
    else
      part = Enum.at(parts, target)
      ~p"/exams/#{exam}/correction/#{submission.id}/parts/#{part.id}"
    end
  end

  defp sibling_submission_path(_exam, _submissions, nil, _part_id, _delta), do: nil

  defp sibling_submission_path(exam, submissions, idx, part_id, delta) do
    target = idx + delta

    if target < 0 or target >= length(submissions) do
      nil
    else
      sub = Enum.at(submissions, target)
      ~p"/exams/#{exam}/correction/#{sub.id}/parts/#{part_id}"
    end
  end

  # If a submission has no nodes for the requested part_id (e.g. never opened
  # or content out-of-sync), fall back to the exam's canonical part so the
  # editor still renders the question structure.
  defp fallback_part_from_exam(exam, part_id) do
    exam.content
    |> Kernel.||(%{})
    |> Exams.split_content_into_parts()
    |> Enum.find(&(&1.id == part_id))
  end
end
