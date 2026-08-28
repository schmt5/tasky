defmodule TaskyWeb.StudentsLive.Edit do
  @moduledoc """
  The teacher-facing edit page for one learner.

  Mirrors `TaskyWeb.Admin.UserEditLive` for a single student, with two
  differences that matter:

    * the class select offers only the scope's own classes, so a student cannot
      be handed to another organization, and
    * there is no organization select at all — a student's organization is
      derived from their class.

  Both rules are enforced again in `Tasky.Accounts.update_student/3`; the select
  is convenience, not the boundary.
  """

  use TaskyWeb, :live_view

  alias Tasky.Accounts
  alias Tasky.Classes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-header">
        <div class="max-w-5xl mx-auto">
          <div class="mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Lernende", navigate: ~p"/students"},
              %{label: full_name(@student)}
            ]} />
          </div>
          <div class="flex items-center gap-3">
            <.back_button navigate={~p"/students"} tooltip="Zurück zu den Lernenden" />
            <h1>
              Lernende <em>bearbeiten</em>
            </h1>
          </div>
        </div>
      </div>

      <div class="max-w-3xl mx-auto mt-10 px-8 pb-8 space-y-6">
        <%!-- Profile header --%>
        <div class="bg-white rounded-[14px] border border-stone-100 p-6 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="flex items-start gap-5">
            <div class="w-16 h-16 rounded-full flex items-center justify-center shrink-0 bg-green-100 text-green-700 text-[20px] font-semibold">
              {initials(@student)}
            </div>

            <div class="flex-1 min-w-0">
              <h1 class="font-serif text-[28px] text-stone-900 leading-[1.2] mb-2 font-normal">
                {full_name(@student)}
              </h1>

              <div class="flex flex-wrap items-center gap-2 mb-3">
                <span class="inline-flex items-center text-[11px] font-semibold px-2 py-0.5 rounded-full bg-stone-100 text-stone-600 whitespace-nowrap">
                  <.icon name="hero-academic-cap" class="w-3 h-3 mr-1" />
                  {if @student.class, do: @student.class.name, else: "Keine Klasse"}
                </span>

                <%= if @student.confirmed_at do %>
                  <span class="inline-flex items-center gap-0.5 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-green-100 text-green-700 whitespace-nowrap">
                    <.icon name="hero-check-circle" class="w-3 h-3" /> Bestätigt
                  </span>
                <% else %>
                  <span class="inline-flex items-center text-[11px] font-semibold px-2 py-0.5 rounded-full bg-stone-100 text-stone-500 whitespace-nowrap">
                    Unbestätigt
                  </span>
                <% end %>
              </div>

              <div class="text-[13px] text-stone-500 space-y-0.5">
                <div class="flex items-center gap-1.5">
                  <.icon name="hero-envelope" class="w-3.5 h-3.5 text-stone-400" />
                  {@student.email}
                </div>
                <div :if={@student.inserted_at} class="flex items-center gap-1.5">
                  <.icon name="hero-calendar" class="w-3.5 h-3.5 text-stone-400" />
                  Mitglied seit {format_date(@student.inserted_at)}
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Profile edit form --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="px-6 py-5 border-b border-stone-100">
            <h2 class="text-lg font-semibold text-stone-800">Profil</h2>
            <p class="text-sm text-stone-500 mt-1">
              Vorname, Nachname, E-Mail-Adresse und Klassenzuordnung
            </p>
          </div>

          <div class="p-6">
            <.form
              for={@profile_form}
              id="student-edit-form"
              phx-submit="update_student"
              phx-change="validate_student"
              class="space-y-5"
            >
              <div class="grid grid-cols-1 gap-5 sm:grid-cols-2">
                <.input field={@profile_form[:firstname]} type="text" label="Vorname" required />
                <.input field={@profile_form[:lastname]} type="text" label="Nachname" required />
              </div>

              <.input
                field={@profile_form[:email]}
                type="email"
                label="E-Mail"
                autocomplete="off"
                required
              />

              <.input
                field={@profile_form[:class_id]}
                type="select"
                label="Klasse"
                prompt="Keine Klasse"
                options={Enum.map(@classes, &{&1.name, &1.id})}
              />

              <div class="bg-amber-50 border border-amber-200 rounded-[10px] p-3">
                <div class="flex items-start gap-2">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-4 h-4 text-amber-600 mt-0.5 shrink-0"
                  />
                  <p class="text-xs text-amber-800 leading-[1.5]">
                    Ohne Klasse gehören Lernende zu keiner Organisation und verschwinden aus dieser Liste — nur die Administration kann sie dann wieder zuordnen.
                  </p>
                </div>
              </div>

              <div class="flex items-center justify-between pt-2">
                <.link
                  navigate={~p"/students"}
                  class="inline-flex items-center gap-1.5 text-sm font-medium text-stone-500 hover:text-stone-700 transition-colors"
                >
                  <.icon name="hero-arrow-left" class="w-4 h-4" /> Zurück
                </.link>
                <.button
                  variant="primary"
                  phx-disable-with="Wird gespeichert..."
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name="hero-check" class="w-4 h-4" /> Speichern
                </.button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Security --%>
        <div class="bg-white rounded-[14px] border border-stone-100 px-6 py-4 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)] flex items-center justify-between gap-4">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-[10px] bg-stone-100 flex items-center justify-center shrink-0">
              <.icon name="hero-key" class="w-5 h-5 text-stone-500" />
            </div>
            <div>
              <h2 class="text-[15px] font-semibold text-stone-800">Passwort</h2>
              <p class="text-[13px] text-stone-500">
                Setze ein neues Passwort für diese Lernende bzw. diesen Lernenden.
              </p>
            </div>
          </div>
          <button
            type="button"
            phx-click="open_password_modal"
            class="inline-flex items-center gap-1.5 text-sm font-medium text-sky-700 hover:text-sky-800 bg-sky-50 hover:bg-sky-100 border border-sky-200 px-3 py-2 rounded-lg transition-all duration-150 shrink-0"
          >
            <.icon name="hero-arrow-path" class="w-4 h-4" /> Zurücksetzen
          </button>
        </div>
      </div>

      <%= if @show_password_modal do %>
        <dialog
          class="modal modal-open"
          phx-window-keydown="close_password_modal"
          phx-key="escape"
        >
          <div class="modal-box max-w-md">
            <div class="flex items-center gap-3 mb-6">
              <div class="w-10 h-10 bg-sky-100 rounded-xl flex items-center justify-center">
                <.icon name="hero-key" class="w-5 h-5 text-sky-600" />
              </div>
              <div>
                <h3 class="text-lg font-semibold text-stone-900">Passwort zurücksetzen</h3>
                <p class="text-sm text-stone-500">{@student.email}</p>
              </div>
            </div>

            <.form
              for={@password_form}
              id={"password-reset-form-#{@student.id}"}
              phx-submit="reset_password"
            >
              <div class="space-y-4">
                <.input
                  field={@password_form[:password]}
                  type="text"
                  label="Neues Passwort"
                  placeholder="Mindestens 8 Zeichen"
                  required
                  phx-mounted={JS.focus()}
                  class="w-full px-4 py-3 text-[15px] text-stone-900 bg-white border border-stone-200 rounded-[10px] transition-all duration-150 placeholder:text-stone-400 focus:outline-none focus:border-sky-400 focus:ring-4 focus:ring-sky-100"
                />

                <div class="bg-amber-50 border border-amber-200 rounded-[10px] p-3">
                  <div class="flex items-start gap-2">
                    <.icon
                      name="hero-exclamation-triangle"
                      class="w-4 h-4 text-amber-600 mt-0.5 shrink-0"
                    />
                    <p class="text-xs text-amber-800 leading-[1.5]">
                      Das Passwort wird sofort geändert und alle offenen Sitzungen werden beendet. Teile es persönlich mit — die Plattform versendet keine E-Mails.
                    </p>
                  </div>
                </div>
              </div>

              <div class="flex justify-end gap-3 mt-6">
                <button
                  type="button"
                  phx-click="close_password_modal"
                  class="px-4 py-2.5 text-sm font-medium text-stone-700 bg-white border border-stone-200 rounded-[10px] hover:bg-stone-50 transition-all duration-150"
                >
                  Abbrechen
                </button>
                <button
                  type="submit"
                  phx-disable-with="Wird gespeichert..."
                  class="px-4 py-2.5 text-sm font-semibold text-white bg-sky-500 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] hover:bg-sky-600 transition-all duration-150"
                >
                  Passwort setzen
                </button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop bg-black/50" phx-click="close_password_modal">
            <button class="cursor-default">close</button>
          </div>
        </dialog>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    student = Accounts.get_student!(scope, id)

    {:ok,
     socket
     |> assign(:page_title, "Lernende bearbeiten")
     |> assign(:student, student)
     |> assign(:classes, Classes.list_classes(scope))
     |> assign(:profile_form, profile_form(student))
     |> assign(:show_password_modal, false)
     |> assign(:password_form, blank_password_form())}
  end

  @impl true
  def handle_event("validate_student", %{"user" => params}, socket) do
    form =
      socket.assigns.student
      |> Accounts.change_user_admin(params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :profile_form, form)}
  end

  def handle_event("update_student", %{"user" => params}, socket) do
    scope = socket.assigns.current_scope

    case Accounts.update_student(scope, socket.assigns.student, params) do
      {:ok, student} ->
        student = Accounts.get_student!(scope, student.id)

        {:noreply,
         socket
         |> put_flash(:info, "Lernende bzw. Lernender aktualisiert.")
         |> assign(:student, student)
         |> assign(:profile_form, profile_form(student))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Diese Klasse gehört nicht zu deiner Organisation.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("open_password_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_password_modal, true)
     |> assign(:password_form, blank_password_form())}
  end

  def handle_event("close_password_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_password_modal, false)
     |> assign(:password_form, blank_password_form())}
  end

  def handle_event("reset_password", %{"password_reset" => %{"password" => password}}, socket) do
    case Accounts.reset_student_password(
           socket.assigns.current_scope,
           socket.assigns.student,
           password
         ) do
      {:ok, {_student, expired_tokens}} ->
        # Deleting the token rows stops the *next* request; already-connected
        # LiveView sockets have to be kicked explicitly.
        TaskyWeb.UserAuth.disconnect_sessions(expired_tokens)

        {:noreply,
         socket
         |> put_flash(:info, "Passwort für #{socket.assigns.student.email} wurde zurückgesetzt.")
         |> assign(:show_password_modal, false)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Dazu fehlt dir die Berechtigung.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_form, to_form(changeset, as: "password_reset"))}
    end
  end

  defp profile_form(student) do
    to_form(Accounts.change_user_admin(student, %{}, validate_unique: false))
  end

  defp blank_password_form do
    to_form(%{"password" => ""}, as: "password_reset")
  end

  defp full_name(student) do
    case String.trim("#{student.firstname || ""} #{student.lastname || ""}") do
      "" -> student.email || ""
      name -> name
    end
  end

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y")
  defp format_date(_), do: ""
end
