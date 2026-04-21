defmodule TaskyWeb.ExamLive.Form do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.Exams.Exam

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <%= if @live_action == :new do %>
              <.breadcrumbs crumbs={[
                %{label: "Prüfungen", navigate: ~p"/exams"},
                %{label: "Neue Prüfung"}
              ]} />
            <% else %>
              <.breadcrumbs crumbs={[
                %{label: "Prüfungen", navigate: ~p"/exams"},
                %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
                %{label: "Bearbeiten"}
              ]} />
            <% end %>
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            {@page_title}
          </h1>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            {if @live_action == :new,
              do: "Gib deiner neuen Prüfung einen Namen.",
              else: "Bearbeite die Prüfungsinformationen."}
          </p>
        </div>
      </div>
      <%!-- Form Card --%>
      <div class="max-w-6xl mx-auto px-8 pb-8">
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6">
            <.form
              for={@form}
              id="exam-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-6"
            >
              <.input field={@form[:name]} type="text" label="Prüfungsname" required />

              <%= if @live_action == :edit do %>
                <.input
                  field={@form[:status]}
                  type="select"
                  label="Status"
                  options={[
                    {"Entwurf", "draft"},
                    {"Offen", "open"},
                    {"Laufend", "running"},
                    {"Beendet", "finished"},
                    {"Archiviert", "archived"}
                  ]}
                />

                <.input
                  field={@form[:enrollment_token]}
                  type="text"
                  label="Einschreibeschlüssel"
                  placeholder="Optionaler Token für die Einschreibung..."
                />

                <.input
                  field={@form[:content_json]}
                  type="textarea"
                  label="Inhalt (JSON)"
                  placeholder="z.B. {&quot;fragen&quot;: [...]}"
                  rows="6"
                />

                <.input
                  field={@form[:sample_solution_json]}
                  type="textarea"
                  label="Musterlösung (JSON)"
                  placeholder="z.B. {&quot;antworten&quot;: [...]}"
                  rows="6"
                />
              <% end %>

              <div class="flex items-center gap-3 pt-4 border-t border-stone-100">
                <.button
                  phx-disable-with="Speichert..."
                  class="inline-flex items-center gap-2 bg-amber-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(245,158,11,0.25)] transition-all duration-150 hover:bg-amber-600 active:scale-[0.98]"
                >
                  {if @live_action == :new, do: "Prüfung erstellen", else: "Änderungen speichern"}
                </.button>
                <.link
                  navigate={return_path(@return_to, @exam)}
                  class="inline-flex items-center gap-2 text-stone-500 text-sm font-medium px-5 py-2.5 rounded-[10px] transition-all duration-150 hover:bg-stone-100 hover:text-stone-700"
                >
                  Abbrechen
                </.link>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)
    changeset = Exams.change_exam(exam)

    socket
    |> assign(:page_title, "Prüfung bearbeiten")
    |> assign(:exam, exam)
    |> assign(:form, to_form(changeset, as: :exam))
    |> assign(:content_json, json_encode(exam.content))
    |> assign(:sample_solution_json, json_encode(exam.sample_solution))
  end

  defp apply_action(socket, :new, _params) do
    exam = %Exam{}

    socket
    |> assign(:page_title, "Neue Prüfung")
    |> assign(:exam, exam)
    |> assign(:form, to_form(Exams.change_exam(exam), as: :exam))
    |> assign(:content_json, "")
    |> assign(:sample_solution_json, "")
  end

  @impl true
  def handle_event("validate", %{"exam" => exam_params}, socket) do
    exam_params = process_json_fields(exam_params)
    changeset = Exams.change_exam(socket.assigns.exam, exam_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate, as: :exam))}
  end

  def handle_event("save", %{"exam" => exam_params}, socket) do
    exam_params = process_json_fields(exam_params)
    save_exam(socket, socket.assigns.live_action, exam_params)
  end

  defp save_exam(socket, :edit, exam_params) do
    case Exams.update_exam(socket.assigns.exam, exam_params) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> put_flash(:info, "Prüfung erfolgreich aktualisiert")
         |> push_navigate(to: return_path(socket.assigns.return_to, exam))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :exam))}
    end
  end

  defp save_exam(socket, :new, exam_params) do
    case Exams.create_exam(socket.assigns.current_scope, exam_params) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> put_flash(:info, "Prüfung erfolgreich erstellt")
         |> push_navigate(to: return_path(socket.assigns.return_to, exam))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :exam))}
    end
  end

  defp process_json_fields(params) do
    params
    |> maybe_parse_json("content_json", "content")
    |> maybe_parse_json("sample_solution_json", "sample_solution")
    |> Map.drop(["content_json", "sample_solution_json"])
  end

  defp maybe_parse_json(params, json_key, target_key) do
    case Map.get(params, json_key) do
      nil ->
        params

      "" ->
        Map.put(params, target_key, %{})

      json_string ->
        case Jason.decode(json_string) do
          {:ok, decoded} -> Map.put(params, target_key, decoded)
          {:error, _} -> params
        end
    end
  end

  defp json_encode(nil), do: ""
  defp json_encode(map) when map == %{}, do: ""
  defp json_encode(map), do: Jason.encode!(map, pretty: true)

  defp return_path("index", _exam), do: ~p"/exams"
  defp return_path("show", exam), do: ~p"/exams/#{exam}"
end
