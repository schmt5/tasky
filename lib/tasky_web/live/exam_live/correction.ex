defmodule TaskyWeb.ExamLive.Correction do
  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
              %{label: "Korrektur"}
            ]} />
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Korrektur
          </h1>

          <.exam_status_chip status={@exam.status} />
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <%= if @parts == [] do %>
            <div class="p-12 text-center text-stone-400">
              <.icon name="hero-document" class="w-10 h-10 mx-auto mb-3 text-stone-300" />
              <p class="text-sm font-medium">Kein Inhalt zum Korrigieren vorhanden.</p>
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-left">
                <thead class="bg-stone-50 border-b border-stone-100">
                  <tr>
                    <th class="px-6 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide">
                      Teilnehmer
                    </th>
                    <th class="px-4 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide">
                      Punkte
                    </th>
                    <th
                      :for={part <- @parts}
                      class="px-4 py-3 text-xs font-semibold text-stone-500 uppercase tracking-wide"
                    >
                      {part.label}
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-stone-100">
                  <tr :for={submission <- @submissions} class="hover:bg-stone-50/50">
                    <td class="px-6 py-3">
                      <div class="flex items-center gap-3">
                        <div class="w-9 h-9 rounded-full bg-gradient-to-br from-blue-400 to-indigo-500 flex items-center justify-center text-white text-sm font-bold shadow-sm shrink-0">
                          {String.first(submission.firstname)}{String.first(submission.lastname)}
                        </div>
                        <div class="min-w-0">
                          <p class="text-sm font-semibold text-stone-800 truncate">
                            {submission.firstname} {submission.lastname}
                          </p>
                          <p class="text-xs text-stone-400 mt-0.5">
                            <%= if submission.submitted do %>
                              <span class="text-purple-500 font-medium">Abgegeben</span>
                            <% else %>
                              <span class="text-stone-400">Nicht abgegeben</span>
                            <% end %>
                          </p>
                        </div>
                      </div>
                    </td>
                    <td class="px-4 py-3">
                      <span class="font-mono text-sm font-semibold text-stone-700">
                        {format_points(total_points(submission))}
                      </span>
                    </td>
                    <td :for={part <- @parts} class="px-4 py-3">
                      <div class="flex items-center gap-2">
                        <.link
                          navigate={
                            ~p"/exams/#{@exam}/correction/#{submission.id}/parts/#{part.id}"
                          }
                          class="inline-flex items-center justify-center w-9 h-9 rounded-lg text-stone-500 border border-stone-200 transition-all duration-150 hover:bg-stone-100 hover:text-stone-700 hover:border-stone-300"
                          title={"#{part.label} ansehen"}
                        >
                          <.icon name="hero-eye" class="w-4 h-4" />
                        </.link>
                        <%= if part.id in submission.corrected_parts do %>
                          <span
                            class="inline-flex items-center justify-center w-7 h-7 rounded-full bg-purple-50 text-purple-500"
                            title="Als korrigiert markiert"
                          >
                            <.icon name="hero-check-badge" class="w-5 h-5" />
                          </span>
                        <% end %>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    if connected?(socket) do
      Exams.subscribe_correction(exam.id)
    end

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Korrektur")
     |> assign(:exam, exam)
     |> assign(:parts, Exams.split_content_into_parts(exam.content || %{}))
     |> assign(:submissions, load_sorted_submissions(exam))}
  end

  @impl true
  def handle_info({:submission_corrected_parts_changed, submission}, socket) do
    submissions =
      Enum.map(socket.assigns.submissions, fn s ->
        if s.id == submission.id, do: submission, else: s
      end)

    {:noreply, assign(socket, :submissions, submissions)}
  end

  defp total_points(submission) do
    (submission.points_per_part || %{})
    |> Map.values()
    |> Enum.reduce(0, fn
      v, acc when is_number(v) -> acc + v
      _, acc -> acc
    end)
  end

  defp format_points(0), do: "—"
  defp format_points(n) when is_integer(n), do: Integer.to_string(n)

  defp format_points(n) when is_float(n) do
    if n == trunc(n), do: Integer.to_string(trunc(n)), else: :erlang.float_to_binary(n, decimals: 1)
  end

  defp load_sorted_submissions(exam) do
    exam
    |> Exams.list_exam_submissions()
    |> Enum.sort_by(fn s ->
      {String.downcase(s.firstname || ""), String.downcase(s.lastname || "")}
    end)
  end
end
