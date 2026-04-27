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
      <div class="bg-white min-h-screen">
        <%!-- Compact Header --%>
        <div class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 py-3">
          <div class="max-w-7xl mx-auto flex items-center justify-between gap-4">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Musterlösung – #{@current_part.label}"}
            ]} />

            <div class="flex items-center gap-2 shrink-0">
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
                id={"sample-solution-part-editor-#{@exam.id}-#{@current_part.id}"}
                phx-hook="ExamSampleSolutionPartEditor"
                phx-update="ignore"
                data-exam-id={@exam.id}
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
                  <p class="text-xs text-stone-500 mt-1">Musterlösung</p>
                </div>

                <div class="p-5">
                  <form phx-change="set_max_points" phx-submit="set_max_points">
                    <label
                      for="part-max-points-input"
                      class="block text-xs font-semibold text-stone-500 uppercase tracking-wide mb-2"
                    >
                      Max. Punkte
                    </label>
                    <input
                      id="part-max-points-input"
                      type="number"
                      name="points"
                      value={@max_points || ""}
                      step="0.5"
                      min="0"
                      inputmode="decimal"
                      phx-debounce="500"
                      placeholder="—"
                      class="w-full font-mono text-base text-stone-800 bg-stone-50 border border-stone-200 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-purple-300 focus:border-purple-400"
                    />
                  </form>
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
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    {:ok, assign(socket, :exam, exam)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, socket.assigns.exam.id)
    socket = assign(socket, :exam, exam)
    parts = sample_solution_parts(exam)

    cond do
      parts == [] ->
        {:noreply,
         socket
         |> put_flash(:error, "Kein Inhalt für die Musterlösung vorhanden.")
         |> push_navigate(to: ~p"/exams/#{exam}")}

      is_nil(params["part_id"]) ->
        first = hd(parts)
        {:noreply, push_patch(socket, to: ~p"/exams/#{exam}/sample-solution/parts/#{first.id}")}

      true ->
        part_id = params["part_id"]

        case Enum.find(parts, &(&1.id == part_id)) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, "Teil nicht gefunden.")
             |> push_patch(to: ~p"/exams/#{exam}/sample-solution")}

          current_part ->
            part_doc = %{"type" => "doc", "content" => current_part.nodes}
            part_doc_json = Jason.encode!(part_doc)
            part_index = Enum.find_index(parts, &(&1.id == current_part.id))

            {:noreply,
             socket
             |> assign(:page_title, "#{exam.name} – Musterlösung – #{current_part.label}")
             |> assign(:parts, parts)
             |> assign(:current_part, current_part)
             |> assign(:part_doc_json, part_doc_json)
             |> assign(
               :max_points,
               Map.get(exam.sample_solution_points || %{}, current_part.id)
             )
             |> assign(:prev_part_path, sibling_part_path(exam, parts, part_index, -1))
             |> assign(:next_part_path, sibling_part_path(exam, parts, part_index, +1))}
        end
    end
  end

  @impl true
  def handle_event("set_max_points", %{"points" => raw}, socket) do
    %{exam: exam, current_part: part} = socket.assigns

    points = parse_points(raw)

    case Exams.set_sample_solution_part_points(exam, part.id, points) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:exam, updated)
         |> assign(:max_points, points)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Punkte konnten nicht gespeichert werden.")}
    end
  end

  defp sample_solution_parts(exam) do
    doc =
      case exam.sample_solution do
        s when is_map(s) and map_size(s) > 0 -> s
        _ -> exam.content || %{}
      end

    Exams.split_content_into_parts(doc)
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

  defp sibling_part_path(_exam, _parts, nil, _delta), do: nil

  defp sibling_part_path(exam, parts, idx, delta) do
    target = idx + delta

    if target < 0 or target >= length(parts) do
      nil
    else
      part = Enum.at(parts, target)
      ~p"/exams/#{exam}/sample-solution/parts/#{part.id}"
    end
  end
end
