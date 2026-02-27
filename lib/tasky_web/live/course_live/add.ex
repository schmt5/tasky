defmodule TaskyWeb.CourseLive.Add do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Tasks
  alias Tasky.Tally.Client

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Lerneinheiten zu "{@course.name}" hinzufügen
        <:subtitle>Fügen Sie neue Lerneinheiten zu diesem Kurs hinzu</:subtitle>
        <:actions>
          <.button navigate={~p"/courses/#{@course}"}>
            <.icon name="hero-arrow-left" /> Zurück zum Kurs
          </.button>
        </:actions>
      </.header>

      <div class="mt-8">
        <div class="bg-white shadow rounded-lg p-6">
          <%= if @loading do %>
            <div class="flex items-center justify-center py-12">
              <div class="text-gray-600">
                <.icon name="hero-arrow-path" class="w-6 h-6 animate-spin inline-block" />
                Lade Tally Formulare...
              </div>
            </div>
          <% else %>
            <%= if @forms == [] do %>
              <div class="text-center py-12">
                <.icon name="hero-document-text" class="w-12 h-12 mx-auto mb-2 text-gray-400" />
                <p class="text-gray-600">Keine Formulare gefunden.</p>
              </div>
            <% else %>
              <div class="space-y-3">
                <div
                  :for={form <- @forms}
                  class="flex items-center justify-between p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
                >
                  <div class="flex-1">
                    <h3 class="font-medium text-gray-900">{form["name"]}</h3>
                    <p class="text-sm text-gray-500 mt-1">Form ID: {form["id"]}</p>
                  </div>
                  <div>
                    <%= if form_already_added?(form["id"], @existing_form_ids) do %>
                      <span class="text-sm text-gray-600 italic">bereits hinzugefügt</span>
                    <% else %>
                      <.button
                        phx-click="add_form"
                        phx-value-form_id={form["id"]}
                        phx-value-form_name={form["name"]}
                        variant="primary"
                      >
                        Hinzufügen
                      </.button>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    course = Courses.get_course!(socket.assigns.current_scope, id)
    existing_form_ids = get_existing_form_ids(course.id)

    send(self(), :load_forms)

    {:ok,
     socket
     |> assign(:page_title, "Lerneinheiten hinzufügen")
     |> assign(:course, course)
     |> assign(:forms, [])
     |> assign(:loading, true)
     |> assign(:existing_form_ids, existing_form_ids)}
  end

  @impl true
  def handle_event("add_form", %{"form_id" => form_id, "form_name" => form_name}, socket) do
    course = socket.assigns.course
    next_position = length(course.tasks) + 1

    task_attrs = %{
      name: form_name,
      link: Client.form_url(form_id),
      position: next_position,
      status: "published",
      course_id: course.id,
      tally_form_id: form_id
    }

    case Tasks.create_task(socket.assigns.current_scope, task_attrs) do
      {:ok, _task} ->
        # Update existing form IDs
        existing_form_ids = [form_id | socket.assigns.existing_form_ids]

        {:noreply,
         socket
         |> assign(:existing_form_ids, existing_form_ids)
         |> put_flash(:info, "Lerneinheit erfolgreich hinzugefügt")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Fehler beim Hinzufügen der Lerneinheit")}
    end
  end

  @impl true
  def handle_info(:load_forms, socket) do
    case Client.list_forms() do
      {:ok, forms} ->
        {:noreply,
         socket
         |> assign(:forms, forms)
         |> assign(:loading, false)}

      {:error, reason} ->
        require Logger
        Logger.error("Failed to load Tally forms: #{inspect(reason)}")

        error_message =
          case reason do
            :unauthorized -> "Ungültiger API Key"
            :connection_error -> "Verbindung zur Tally API fehlgeschlagen"
            :api_error -> "Tally API Fehler"
            _ -> "Fehler beim Laden der Formulare: #{inspect(reason)}"
          end

        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, error_message)}
    end
  end

  defp get_existing_form_ids(course_id) do
    Tasks.list_tasks_by_course(course_id)
    |> Enum.map(& &1.tally_form_id)
    |> Enum.reject(&is_nil/1)
  end

  defp form_already_added?(form_id, existing_form_ids) do
    form_id in existing_form_ids
  end
end
