defmodule TaskyWeb.CourseLive.Students do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Accounts
  alias Tasky.Classes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-sky-500">
              Studentenverwaltung
            </div>
            
            <div class="flex items-center gap-2">
              <.link
                navigate={~p"/courses/#{@course}"}
                class="inline-flex items-center gap-1.5 text-[13px] font-semibold text-stone-600 hover:text-stone-900 transition-colors duration-150"
              >
                <.icon name="hero-arrow-left" class="w-4 h-4" /> Zurück zum Kurs
              </.link>
            </div>
          </div>
          
          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Eingeschriebene Studenten
          </h1>
          
          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Verwalten Sie die Studenten für den Kurs "{@course.name}"
          </p>
        </div>
      </div>
      
      <div class="max-w-6xl mx-auto px-8 pb-8">
        <%!-- Students Section --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="flex items-center justify-between p-6 border-b border-stone-100">
            <div>
              <h2 class="text-lg font-semibold text-stone-800">Eingeschriebene Studenten</h2>
              
              <p class="text-sm text-stone-500 mt-1">
                {if @has_students, do: "#{@student_count} Studenten", else: "Keine Studenten"}
              </p>
            </div>
            
            <button
              type="button"
              phx-click="show_enroll_modal"
              class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
            >
              <.icon name="hero-user-plus" class="w-4 h-4" /> Studenten einschreiben
            </button>
          </div>
          
          <ul :if={@has_students} id="enrolled-students" phx-update="stream" class="list-none p-0 m-0">
            <li
              :for={{id, student} <- @streams.enrolled_students}
              id={id}
              class="flex items-center justify-between px-6 py-4 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 hover:bg-stone-50"
            >
              <div class="flex items-center gap-3">
                <div class="w-9 h-9 rounded-full flex items-center justify-center shrink-0 bg-stone-100 text-stone-600">
                  <.icon name="hero-user-circle" class="w-5 h-5" />
                </div>
                 <span class="text-[15px] font-medium text-stone-800">{student.email}</span>
              </div>
              
              <button
                type="button"
                phx-click={
                  JS.push("unenroll_student", value: %{student_id: student.id}) |> hide("##{id}")
                }
                data-confirm="Sind Sie sicher, dass Sie diesen Studenten ausschreiben möchten?"
                class="inline-flex items-center gap-2 text-red-600 text-[13px] font-medium px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-red-100 hover:text-red-700"
              >
                <.icon name="hero-x-mark" class="w-4 h-4" /> Ausschreiben
              </button>
            </li>
          </ul>
          
          <div :if={!@has_students} class="flex flex-col items-center text-center px-8 py-16 bg-white">
            <div class="w-14 h-14 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-5">
              <.icon name="hero-users" class="w-6 h-6" />
            </div>
            
            <h3 class="text-base font-semibold text-stone-700 mb-2">Noch keine Studenten</h3>
            
            <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6] mb-6">
              Schreiben Sie Studenten ein, um zu beginnen.
            </p>
            
            <button
              type="button"
              phx-click="show_enroll_modal"
              class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
            >
              <.icon name="hero-user-plus" class="w-4 h-4" /> Erste Studenten einschreiben
            </button>
          </div>
        </div>
      </div>
       <%!-- Enrollment Modal --%>
      <%= if @show_enroll_modal do %>
        <dialog
          id="enroll-modal"
          class="modal modal-open"
          phx-window-keydown="hide_enroll_modal"
          phx-key="escape"
        >
          <%!-- Modal backdrop --%>
          <div class="modal-backdrop bg-stone-900/50" phx-click="hide_enroll_modal"></div>
           <%!-- Modal box --%>
          <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
            <div class="p-6 border-b border-stone-100">
              <h3 class="text-lg font-semibold text-stone-800">Studenten einschreiben</h3>
            </div>
            
            <div class="p-6">
              <%!-- Class Filter --%>
              <.form for={%{}} phx-change="filter_by_class" class="mb-4">
                <.input
                  type="select"
                  name="class_id"
                  label="Nach Klasse filtern"
                  value={@selected_class_id}
                  prompt="Alle Klassen"
                  options={Enum.map(@classes, fn class -> {class.name, class.id} end)}
                />
              </.form>
               <%!-- Batch Enroll Button --%>
              <%= if @selected_class_id && !Enum.empty?(@unenrolled_students) do %>
                <div class="mb-4 p-4 bg-sky-50 rounded-[10px] border border-sky-100">
                  <div class="flex items-center justify-between gap-4">
                    <div class="flex-1">
                      <p class="text-sm font-medium text-sky-900 mb-1">Alle Studenten einschreiben</p>
                      
                      <p class="text-xs text-sky-700">
                        {length(@unenrolled_students)} Studenten aus dieser Klasse gleichzeitig einschreiben
                      </p>
                    </div>
                    
                    <button
                      type="button"
                      phx-click="enroll_all_from_class"
                      class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-4 py-2 rounded-[8px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] whitespace-nowrap"
                    >
                      <.icon name="hero-user-group" class="w-4 h-4" /> Alle einschreiben
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
            
            <div class="px-6 pb-6">
              <div class="space-y-2 max-h-96 overflow-y-auto">
                <div
                  :for={student <- @unenrolled_students}
                  class="flex items-center justify-between p-3 bg-stone-50 rounded-[10px] hover:bg-stone-100 transition-colors duration-150"
                >
                  <div class="flex items-center gap-3">
                    <div class="w-8 h-8 rounded-full flex items-center justify-center shrink-0 bg-stone-200 text-stone-600">
                      <.icon name="hero-user-circle" class="w-5 h-5" />
                    </div>
                     <span class="text-[15px] text-stone-800">{student.email}</span>
                  </div>
                  
                  <button
                    type="button"
                    phx-click="enroll_student"
                    phx-value-student_id={student.id}
                    class="inline-flex items-center gap-2 bg-sky-500 text-white text-[13px] font-semibold px-3.5 py-1.5 rounded-[6px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                  >
                    Einschreiben
                  </button>
                </div>
              </div>
              
              <div
                :if={Enum.empty?(@unenrolled_students)}
                class="text-center py-12 text-stone-500"
              >
                <div class="w-12 h-12 rounded-[10px] bg-stone-100 flex items-center justify-center text-stone-400 mx-auto mb-3">
                  <.icon name="hero-check-circle" class="w-6 h-6" />
                </div>
                
                <p class="text-sm">Alle Studenten sind bereits in diesem Kurs eingeschrieben.</p>
              </div>
            </div>
            
            <div class="p-6 border-t border-stone-100 flex justify-end">
              <button
                type="button"
                phx-click="hide_enroll_modal"
                class="inline-flex items-center gap-2 text-stone-600 text-sm font-medium px-5 py-2.5 rounded-[10px] transition-all duration-150 hover:bg-stone-100 hover:text-stone-800"
              >
                Schließen
              </button>
            </div>
          </div>
        </dialog>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    course = Courses.get_course!(socket.assigns.current_scope, id)
    enrolled_students = Courses.list_enrolled_students(course.id)

    {:ok,
     socket
     |> assign(:page_title, "Studenten - #{course.name}")
     |> assign(:course, course)
     |> assign(:show_enroll_modal, false)
     |> assign(:unenrolled_students, [])
     |> assign(:classes, [])
     |> assign(:selected_class_id, nil)
     |> assign(:has_students, length(enrolled_students) > 0)
     |> assign(:student_count, length(enrolled_students))
     |> stream(:enrolled_students, enrolled_students)}
  end

  @impl true
  def handle_event("show_enroll_modal", _params, socket) do
    unenrolled_students = Courses.list_unenrolled_students(socket.assigns.course.id)
    classes = Classes.list_classes()

    {:noreply,
     socket
     |> assign(:show_enroll_modal, true)
     |> assign(:unenrolled_students, unenrolled_students)
     |> assign(:classes, classes)
     |> assign(:selected_class_id, nil)}
  end

  def handle_event("hide_enroll_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_enroll_modal, false)
     |> assign(:unenrolled_students, [])
     |> assign(:classes, [])
     |> assign(:selected_class_id, nil)}
  end

  def handle_event("filter_by_class", %{"class_id" => ""}, socket) do
    unenrolled_students = Courses.list_unenrolled_students(socket.assigns.course.id)

    {:noreply,
     socket
     |> assign(:unenrolled_students, unenrolled_students)
     |> assign(:selected_class_id, nil)}
  end

  def handle_event("filter_by_class", %{"class_id" => class_id}, socket) do
    class_id = String.to_integer(class_id)
    unenrolled_students = Courses.list_unenrolled_students(socket.assigns.course.id, class_id)

    {:noreply,
     socket
     |> assign(:unenrolled_students, unenrolled_students)
     |> assign(:selected_class_id, class_id)}
  end

  def handle_event("enroll_all_from_class", _params, socket) do
    case socket.assigns.unenrolled_students do
      [] ->
        {:noreply, put_flash(socket, :info, "Keine Studenten zum Einschreiben verfügbar")}

      students ->
        results =
          Enum.map(students, fn student ->
            Courses.enroll_student(socket.assigns.course.id, student.id)
          end)

        success_count = Enum.count(results, fn {status, _} -> status == :ok end)
        enrolled_students = Courses.list_enrolled_students(socket.assigns.course.id)
        new_count = length(enrolled_students)

        # Clear the filter and refresh the list
        unenrolled_students = Courses.list_unenrolled_students(socket.assigns.course.id)

        socket =
          socket
          |> assign(:has_students, new_count > 0)
          |> assign(:student_count, new_count)
          |> assign(:unenrolled_students, unenrolled_students)
          |> assign(:selected_class_id, nil)
          |> stream(:enrolled_students, enrolled_students, reset: true)

        {:noreply,
         put_flash(
           socket,
           :info,
           "#{success_count} Studenten wurden erfolgreich eingeschrieben"
         )}
    end
  end

  def handle_event("enroll_student", %{"student_id" => student_id}, socket) do
    student_id = String.to_integer(student_id)

    case Courses.enroll_student(socket.assigns.course.id, student_id) do
      {:ok, _enrollment} ->
        student = Accounts.get_user!(student_id)

        unenrolled_students =
          Enum.reject(socket.assigns.unenrolled_students, &(&1.id == student_id))

        {:noreply,
         socket
         |> put_flash(:info, "Student enrolled successfully")
         |> assign(:has_students, true)
         |> assign(:student_count, socket.assigns.student_count + 1)
         |> stream_insert(:enrolled_students, student)
         |> assign(:unenrolled_students, unenrolled_students)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to enroll student")}
    end
  end

  def handle_event("unenroll_student", %{"student_id" => student_id}, socket) do
    student_id = String.to_integer(student_id)

    case Courses.unenroll_student(socket.assigns.course.id, student_id) do
      {:ok, _} ->
        student = Accounts.get_user!(student_id)
        enrolled_students = Courses.list_enrolled_students(socket.assigns.course.id)

        new_count = length(enrolled_students)

        {:noreply,
         socket
         |> put_flash(:info, "Student unenrolled successfully")
         |> assign(:has_students, new_count > 0)
         |> assign(:student_count, new_count)
         |> stream_delete(:enrolled_students, student)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unenroll student")}
    end
  end
end
