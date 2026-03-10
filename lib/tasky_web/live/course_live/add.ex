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
                disabled={@loading || @adding}
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
        <%= if is_nil(@current_scope.user.tally_api_key) do %>
          <div class="bg-gradient-to-br from-amber-50 to-orange-50 rounded-[16px] border border-amber-200 p-8 shadow-[0_2px_12px_rgba(251,191,36,0.15)]">
            <div class="flex flex-col items-center text-center">
              <div class="w-14 h-14 bg-amber-100 rounded-[12px] flex items-center justify-center mb-4">
                <svg
                  width="28"
                  height="28"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  stroke-width="2"
                  class="text-amber-600"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"
                  />
                </svg>
              </div>
              <div class="w-full max-w-[480px]">
                <h3 class="text-lg font-semibold text-amber-900 mb-2">
                  Tally API Key erforderlich
                </h3>
                <p class="text-base text-amber-800 leading-relaxed mb-6">
                  Tasky funktioniert zusammen mit Tally. Damit diese beide kommunizieren können, musst du einen API Key hinterlegen.
                </p>
                <.link
                  navigate={~p"/settings/tally"}
                  class="inline-flex items-center gap-2 bg-amber-600 text-white text-[15px] font-semibold px-6 py-3 rounded-[10px] shadow-[0_2px_8px_rgba(217,119,6,0.25)] transition-all duration-150 hover:bg-amber-700 active:scale-[0.98]"
                >
                  <svg
                    width="18"
                    height="18"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    stroke-width="2"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"
                    />
                  </svg>
                  API Key jetzt einrichten
                </.link>
              </div>
            </div>
          </div>
        <% else %>
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

                  <h3 class="text-base font-semibold text-stone-700 mb-2">
                    Keine Formulare gefunden
                  </h3>

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
                  <div class="flex items-center justify-between">
                    <div>
                      <h2 class="text-lg font-semibold text-stone-800">
                        Verfügbare Tally Formulare
                      </h2>

                      <p class="text-sm text-stone-500 mt-1">
                        {length(@forms)} Formulare gefunden
                        <%= if MapSet.size(@selected_form_ids) > 0 do %>
                          <span class="inline-flex items-center ml-2 text-[11px] font-semibold px-2.5 py-0.5 rounded-full whitespace-nowrap tracking-[0.01em] bg-sky-100 text-sky-700">
                            {MapSet.size(@selected_form_ids)} ausgewählt
                          </span>
                        <% end %>
                      </p>
                    </div>

                    <%= if MapSet.size(@selected_form_ids) > 0 do %>
                      <button
                        type="button"
                        phx-click="add_selected_forms"
                        disabled={@adding}
                        class="inline-flex items-center gap-2 bg-sky-500 text-white text-[13px] font-semibold px-4 py-2 rounded-[8px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        <%= if @adding do %>
                          <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin" />
                          Wird hinzugefügt...
                        <% else %>
                          <.icon name="hero-plus" class="w-4 h-4" />
                          Ausgewählte hinzufügen ({MapSet.size(@selected_form_ids)})
                        <% end %>
                      </button>
                    <% end %>
                  </div>
                </div>

                <ul class="list-none p-0 m-0">
                  <li
                    :for={form <- @forms}
                    class={[
                      "flex items-start gap-5 px-6 py-5 border-b border-stone-100 transition-colors duration-150 last:border-b-0",
                      form_already_added?(form["id"], @existing_form_ids) &&
                        "bg-stone-50 opacity-60",
                      !form_already_added?(form["id"], @existing_form_ids) &&
                        "bg-white hover:bg-stone-50"
                    ]}
                  >
                    <%= if form_already_added?(form["id"], @existing_form_ids) do %>
                      <div class="w-5 h-5 mt-2 shrink-0"></div>
                    <% else %>
                      <label class="flex items-center justify-center w-5 h-5 mt-2 shrink-0 cursor-pointer">
                        <input
                          type="checkbox"
                          phx-click="toggle_form_selection"
                          phx-value-form_id={form["id"]}
                          checked={MapSet.member?(@selected_form_ids, form["id"])}
                          disabled={@adding}
                          class="w-5 h-5 rounded-[4px] border-2 border-stone-300 text-sky-500 focus:ring-2 focus:ring-sky-500 focus:ring-offset-0 transition-colors duration-150 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                        />
                      </label>
                    <% end %>

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
                      <% end %>
                    </div>
                  </li>
                </ul>
              <% end %>
            <% end %>
          </div>
        <% end %>
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
     |> assign(:adding, false)
     |> assign(:selected_form_ids, MapSet.new())
     |> assign(:existing_form_ids, existing_form_ids)}
  end

  @impl true
  def handle_event("toggle_form_selection", %{"form_id" => form_id}, socket) do
    selected_form_ids = socket.assigns.selected_form_ids

    new_selected =
      if MapSet.member?(selected_form_ids, form_id) do
        MapSet.delete(selected_form_ids, form_id)
      else
        MapSet.put(selected_form_ids, form_id)
      end

    {:noreply, assign(socket, :selected_form_ids, new_selected)}
  end

  @impl true
  def handle_event("add_selected_forms", _params, socket) do
    selected_form_ids = socket.assigns.selected_form_ids

    if MapSet.size(selected_form_ids) == 0 do
      {:noreply, socket}
    else
      # Start adding process
      socket = assign(socket, :adding, true)

      # Get selected forms with their data
      selected_forms =
        socket.assigns.forms
        |> Enum.filter(fn form -> MapSet.member?(selected_form_ids, form["id"]) end)

      # Send message to process forms asynchronously
      send(self(), {:process_selected_forms, selected_forms})

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh_forms", _params, socket) do
    send(self(), :load_forms)

    {:noreply, assign(socket, :loading, true)}
  end

  @impl true
  def handle_info(:load_forms, socket) do
    case Client.list_forms(socket.assigns.current_scope) do
      {:ok, forms} ->
        # Sort forms alphabetically by name (A to Z, case insensitive)
        sorted_forms = Enum.sort_by(forms, fn form -> String.downcase(form["name"]) end)

        {:noreply,
         socket
         |> assign(:forms, sorted_forms)
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

  @impl true
  def handle_info({:process_selected_forms, selected_forms}, socket) do
    course = socket.assigns.course
    current_position = length(course.tasks)

    results =
      selected_forms
      |> Enum.with_index(1)
      |> Enum.map(fn {form, index} ->
        task_attrs = %{
          name: form["name"],
          link: Client.form_url(form["id"]),
          position: current_position + index,
          status: "published",
          course_id: course.id,
          tally_form_id: form["id"]
        }

        case Tasks.create_task(socket.assigns.current_scope, task_attrs) do
          {:ok, _task} ->
            # Create webhook for the form
            webhook_url = "https://roxann-fluttery-jacqueline.ngrok-free.dev/api/webhooks/tally"

            case Client.create_webhook(socket.assigns.current_scope, form["id"], webhook_url) do
              {:ok, _webhook} ->
                require Logger
                Logger.info("Webhook created successfully for form #{form["id"]}")

              {:error, reason} ->
                require Logger

                Logger.warning(
                  "Failed to create webhook for form #{form["id"]}: #{inspect(reason)}"
                )
            end

            {:ok, form["id"]}

          {:error, changeset} ->
            {:error, form["id"], changeset}
        end
      end)

    # Count successes and failures
    successes = Enum.count(results, fn result -> match?({:ok, _}, result) end)
    failures = Enum.count(results, fn result -> match?({:error, _, _}, result) end)

    # Update existing form IDs with successful additions
    new_form_ids =
      results
      |> Enum.filter(fn result -> match?({:ok, _}, result) end)
      |> Enum.map(fn {:ok, form_id} -> form_id end)

    existing_form_ids = new_form_ids ++ socket.assigns.existing_form_ids

    # Prepare flash message
    socket =
      cond do
        failures == 0 ->
          message =
            if successes == 1 do
              "1 Lerneinheit erfolgreich hinzugefügt"
            else
              "#{successes} Lerneinheiten erfolgreich hinzugefügt"
            end

          put_flash(socket, :info, message)

        successes == 0 ->
          put_flash(socket, :error, "Fehler beim Hinzufügen der Lerneinheiten")

        true ->
          put_flash(
            socket,
            :info,
            "#{successes} von #{successes + failures} Lerneinheiten erfolgreich hinzugefügt"
          )
      end

    {:noreply,
     socket
     |> assign(:adding, false)
     |> assign(:selected_form_ids, MapSet.new())
     |> assign(:existing_form_ids, existing_form_ids)}
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
