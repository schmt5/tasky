defmodule TaskyWeb.ClassLive.Index do
  use TaskyWeb, :live_view

  alias Tasky.Classes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-gradient-to-br from-sky-50 via-white to-stone-50">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
          <%!-- Header --%>
          <div class="mb-8">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] font-normal">
                  Klassen
                </h1>
                <p class="text-[15px] text-stone-500 mt-2">
                  Verwalten Sie Ihre Klassen und teilen Sie Registrierungslinks mit Ihren Schülern.
                </p>
              </div>
              <.link
                navigate={~p"/classes/new"}
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-[15px] font-semibold px-6 py-3.5 rounded-[10px] shadow-[0_2px_12px_rgba(14,165,233,0.3)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
              >
                <svg
                  width="18"
                  height="18"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  stroke-width="2"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
                </svg>
                Neue Klasse
              </.link>
            </div>
          </div>
          <%!-- Classes Grid --%>
          <%= if @classes == [] do %>
            <div class="bg-white rounded-[16px] border border-stone-100 shadow-[0_2px_12px_rgba(0,0,0,0.08)] p-12 text-center">
              <div class="inline-flex items-center justify-center w-16 h-16 rounded-[16px] bg-stone-100 mb-6">
                <svg
                  width="32"
                  height="32"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  stroke-width="2"
                  class="text-stone-400"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                  />
                </svg>
              </div>
              <h3 class="text-[20px] font-semibold text-stone-900 mb-2">
                Noch keine Klassen
              </h3>
              <p class="text-[15px] text-stone-500 mb-6">
                Erstellen Sie Ihre erste Klasse, um Schüler zu organisieren.
              </p>
              <.link
                navigate={~p"/classes/new"}
                class="inline-flex items-center gap-2 bg-sky-500 text-white text-[15px] font-semibold px-6 py-3 rounded-[10px] shadow-[0_2px_12px_rgba(14,165,233,0.3)] transition-all duration-150 hover:bg-sky-600"
              >
                <svg
                  width="18"
                  height="18"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  stroke-width="2"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
                </svg>
                Erste Klasse erstellen
              </.link>
            </div>
          <% else %>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <div
                :for={class <- @classes}
                class="bg-white rounded-[16px] border border-stone-100 shadow-[0_2px_12px_rgba(0,0,0,0.08)] overflow-hidden transition-all duration-150 hover:shadow-[0_4px_20px_rgba(0,0,0,0.12)] hover:border-sky-200"
              >
                <div class="p-6">
                  <div class="flex items-start justify-between mb-4">
                    <div class="flex-1">
                      <h3 class="text-[18px] font-semibold text-stone-900 mb-1">
                        {class.name}
                      </h3>
                      <p class="text-[13px] text-stone-500 font-mono">
                        {class.slug}
                      </p>
                    </div>
                    <div class="inline-flex items-center gap-1.5 bg-sky-50 text-sky-700 text-[13px] font-semibold px-3 py-1.5 rounded-[8px]">
                      <svg
                        width="14"
                        height="14"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                        stroke-width="2"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
                        />
                      </svg>
                      {Map.get(@student_counts, class.id, 0)}
                    </div>
                  </div>
                  <%!-- Registration Link --%>
                  <div class="bg-stone-50 rounded-[10px] p-4 mb-4">
                    <label class="block text-[12px] font-semibold text-stone-600 uppercase tracking-wide mb-2">
                      Registrierungslink
                    </label>
                    <div class="flex items-center gap-2">
                      <input
                        type="text"
                        readonly
                        value={registration_url(@socket, class.slug)}
                        class="flex-1 px-3 py-2 text-[13px] text-stone-700 bg-white border border-stone-200 rounded-[8px] font-mono"
                        id={"registration-link-#{class.id}"}
                      />
                      <button
                        type="button"
                        phx-click="copy_link"
                        phx-value-url={registration_url(@socket, class.slug)}
                        class="inline-flex items-center justify-center w-10 h-10 bg-sky-500 text-white rounded-[8px] transition-all duration-150 hover:bg-sky-600 active:scale-95"
                        title="Link kopieren"
                      >
                        <svg
                          width="16"
                          height="16"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke="currentColor"
                          stroke-width="2"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
                          />
                        </svg>
                      </button>
                    </div>
                  </div>
                  <%!-- Actions --%>
                  <div class="flex items-center gap-2">
                    <.link
                      navigate={~p"/classes/#{class}/edit"}
                      class="flex-1 inline-flex items-center justify-center gap-2 bg-stone-100 text-stone-700 text-[14px] font-semibold px-4 py-2.5 rounded-[8px] transition-all duration-150 hover:bg-stone-200 active:scale-95"
                    >
                      <svg
                        width="16"
                        height="16"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                        stroke-width="2"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                        />
                      </svg>
                      Bearbeiten
                    </.link>
                    <button
                      type="button"
                      phx-click="delete"
                      phx-value-id={class.id}
                      data-confirm="Möchten Sie diese Klasse wirklich löschen? Schüler werden nicht gelöscht."
                      class="inline-flex items-center justify-center w-10 h-10 bg-red-50 text-red-600 rounded-[8px] transition-all duration-150 hover:bg-red-100 active:scale-95"
                      title="Löschen"
                    >
                      <svg
                        width="16"
                        height="16"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                        stroke-width="2"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                        />
                      </svg>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    classes = Classes.list_classes()
    student_counts = build_student_counts(classes)

    socket =
      socket
      |> assign(:classes, classes)
      |> assign(:student_counts, student_counts)

    {:ok, socket}
  end

  @impl true
  def handle_event("copy_link", %{"url" => url}, socket) do
    # Use JavaScript to copy to clipboard
    {:noreply,
     socket
     |> put_flash(:info, "Link wurde in die Zwischenablage kopiert!")
     |> push_event("copy-to-clipboard", %{text: url})}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    class = Classes.get_class!(id)

    case Classes.delete_class(class) do
      {:ok, _class} ->
        classes = Classes.list_classes()
        student_counts = build_student_counts(classes)

        {:noreply,
         socket
         |> assign(:classes, classes)
         |> assign(:student_counts, student_counts)
         |> put_flash(:info, "Klasse wurde erfolgreich gelöscht.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Klasse konnte nicht gelöscht werden.")}
    end
  end

  defp build_student_counts(classes) do
    classes
    |> Enum.map(fn class ->
      {class.id, Classes.count_students_in_class(class)}
    end)
    |> Enum.into(%{})
  end

  defp registration_url(_socket, slug) do
    url(~p"/users/register?class=#{slug}")
  end
end
