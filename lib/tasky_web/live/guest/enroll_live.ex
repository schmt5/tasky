defmodule TaskyWeb.Guest.EnrollLive do
  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.guest flash={@flash}>
      <div class="min-h-[80vh] flex items-center justify-center px-4 py-12">
        <div class="w-full max-w-md">
          <%= case @state do %>
            <% :invalid -> %>
              <%!-- Unknown enrollment token (mistyped, regenerated, or expired). --%>
              <div class="text-center">
                <div class="w-16 h-16 rounded-2xl bg-stone-100 flex items-center justify-center mx-auto mb-4">
                  <.icon name="hero-link-slash" class="w-8 h-8 text-stone-400" />
                </div>
                <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
                  Einschreibelink ungültig
                </h1>
                <p class="text-stone-500 text-sm leading-relaxed">
                  Dieser Einschreibelink ist ungültig oder abgelaufen. Bitte überprüfe
                  den Link oder wende dich an deine Lehrperson.
                </p>
              </div>
            <% :unavailable -> %>
              <%!-- Exam exists but is not currently open for enrollment. --%>
              <div class="text-center">
                <div class="w-16 h-16 rounded-2xl bg-amber-50 flex items-center justify-center mx-auto mb-4">
                  <.icon name="hero-lock-closed" class="w-8 h-8 text-amber-500" />
                </div>
                <h1 class="font-serif text-3xl text-stone-900 font-normal mb-2">
                  {@exam.name}
                </h1>
                <p class="text-stone-500 text-sm leading-relaxed">
                  Diese Prüfung ist aktuell nicht zur Anmeldung geöffnet. Bitte wende
                  dich an deine Lehrperson.
                </p>
              </div>
            <% :form -> %>
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

              <%!-- Resume card: shown by the hook only if this browser has a saved
                    submission for this exam (e.g. after an accidental tab close). --%>
              <div
                id="resume-offer"
                phx-hook=".ResumeOffer"
                data-exam-id={@exam.id}
                hidden
                class="mb-6"
              >
                <a
                  id="resume-offer-link"
                  href="#"
                  class="block bg-sky-50 border border-sky-200 rounded-2xl p-5 transition-all duration-150 hover:bg-sky-100 active:scale-[0.99]"
                >
                  <div class="flex items-center gap-3">
                    <div class="w-10 h-10 rounded-xl bg-sky-500 flex items-center justify-center shrink-0">
                      <.icon name="hero-arrow-uturn-left" class="w-5 h-5 text-white" />
                    </div>
                    <div class="min-w-0">
                      <p class="text-sm font-semibold text-sky-900">Prüfung fortsetzen</p>
                      <p class="text-xs text-sky-700 mt-0.5">
                        Als <span id="resume-offer-name" class="font-medium"></span>
                      </p>
                    </div>
                    <.icon name="hero-chevron-right" class="w-5 h-5 text-sky-400 ml-auto shrink-0" />
                  </div>
                </a>
                <div class="flex items-center gap-3 my-5">
                  <div class="flex-1 h-px bg-stone-200" />
                  <span class="text-xs text-stone-400">oder neu anmelden</span>
                  <div class="flex-1 h-px bg-stone-200" />
                </div>
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
                    <.input
                      field={@form[:email]}
                      type="email"
                      label="E-Mail"
                      placeholder="deine@email.ch"
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
          <% end %>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ResumeOffer">
        export default {
          mounted() {
            const examId = this.el.dataset.examId;
            if (!examId) return;
            let saved;
            try {
              saved = JSON.parse(localStorage.getItem("tasky:resume:" + examId));
            } catch (_e) {
              saved = null;
            }
            if (!saved || !saved.token) return;

            const link = this.el.querySelector("#resume-offer-link");
            const name = this.el.querySelector("#resume-offer-name");
            if (link) link.setAttribute("href", "/guest/exam/" + saved.token);
            if (name) {
              name.textContent = [saved.firstname, saved.lastname]
                .filter(Boolean)
                .join(" ");
            }
            this.el.hidden = false;
          },
        }
      </script>
    </Layouts.guest>
    """
  end

  @impl true
  def mount(%{"enrollment_token" => enrollment_token}, _session, socket) do
    case Exams.get_exam_by_enrollment_token(enrollment_token) do
      nil ->
        {:ok,
         socket
         |> assign(:page_title, "Einschreibelink ungültig")
         |> assign(:state, :invalid)
         |> assign(:exam, nil)
         |> assign(:form, nil)}

      %{status: status} = exam when status in ["open", "running"] ->
        form =
          to_form(%{"firstname" => "", "lastname" => "", "email" => ""}, as: :enrollment)

        {:ok,
         socket
         |> assign(:page_title, "Anmeldung – #{exam.name}")
         |> assign(:state, :form)
         |> assign(:exam, exam)
         |> assign(:form, form)}

      exam ->
        {:ok,
         socket
         |> assign(:page_title, exam.name)
         |> assign(:state, :unavailable)
         |> assign(:exam, exam)
         |> assign(:form, nil)}
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
        # The exam closed between loading the form and submitting it.
        {:noreply, assign(socket, :state, :unavailable)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :enrollment))}
    end
  end
end
