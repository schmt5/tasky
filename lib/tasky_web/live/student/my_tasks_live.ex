defmodule TaskyWeb.Student.MyTasksLive do
  use TaskyWeb, :live_view

  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".OpenLink">
      export default {
        mounted() {
          this.handleEvent("open_link", ({url}) => {
            window.open(url, '_blank');
          });
        }
      }
    </script>
    <div id="my-tasks-container" phx-hook=".OpenLink">
      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <div class="page-header">
          <div class="page-header-eyebrow">Studenten Portal</div>
          <h1>
            Meine <em>Aufgaben</em>
          </h1>
          <p>Sieh dir deine zugewiesenen Aufgaben an und bearbeite sie.</p>
        </div>

        <%= if @submissions != [] do %>
          <%!-- Progress Card --%>
          <div class="content-card mb-6">
            <div class="p-6">
              <div class="flex items-center justify-between mb-3">
                <h3 class="text-sm font-semibold text-stone-700 uppercase tracking-wide">
                  Fortschritt
                </h3>
                <span class="text-3xl font-bold text-sky-600">
                  {if @stats.total > 0,
                    do: round(@stats.completed / @stats.total * 100),
                    else: 0}%
                </span>
              </div>
              <div class="w-full bg-stone-100 rounded-full h-3 overflow-hidden">
                <div
                  class="bg-gradient-to-r from-sky-400 to-sky-600 h-3 rounded-full transition-all duration-500 ease-out"
                  style={"width: #{if @stats.total > 0, do: (@stats.completed / @stats.total * 100), else: 0}%"}
                >
                </div>
              </div>
              <div class="mt-3 flex items-center justify-between text-sm">
                <span class="text-stone-500">
                  {@stats.completed} von {@stats.total} erledigt
                </span>
                <span class="text-stone-400">
                  {@stats.graded} bewertet
                </span>
              </div>
            </div>
          </div>
        <% end %>

        <div class="content-card">
          <%= if @submissions == [] do %>
            <div class="ks-empty">
              <div class="ks-empty-icon">
                <.icon name="hero-document-text" class="w-6 h-6" />
              </div>
              <h3 class="ks-empty-title">Noch keine Aufgaben</h3>
              <p class="ks-empty-desc">
                Du hast noch keine Aufgaben bekommen. Schau später nochmal vorbei!
              </p>
            </div>
          <% else %>
            <ul class="ks-list">
              <li :for={submission <- @submissions} class="ks-item">
                <div class={[
                  "ks-item-icon",
                  submission.status == "completed" && "ks-icon-green",
                  submission.status == "review_approved" && "ks-icon-green",
                  submission.status == "in_progress" && "ks-icon-sky",
                  submission.status == "review_denied" && "ks-icon-red",
                  submission.status in ["open", "draft", "not_started"] && "ks-icon-stone"
                ]}>
                  <%= cond do %>
                    <% submission.status in ["completed", "review_approved"] -> %>
                      <.icon name="hero-check-circle" class="w-5 h-5" />
                    <% submission.status == "review_denied" -> %>
                      <.icon name="hero-x-circle" class="w-5 h-5" />
                    <% submission.status == "in_progress" -> %>
                      <.icon name="hero-arrow-path" class="w-5 h-5" />
                    <% true -> %>
                      <.icon name="hero-document-text" class="w-5 h-5" />
                  <% end %>
                </div>

                <div class="ks-item-main">
                  <div class="ks-item-header">
                    <%= if submission.task.link do %>
                      <div
                        phx-click="mark_in_progress"
                        phx-value-submission-id={submission.id}
                        phx-value-link={"#{submission.task.link}?user_id=#{@current_scope.user.id}&task_id=#{submission.task.id}&user_name=#{@current_scope.user.email}"}
                      >
                        <a
                          href={"#{submission.task.link}?user_id=#{@current_scope.user.id}&task_id=#{submission.task.id}&user_name=#{@current_scope.user.email}"}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="ks-item-title hover:text-sky-600 transition-colors"
                        >
                          {submission.task.name}
                        </a>
                      </div>
                    <% else %>
                      <h3 class="ks-item-title">{submission.task.name}</h3>
                    <% end %>

                    <span class={[
                      "ks-badge",
                      submission.status in ["draft", "not_started"] && "ks-badge-stone",
                      submission.status == "open" && "ks-badge-stone",
                      submission.status == "in_progress" && "ks-badge-sky",
                      submission.status == "completed" && "ks-badge-green",
                      submission.status == "review_approved" && "ks-badge-green",
                      submission.status == "review_denied" && "ks-badge-red"
                    ]}>
                      {format_status(submission.status)}
                    </span>
                  </div>

                  <div class="ks-meta">
                    <span class="ks-meta-item">
                      <.icon name="hero-clock" class="w-3.5 h-3.5" />
                      {format_status(submission.status)}
                    </span>
                  </div>
                </div>

                <div class="ks-item-actions">
                  <%= cond do %>
                    <% submission.status in ["completed", "review_approved"] -> %>
                      <div class="flex items-center gap-2 text-green-600 font-medium text-sm">
                        <.icon name="hero-check-circle" class="w-5 h-5" /> Erledigt
                      </div>
                    <% submission.status == "review_denied" -> %>
                      <div class="flex items-center gap-2 text-red-600 font-medium text-sm">
                        <.icon name="hero-x-circle" class="w-5 h-5" /> Abgelehnt
                      </div>
                    <% submission.task.link -> %>
                      <div
                        phx-click="mark_in_progress"
                        phx-value-submission-id={submission.id}
                        phx-value-link={"#{submission.task.link}?user_id=#{@current_scope.user.id}&task_id=#{submission.task.id}&user_name=#{@current_scope.user.email}"}
                      >
                        <a
                          href={"#{submission.task.link}?user_id=#{@current_scope.user.id}&task_id=#{submission.task.id}&user_name=#{@current_scope.user.email}"}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="btn-custom-primary btn-custom-sm"
                        >
                          {if submission.status in ["not_started", "open", "draft"],
                            do: "Starten",
                            else: "Öffnen"}
                          <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                        </a>
                      </div>
                    <% true -> %>
                      <span class="text-sm text-stone-400">Kein Link</span>
                  <% end %>
                </div>
              </li>
            </ul>
          <% end %>
        </div>
      </Layouts.app>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to real-time updates for this student's submissions
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Tasky.PubSub,
        "student:#{socket.assigns.current_scope.user.id}:submissions"
      )
    end

    submissions = Tasks.list_my_submissions(socket.assigns.current_scope)

    stats = %{
      total: length(submissions),
      completed: Enum.count(submissions, &(&1.status == "completed")),
      graded: Enum.count(submissions, &(&1.status == "review_approved"))
    }

    {:ok,
     socket
     |> assign(:page_title, "My Tasks")
     |> assign(:submissions, submissions)
     |> assign(:stats, stats)}
  end

  defp format_status(status) do
    status
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  @impl true
  def handle_event(
        "mark_in_progress",
        %{"submission-id" => submission_id, "link" => link},
        socket
      ) do
    IO.inspect(submission_id, label: "Received submission_id")
    submission_id = String.to_integer(submission_id)
    submission = Enum.find(socket.assigns.submissions, &(&1.id == submission_id))
    IO.inspect(submission, label: "Found submission")

    # Only mark as in_progress if it's currently open or draft
    IO.inspect(submission && submission.status, label: "Current status")

    socket =
      if submission && submission.status in ["open", "draft", "not_started"] do
        IO.puts("Attempting to update status to in_progress")

        case Tasks.update_submission_status(
               socket.assigns.current_scope,
               submission_id,
               "in_progress"
             ) do
          {:ok, _updated_submission} ->
            IO.puts("Successfully updated to in_progress")
            # Reload submissions to reflect the change
            submissions = Tasks.list_my_submissions(socket.assigns.current_scope)

            stats = %{
              total: length(submissions),
              completed: Enum.count(submissions, &(&1.status == "completed")),
              graded: Enum.count(submissions, &(&1.status == "review_approved"))
            }

            socket
            |> assign(:submissions, submissions)
            |> assign(:stats, stats)

          {:error, changeset} ->
            IO.inspect(changeset, label: "Error updating submission")
            socket
        end
      else
        IO.puts("Submission not found or status not open/draft")
        socket
      end

    # Open the link using JS command
    {:noreply, push_event(socket, "open_link", %{url: link})}
  end

  @impl true
  def handle_info({:submission_updated, _updated_submission}, socket) do
    # Reload all submissions to get the latest state
    submissions = Tasks.list_my_submissions(socket.assigns.current_scope)

    stats = %{
      total: length(submissions),
      completed: Enum.count(submissions, &(&1.status == "completed")),
      graded: Enum.count(submissions, &(&1.status == "review_approved"))
    }

    {:noreply,
     socket
     |> assign(:submissions, submissions)
     |> assign(:stats, stats)
     |> put_flash(:info, "Task status updated!")}
  end
end
