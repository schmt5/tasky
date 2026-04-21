defmodule TaskyWeb.Guest.EnrollLive do
  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.guest flash={@flash}>
      <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
        <div class="w-full max-w-md">
          <%!-- Exam Header Card --%>
          <div class="text-center mb-8">
            <div class="w-16 h-16 rounded-2xl bg-sky-50 flex items-center justify-center mx-auto mb-4">
              <.icon name="hero-academic-cap" class="w-8 h-8 text-sky-500" />
            </div>
            <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
              {@exam.name}
            </h1>
            <p class="text-stone-500 text-sm">
              Melde dich für die Prüfung an, um teilzunehmen.
            </p>
          </div>

          <%!-- Enrollment Form --%>
          <div class="bg-white rounded-2xl border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] p-6">
            <.form for={@form} id="enrollment-form" phx-change="validate" phx-submit="enroll">
              <div class="space-y-4">
                <.input
                  field={@form[:firstname]}
                  type="text"
                  label="Vorname"
                  placeholder="Dein Vorname"
                  required
                />
                <.input
                  field={@form[:lastname]}
                  type="text"
                  label="Nachname"
                  placeholder="Dein Nachname"
                  required
                />
              </div>

              <div class="mt-6">
                <button
                  type="submit"
                  id="enroll-submit-btn"
                  class="w-full inline-flex items-center justify-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-3 rounded-xl shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-arrow-right-circle" class="w-5 h-5" /> Anmelden
                </button>
              </div>
            </.form>
          </div>

          <p class="text-center text-xs text-stone-400 mt-4">
            Lehrperson: {@exam.teacher.email}
          </p>
        </div>
      </div>
    </Layouts.guest>
    """
  end

  @impl true
  def mount(%{"enrollment_token" => enrollment_token}, _session, socket) do
    exam = Exams.get_exam_by_enrollment_token!(enrollment_token)

    if exam.status != "open" do
      {:ok,
       socket
       |> put_flash(:error, "Diese Prüfung ist aktuell nicht zur Anmeldung geöffnet.")
       |> push_navigate(to: ~p"/")}
    else
      form = to_form(%{"firstname" => "", "lastname" => ""}, as: :enrollment)

      {:ok,
       socket
       |> assign(:page_title, "Anmeldung – #{exam.name}")
       |> assign(:exam, exam)
       |> assign(:form, form)}
    end
  end

  @impl true
  def handle_event("validate", %{"enrollment" => params}, socket) do
    form = to_form(params, as: :enrollment)
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("enroll", %{"enrollment" => params}, socket) do
    exam = socket.assigns.exam

    case Exams.create_exam_submission(exam, params) do
      {:ok, submission} ->
        {:noreply, push_navigate(socket, to: ~p"/guest/exam/#{submission.exam_token}")}

      {:error, :exam_not_open} ->
        {:noreply,
         socket
         |> put_flash(:error, "Diese Prüfung ist nicht mehr zur Anmeldung geöffnet.")
         |> push_navigate(to: ~p"/")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :enrollment))}
    end
  end
end
