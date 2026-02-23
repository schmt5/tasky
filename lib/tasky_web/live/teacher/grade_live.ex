defmodule TaskyWeb.Teacher.GradeLive do
  use TaskyWeb, :live_view

  alias Tasky.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto">
        <.header>
          Grade Submission
          <:subtitle>
            <div class="mt-2">
              <span class="text-gray-700">Student:</span>
              <span class="font-medium">{@submission.student.email}</span>
            </div>

            <div class="mt-1">
              <span class="text-gray-700">Task:</span>
              <span class="font-medium">{@submission.task.name}</span>
            </div>
          </:subtitle>

          <:actions>
            <.button navigate={~p"/tasks/#{@submission.task_id}/submissions"}>
              <.icon name="hero-arrow-left" /> Back to Submissions
            </.button>
          </:actions>
        </.header>

        <div class="mt-8 space-y-8">
          <%!-- Submission Info --%>
          <div class="bg-white shadow rounded-lg p-6">
            <h2 class="text-lg font-semibold text-gray-900 mb-4">Submission Details</h2>

            <.list>
              <:item title="Status">
                <span class={[
                  "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                  @submission.status == "not_started" && "bg-gray-100 text-gray-800",
                  @submission.status == "in_progress" && "bg-yellow-100 text-yellow-800",
                  @submission.status == "completed" && "bg-green-100 text-green-800"
                ]}>
                  {format_status(@submission.status)}
                </span>
              </:item>

              <:item title="Completed At">
                <%= if @submission.completed_at do %>
                  {format_datetime(@submission.completed_at)}
                <% else %>
                  <span class="text-gray-400">Not completed yet</span>
                <% end %>
              </:item>

              <:item :if={@submission.task.link} title="Task Link">
                <a
                  href={@submission.task.link}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-blue-600 hover:text-blue-700 underline flex items-center gap-1"
                >
                  {@submission.task.link}
                  <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                </a>
              </:item>

              <:item :if={@submission.graded_at} title="Previously Graded">
                <div class="space-y-1">
                  <div>
                    <span class="font-medium">{format_datetime(@submission.graded_at)}</span>
                    <%= if @submission.graded_by do %>
                      <span class="text-sm text-gray-500">by {@submission.graded_by.email}</span>
                    <% end %>
                  </div>
                </div>
              </:item>
            </.list>
          </div>
          <%!-- Grading Form --%>
          <div class="bg-white shadow rounded-lg p-6">
            <h2 class="text-lg font-semibold text-gray-900 mb-4">
              <%= if @submission.graded_at do %>
                Update Grade
              <% else %>
                Assign Grade
              <% end %>
            </h2>

            <.form for={@form} id="grade-form" phx-submit="save_grade" class="space-y-6">
              <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
                <div class="sm:col-span-2">
                  <.input
                    field={@form[:points]}
                    type="number"
                    label="Points (0-100)"
                    min="0"
                    max="100"
                    required
                    phx-debounce="500"
                  />
                </div>

                <div class="sm:col-span-2">
                  <.input
                    field={@form[:feedback]}
                    type="textarea"
                    label="Feedback (optional)"
                    rows="6"
                    placeholder="Provide feedback to help the student improve..."
                    phx-debounce="500"
                  />
                </div>
              </div>

              <div class="flex items-center justify-end gap-4 pt-4 border-t border-gray-200">
                <.button
                  type="button"
                  phx-click={JS.navigate(~p"/tasks/#{@submission.task_id}/submissions")}
                >
                  Cancel
                </.button>
                <.button type="submit" variant="primary">
                  <.icon name="hero-check-circle" class="w-5 h-5" />
                  <%= if @submission.graded_at do %>
                    Update Grade
                  <% else %>
                    Save Grade
                  <% end %>
                </.button>
              </div>
            </.form>
          </div>
          <%!-- Current Grade Display (if already graded) --%>
          <%= if @submission.graded_at && !@form.source.action do %>
            <div class="bg-blue-50 border border-blue-200 rounded-lg p-6">
              <h3 class="text-lg font-semibold text-blue-900 mb-3">Current Grade</h3>

              <div class="space-y-3">
                <div>
                  <span class="text-sm font-medium text-blue-700">Points:</span>
                  <span class="ml-2 text-2xl font-bold text-blue-900">
                    {@submission.points}<span class="text-sm text-blue-600">/100</span>
                  </span>
                </div>

                <%= if @submission.feedback && @submission.feedback != "" do %>
                  <div>
                    <span class="text-sm font-medium text-blue-700">Feedback:</span>
                    <p class="mt-1 text-blue-800 whitespace-pre-wrap">{@submission.feedback}</p>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"task_id" => task_id, "id" => submission_id}, _session, socket) do
    submission =
      Tasks.get_submission!(socket.assigns.current_scope, submission_id)
      |> Tasky.Repo.preload([:task, :student, :graded_by])

    # Verify the submission belongs to the specified task
    if submission.task_id != String.to_integer(task_id) do
      raise Ecto.NoResultsError, queryable: Tasky.Tasks.TaskSubmission
    end

    form_data = %{
      "points" => submission.points,
      "feedback" => submission.feedback || ""
    }

    form = to_form(form_data)

    {:ok,
     socket
     |> assign(:page_title, "Grade Submission")
     |> assign(:submission, submission)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("save_grade", %{"points" => points_str, "feedback" => feedback}, socket) do
    points = String.to_integer(points_str)

    case Tasks.grade_submission(
           socket.assigns.current_scope,
           socket.assigns.submission.id,
           %{points: points, feedback: feedback}
         ) do
      {:ok, _submission} ->
        {:noreply,
         socket
         |> put_flash(:info, "Submission graded successfully!")
         |> push_navigate(to: ~p"/tasks/#{socket.assigns.submission.task_id}/submissions")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to grade submission. Please check your input.")
         |> assign(:form, to_form(changeset))}
    end
  end

  defp format_status(status) do
    status
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end
end
