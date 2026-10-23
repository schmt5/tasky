defmodule TaskyWeb.ExamLive.Form do
  use TaskyWeb, :live_view

  alias Tasky.Exams
  alias Tasky.Exams.Exam
  alias TaskyWeb.ExamComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: "Neue Prüfung"}
            ]} />
          </div>

          <div class="flex items-center gap-3 mb-3">
            <.back_button navigate={~p"/exams"} tooltip="Zurück zu Prüfungen" />
            <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
              {@page_title}
            </h1>
          </div>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Gib deiner neuen Prüfung einen Namen und lege fest, wie Lernende darin schreiben.
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

              <ExamComponents.answer_mode_picker
                field={@form[:answer_mode]}
                legend="Wie schreiben Lernende?"
              />

              <div class="flex items-center gap-3 pt-4 border-t border-stone-100">
                <.button
                  phx-disable-with="Speichert..."
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  Prüfung erstellen
                </.button>
                <.link
                  navigate={~p"/exams"}
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
  def mount(_params, _session, socket) do
    exam = %Exam{}

    {:ok,
     socket
     |> assign(:page_title, "Neue Prüfung")
     |> assign(:exam, exam)
     |> assign(:form, to_form(Exams.change_new_exam(exam), as: :exam))}
  end

  # Validates through the create changeset — it is the only one that casts
  # :answer_mode, so anything else would drop the radio's value.
  @impl true
  def handle_event("validate", %{"exam" => exam_params}, socket) do
    changeset = Exams.change_new_exam(socket.assigns.exam, exam_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate, as: :exam))}
  end

  def handle_event("save", %{"exam" => exam_params}, socket) do
    case Exams.create_exam(socket.assigns.current_scope, exam_params) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> put_flash(:info, "Prüfung erfolgreich erstellt")
         |> push_navigate(to: ~p"/exams/#{exam}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :exam))}
    end
  end
end
