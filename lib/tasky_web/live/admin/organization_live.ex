defmodule TaskyWeb.Admin.OrganizationLive do
  @moduledoc """
  Admin-only management of organizations: create, rename, delete, and hand out
  the teacher invite link.

  One LiveView with an inline form rather than separate new/edit routes — there
  is exactly one editable field.
  """

  use TaskyWeb, :live_view

  alias Tasky.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-header">
        <div class="max-w-5xl mx-auto">
          <div class="page-header-eyebrow">Administration</div>
          <h1>
            Organisationen <em>verwalten</em>
          </h1>
          <p>
            Eine Organisation bündelt Lehrpersonen, Klassen und Lernende.
            Lehrpersonen einer Organisation sehen dieselben Klassen und alle Lernenden darin.
          </p>
        </div>
      </div>

      <div class="max-w-5xl mx-auto mt-10 space-y-6">
        <%!-- Create / rename --%>
        <div class="bg-white border border-stone-200 rounded-[14px] overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="px-6 py-5 border-b border-stone-100">
            <h2 class="text-sm font-semibold text-stone-700">
              {if @editing, do: "Organisation umbenennen", else: "Neue Organisation"}
            </h2>
          </div>
          <div class="px-6 py-5">
            <.form for={@form} id="organization-form" phx-change="validate" phx-submit="save">
              <div class="flex flex-wrap items-end gap-4">
                <div class="flex-1 min-w-[240px]">
                  <.input
                    field={@form[:name]}
                    type="text"
                    label="Name"
                    required
                    placeholder="z.B. Berufsfachschule Bern"
                  />
                </div>
                <.button
                  variant="primary"
                  phx-disable-with="Wird gespeichert..."
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  <.icon name={if @editing, do: "hero-check", else: "hero-plus"} class="w-4 h-4" />
                  {if @editing, do: "Speichern", else: "Erstellen"}
                </.button>
                <button
                  :if={@editing}
                  type="button"
                  phx-click="cancel_edit"
                  class="text-sm font-medium text-stone-500 hover:text-stone-700 transition-colors px-2 py-2.5"
                >
                  Abbrechen
                </button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- List --%>
        <div class="bg-white border border-stone-200 rounded-[14px] overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div
            :if={@organizations == []}
            class="px-6 py-12 text-center text-sm text-stone-500"
          >
            Noch keine Organisation angelegt.
          </div>

          <ul :if={@organizations != []} class="list-none p-0 m-0 divide-y divide-stone-100">
            <li :for={organization <- @organizations} class="px-6 py-5">
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="min-w-0">
                  <div class="text-[15px] font-semibold text-stone-900">
                    {organization.name}
                  </div>
                  <div class="text-[13px] text-stone-500 mt-0.5">
                    {member_count(@member_counts, organization)} Mitglieder · {class_count(
                      @class_counts,
                      organization
                    )} Klassen
                  </div>
                </div>

                <div class="flex items-center gap-1.5">
                  <div class="tooltip tooltip-delayed tooltip-top" data-tip="Einladungslink kopieren">
                    <button
                      type="button"
                      phx-click="copy_invite_link"
                      phx-value-token={organization.invite_token}
                      class="inline-flex items-center gap-1.5 bg-transparent text-stone-500 text-[12px] font-medium px-2.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-sky-50 hover:text-sky-600"
                    >
                      <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Einladungslink
                    </button>
                  </div>

                  <div
                    class="tooltip tooltip-delayed tooltip-top"
                    data-tip="Neuen Link generieren — der alte wird ungültig"
                  >
                    <button
                      type="button"
                      phx-click="rotate_token"
                      phx-value-id={organization.id}
                      data-confirm="Neuen Einladungslink generieren? Der bisherige Link funktioniert danach nicht mehr."
                      class="inline-flex items-center gap-1.5 bg-transparent text-stone-500 text-[12px] font-medium px-2.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-amber-50 hover:text-amber-700"
                    >
                      <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> Neu
                    </button>
                  </div>

                  <button
                    type="button"
                    phx-click="edit"
                    phx-value-id={organization.id}
                    class="inline-flex items-center gap-1.5 bg-transparent text-stone-500 text-[12px] font-medium px-2.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-stone-100 hover:text-stone-700"
                  >
                    <.icon name="hero-pencil-square" class="w-3.5 h-3.5" /> Umbenennen
                  </button>

                  <button
                    type="button"
                    phx-click="delete"
                    phx-value-id={organization.id}
                    data-confirm={delete_confirm(@member_counts, @class_counts, organization)}
                    class="inline-flex items-center gap-1.5 bg-transparent text-stone-500 text-[12px] font-medium px-2.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-red-50 hover:text-red-600"
                  >
                    <.icon name="hero-trash" class="w-3.5 h-3.5" /> Löschen
                  </button>
                </div>
              </div>
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Organisationen")
     |> assign_editing(nil)
     |> load_organizations()}
  end

  @impl true
  def handle_event("validate", %{"organization" => params}, socket) do
    changeset =
      socket.assigns.editing
      |> changeset_source()
      |> Organizations.change_organization(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"organization" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.editing do
        nil -> Organizations.create_organization(scope, params)
        organization -> Organizations.update_organization(scope, organization, params)
      end

    case result do
      {:ok, organization} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organisation \"#{organization.name}\" wurde gespeichert.")
         |> assign_editing(nil)
         |> load_organizations()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    organization = Organizations.get_organization!(socket.assigns.current_scope, id)
    {:noreply, assign_editing(socket, organization)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign_editing(socket, nil)}
  end

  def handle_event("copy_invite_link", %{"token" => token}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Einladungslink wurde in die Zwischenablage kopiert!")
     |> push_event("copy-to-clipboard", %{text: url(~p"/users/register?invite=#{token}")})}
  end

  def handle_event("rotate_token", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    organization = Organizations.get_organization!(scope, id)

    case Organizations.rotate_invite_token(scope, organization) do
      {:ok, _organization} ->
        {:noreply,
         socket
         |> put_flash(:info, "Neuer Einladungslink generiert. Der bisherige ist ungültig.")
         |> load_organizations()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Der Einladungslink konnte nicht erneuert werden.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    organization = Organizations.get_organization!(scope, id)

    case Organizations.delete_organization(scope, organization) do
      {:ok, _organization} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organisation wurde gelöscht.")
         |> assign_editing(nil)
         |> load_organizations()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Organisation konnte nicht gelöscht werden.")}
    end
  end

  defp load_organizations(socket) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:organizations, Organizations.list_organizations(scope))
    |> assign(:member_counts, Organizations.count_members_per_organization(scope))
    |> assign(:class_counts, Organizations.count_classes_per_organization(scope))
  end

  defp assign_editing(socket, organization) do
    changeset =
      organization
      |> changeset_source()
      |> Organizations.change_organization()

    socket
    |> assign(:editing, organization)
    |> assign(:form, to_form(changeset))
  end

  defp changeset_source(nil), do: %Tasky.Organizations.Organization{}
  defp changeset_source(organization), do: organization

  defp member_count(counts, organization), do: Map.get(counts, organization.id, 0)
  defp class_count(counts, organization), do: Map.get(counts, organization.id, 0)

  defp delete_confirm(member_counts, class_counts, organization) do
    members = member_count(member_counts, organization)
    classes = class_count(class_counts, organization)

    "Organisation \"#{organization.name}\" wirklich löschen? " <>
      "#{members} Mitglieder und #{classes} Klassen verlieren ihre Zuordnung. " <>
      "Diese Klassen sind danach für keine Lehrperson mehr sichtbar."
  end
end
