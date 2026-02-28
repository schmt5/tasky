defmodule TaskyWeb.CourseLive.Add do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Tasks
  alias Tasky.Tally.Client

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-sky-500">
              Kursverwaltung
            </div>
            
            <div class="flex items-center gap-2">
              <.link
                navigate={~p"/courses/#{@course}"}
                class="inline-flex items-center gap-1.5 text-[13px] font-semibold text-stone-600 hover:text-stone-900 transition-colors duration-150"
              >
                <.icon name="hero-arrow-left" class="w-4 h-4" /> Zurück
              </.link>
              <button
                type="button"
                phx-click="refresh_forms"
                disabled={@loading}
                class="inline-flex items-center gap-2 bg-stone-100 text-stone-700 text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-stone-200 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <.icon name="hero-arrow-path" class={["w-4 h-4", @loading && "animate-spin"]} />
                Aktualisieren
              </button>
            </div>
          </div>
          
          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Lerneinheiten hinzufügen
          </h1>
          
          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Fügen Sie neue Lerneinheiten zu
            <span class="font-medium text-stone-700">"{@course.name}"</span>
            hinzu
          </p>
        </div>
      </div>
       <%!-- Forms List --%>
      <div class="max-w-6xl mx-auto px-8 pb-8">
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <%= if @loading do %>
            <div class="flex flex-col items-center justify-center py-16">
              <div class="w-14 h-14 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-500 mb-4">
                <.icon name="hero-arrow-path" class="w-6 h-6 animate-spin" />
              </div>
              
              <p class="text-stone-600 font-medium">Lade Tally Formulare...</p>
            </div>
          <% else %>
            <%= if @forms == [] do %>
              <div class="flex flex-col items-center text-center px-8 py-16 bg-white">
                <div class="w-14 h-14 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-5">
                  <.icon name="hero-document-text" class="w-6 h-6" />
                </div>
                
                <h3 class="text-base font-semibold text-stone-700 mb-2">Keine Formulare gefunden</h3>
                
                <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6] mb-6">
                  Es wurden keine Tally Formulare gefunden. Erstellen Sie zuerst Formulare in Tally.
                </p>
                
                <button
                  type="button"
                  phx-click="refresh_forms"
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-arrow-path" class="w-4 h-4" /> Erneut laden
                </button>
              </div>
            <% else %>
              <div class="p-6 border-b border-stone-100">
                <h2 class="text-lg font-semibold text-stone-800">Verfügbare Tally Formulare</h2>
                
                <p class="text-sm text-stone-500 mt-1">{length(@forms)} Formulare gefunden</p>
              </div>
              
              <ul class="list-none p-0 m-0">
                <li
                  :for={form <- @forms}
                  class="flex items-start gap-5 px-6 py-5 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 hover:bg-stone-50"
                >
                  <div class="w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5 bg-sky-100 text-sky-600">
                    <.icon name="hero-document-text" class="w-5 h-5" />
                  </div>
                  
                  <div class="flex-1 min-w-0 flex flex-col gap-1.5">
                    <div class="flex items-center gap-2.5 flex-wrap">
                      <h3 class="text-[15px] font-semibold text-stone-800 leading-[1.4]">
                        {form["name"]}
                      </h3>
                      
                      <%= if Map.get(form, "status") == "DRAFT" do %>
                        <span class="inline-flex items-center text-[11px] font-semibold px-2.5 py-0.5 rounded-full whitespace-nowrap tracking-[0.01em] bg-amber-100 text-amber-700">
                          Entwurf
                        </span>
                      <% end %>
                    </div>
                    
                    <p class="text-[13px] text-stone-400">Form ID: {form["id"]}</p>
                  </div>
                  
                  <div class="flex items-center gap-2 shrink-0 pt-0.5">
                    <%= if form_already_added?(form["id"], @existing_form_ids) do %>
                      <span class="text-[13px] text-stone-500 italic px-3.5 py-1.5">
                        bereits hinzugefügt
                      </span>
                    <% else %>
                      <button
                        type="button"
                        phx-click="add_form"
                        phx-value-form_id={form["id"]}
                        phx-value-form_name={form["name"]}
                        class="inline-flex items-center gap-2 bg-sky-500 text-white text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                      >
                        <.icon name="hero-plus" class="w-4 h-4" /> Hinzufügen
                      </button>
                    <% end %>
                  </div>
                </li>
              </ul>
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
  def handle_event("refresh_forms", _params, socket) do
    send(self(), :load_forms)

    {:noreply, assign(socket, :loading, true)}
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
