defmodule TaskyWeb.Student.TaskLive do
  use TaskyWeb, :live_view

  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <script src="https://tally.so/widgets/embed.js">
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".TallyEmbed">
      export default {
        mounted() {
          if (window.Tally) {
            window.Tally.loadEmbeds();
          }
        },
        updated() {
          if (window.Tally) {
            window.Tally.loadEmbeds();
          }
        }
      }
    </script>

    <div id="task-container" phx-hook=".TallyEmbed">
      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <%!-- Compact Page Header --%>
        <div class="bg-white border-b border-stone-200 h-[54px] flex items-center px-8">
          <div class="max-w-6xl mx-auto w-full flex items-center justify-between">
            <h1 class="text-[16px] font-semibold text-stone-900 truncate">
              {@task.name}
            </h1>

            <.link
              navigate={~p"/student/courses/#{@task.course_id}"}
              class="inline-flex items-center gap-1.5 px-4 py-2 text-[13px] font-semibold text-stone-700 bg-stone-100 hover:bg-stone-200 rounded-lg transition-colors duration-150 flex-shrink-0"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Zurück
            </.link>
          </div>
        </div>

        <%!-- Main Content --%>
        <div class="max-w-4xl mx-auto px-8 py-8">
          <%= if @preview_mode && @submission.status == "completed" do %>
            <%!-- Preview Mode Banner --%>
            <div class="mb-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
              <div class="flex items-center gap-3">
                <.icon name="hero-eye" class="w-5 h-5 text-blue-600 flex-shrink-0" />
                <div class="flex-1">
                  <p class="text-[14px] font-medium text-blue-900">
                    Vorschaumodus
                  </p>
                  <p class="text-[13px] text-blue-700">
                    Du siehst deine bereits abgeschlossene Aufgabe zur Ansicht.
                  </p>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @submission.status == "completed" && !@preview_mode do %>
            <%= if @submission.graded_at do %>
              <%!-- Graded Feedback Card --%>
              <div class="bg-gradient-to-br from-emerald-50 to-white rounded-[14px] border border-emerald-200 p-8 shadow-sm">
                <div class="flex items-start gap-4">
                  <div class="flex-shrink-0">
                    <div class="w-12 h-12 bg-emerald-100 rounded-full flex items-center justify-center">
                      <.icon name="hero-check-badge" class="w-6 h-6 text-emerald-600" />
                    </div>
                  </div>

                  <div class="flex-1">
                    <h3 class="text-lg font-semibold text-emerald-900 mb-1">Aufgabe bewertet!</h3>

                    <div class="flex items-baseline gap-2 mb-3">
                      <span class="text-3xl font-bold text-emerald-600">{@submission.points}</span>
                      <span class="text-sm text-stone-500">von 100 Punkten</span>
                    </div>

                    <%= if @submission.feedback && @submission.feedback != "" do %>
                      <div class="mt-4 bg-white rounded-lg p-4 border border-emerald-100">
                        <p class="text-[13px] font-semibold text-stone-700 mb-2">
                          Feedback vom Lehrer:
                        </p>
                        <p class="text-[14px] text-stone-600 whitespace-pre-wrap leading-relaxed">
                          {@submission.feedback}
                        </p>
                      </div>
                    <% end %>

                    <div class="mt-3 text-[12px] text-stone-500">
                      Bewertet am {format_date(@submission.graded_at)}
                    </div>
                  </div>
                </div>
              </div>
            <% else %>
              <%!-- Task Completed - Success Message --%>
              <div class="border border-stone-200 rounded-[18px] bg-white shadow-sm overflow-hidden">
                <div class="flex flex-col items-center text-center px-10 py-16 bg-white">
                  <div class="text-[56px] leading-none mb-1.5 animate-bounce">
                    {@success_emoji}
                  </div>

                  <div class="w-6 h-[1.5px] bg-stone-200 rounded-sm my-5"></div>

                  <h3 class="font-serif text-[34px] font-normal text-stone-900 leading-tight mb-2.5 animate-[fadeUp_0.4s_0.15s_ease_both]">
                    Aufgabe <em class="italic text-emerald-500">erledigt.</em>
                  </h3>

                  <p class="text-[14px] text-stone-400 leading-relaxed max-w-[300px] mb-8 animate-[fadeUp_0.4s_0.2s_ease_both]">
                    Sehr gute Arbeit — du hast diese Aufgabe erfolgreich abgeschlossen.
                  </p>

                  <div class="animate-[fadeUp_0.4s_0.25s_ease_both]">
                    <.link
                      navigate={~p"/student/courses/#{@task.course_id}"}
                      class="inline-flex items-center gap-2 px-5 py-2.5 text-[13px] font-semibold text-white bg-emerald-500 hover:bg-emerald-600 active:scale-[0.97] rounded-[10px] shadow-[0_2px_8px_rgba(16,185,129,0.25)] transition-all duration-150"
                    >
                      Weiter
                      <svg
                        width="14"
                        height="14"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                        stroke-width="2.5"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M14 5l7 7m0 0l-7 7m7-7H3"
                        />
                      </svg>
                    </.link>
                  </div>
                </div>
              </div>
            <% end %>
          <% else %>
            <%!-- Show form only if task is not completed --%>
            <%= if @task.link do %>
              <%!-- Tally Form Embed (no card wrapper) --%>
              <iframe
                data-tally-src={"#{build_tally_url(@task.link, @task.id, @current_scope.user)}"}
                loading="lazy"
                width="100%"
                height="800"
                frameborder="0"
                marginheight="0"
                marginwidth="0"
                title={@task.name}
                class="w-full min-h-[800px]"
              >
              </iframe>
            <% else %>
              <%!-- No Link Available --%>
              <div class="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
                <.icon name="hero-document-text" class="mx-auto h-12 w-12 text-gray-400" />
                <h3 class="mt-2 text-sm font-semibold text-gray-900">Kein Formular verfügbar</h3>

                <p class="mt-1 text-sm text-gray-500">
                  Für diese Aufgabe ist kein Formular-Link hinterlegt.
                </p>
              </div>
            <% end %>
          <% end %>
        </div>
      </Layouts.app>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    # Subscribe to real-time updates for this student's submissions
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Tasky.PubSub,
        "student:#{socket.assigns.current_scope.user.id}:submissions"
      )
    end

    # Convert string ID to integer
    task_id = String.to_integer(id)

    # Get or create submission for this task
    {:ok, submission} =
      Tasks.get_or_create_submission(
        socket.assigns.current_scope,
        task_id
      )

    # Preload the task through the submission
    submission = Tasky.Repo.preload(submission, :task)
    task = submission.task

    # Auto-start the task if it's not started yet
    submission =
      if submission.status in ["not_started", "open", "draft"] do
        case Tasks.update_submission_status(
               socket.assigns.current_scope,
               submission.id,
               "in_progress"
             ) do
          {:ok, updated_submission} ->
            Tasky.Repo.preload(updated_submission, :task, force: true)

          {:error, _} ->
            submission
        end
      else
        submission
      end

    # Check if preview mode is enabled
    preview_mode = Map.get(params, "preview") == "true"

    {:ok,
     socket
     |> assign(:page_title, task.name)
     |> assign(:task, task)
     |> assign(:submission, submission)
     |> assign(:preview_mode, preview_mode)
     |> assign(:success_emoji, random_success_emoji())}
  end

  @impl true
  def handle_info({:submission_updated, updated_submission}, socket) do
    # Only update if this is the current task's submission
    if updated_submission.id == socket.assigns.submission.id do
      # Preload task for the updated submission
      updated_submission = Tasky.Repo.preload(updated_submission, :task, force: true)

      {:noreply, assign(socket, :submission, updated_submission)}
    else
      {:noreply, socket}
    end
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%d.%m.%Y um %H:%M")
  end

  # Pick a random success emoji to celebrate task completion
  defp random_success_emoji do
    success_emojis = ["🎉", "🚀", "⭐", "🎊", "✨", "🏆", "🎯", "💫", "🌟", "👏"]
    Enum.random(success_emojis)
  end

  # Extract Tally embed URL from a regular Tally link
  # Converts https://tally.so/r/Pd6yr1 to https://tally.so/embed/Pd6yr1
  defp extract_tally_embed_url(link) do
    cond do
      String.contains?(link, "/embed/") ->
        link

      String.contains?(link, "/r/") ->
        String.replace(link, "/r/", "/embed/")

      true ->
        # If it's already a full URL, return as is
        link
    end
  end

  # Build complete Tally URL with hidden fields
  # According to Tally docs, query parameters are automatically forwarded to hidden fields
  defp build_tally_url(link, task_id, user) do
    base_url = extract_tally_embed_url(link)

    # Check if URL already has query parameters
    separator = if String.contains?(base_url, "?"), do: "&", else: "?"

    # Build all parameters in one string
    params =
      [
        "alignLeft=1",
        "hideTitle=1",
        "transparentBackground=1",
        "dynamicHeight=1",
        "task_id=#{task_id}",
        "user_id=#{user.id}",
        "user_name=#{URI.encode_www_form(user.email)}"
      ]
      |> Enum.join("&")

    "#{base_url}#{separator}#{params}"
  end
end
