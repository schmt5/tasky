defmodule TaskyWeb.ClassLive.Index do
  use TaskyWeb, :live_view

  alias Tasky.Classes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/classes"}>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-sky-500 mb-3">
            Klassenverwaltung
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Meine <em class="italic text-sky-500">Klassen</em>
          </h1>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Verwalte deine Klassen und teile Registrierungslinks mit deinen Schülern.
          </p>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
        <div class="flex items-center justify-between p-6 border-b border-stone-100">
          <div>
            <h2 class="text-lg font-semibold text-stone-800">Alle Klassen</h2>

            <p class="text-sm text-stone-500 mt-1">{@class_count} Klassen insgesamt</p>
          </div>

          <.link
            navigate={~p"/classes/new"}
            class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Neue Klasse
          </.link>
        </div>

        <ul :if={@has_classes} id="classes" phx-update="stream" class="list-none p-0 m-0">
          <li
            :for={{id, class} <- @streams.classes}
            id={id}
            class="flex items-start gap-5 px-6 py-5 border-b border-stone-100 bg-white transition-colors duration-150 last:border-b-0 hover:bg-stone-50"
          >
            <div class="w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5 bg-sky-100 text-sky-600">
              <.icon name="hero-user-group" class="w-5 h-5" />
            </div>

            <div class="flex-1 min-w-0 flex flex-col gap-1.5">
              <div class="flex items-center gap-2.5 flex-wrap">
                <h3 class="text-[15px] font-semibold text-stone-800 leading-[1.4]">{class.name}</h3>

                <span class="inline-flex items-center gap-1 bg-sky-50 text-sky-700 text-[12px] font-semibold px-2 py-0.5 rounded-[6px]">
                  <.icon name="hero-users" class="w-3 h-3" /> {Map.get(@student_counts, class.id, 0)}
                </span>
              </div>

              <div class="flex items-center gap-2 mt-1">
                <div class="flex-1 max-w-[500px]">
                  <div class="flex items-center gap-2">
                    <input
                      type="text"
                      readonly
                      value={registration_url(class.slug)}
                      class="flex-1 px-2.5 py-1.5 text-[12px] text-stone-600 bg-stone-50 border border-stone-200 rounded-[6px] font-mono"
                      id={"registration-link-#{class.id}"}
                    />
                    <button
                      type="button"
                      phx-click="copy_link"
                      phx-value-url={registration_url(class.slug)}
                      class="inline-flex items-center gap-1.5 bg-transparent text-stone-500 text-[12px] font-medium px-2.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-sky-50 hover:text-sky-600"
                      title="Link kopieren"
                    >
                      <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Kopieren
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <div class="flex items-center gap-2 shrink-0 pt-0.5">
              <.link
                navigate={~p"/classes/#{class}/edit"}
                class="inline-flex items-center gap-2 bg-transparent text-stone-500 text-[13px] font-medium px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-sky-50 hover:text-sky-600"
              >
                <.icon name="hero-pencil-square" class="w-4 h-4" /> Bearbeiten
              </.link>
              <button
                type="button"
                phx-click="delete"
                phx-value-id={class.id}
                data-confirm="Möchten Sie diese Klasse wirklich löschen? Schüler werden nicht gelöscht."
                class="inline-flex items-center gap-2 bg-transparent text-stone-500 text-[13px] font-medium px-3.5 py-1.5 rounded-[6px] transition-all duration-150 hover:bg-red-50 hover:text-red-600"
                title="Löschen"
              >
                <.icon name="hero-trash" class="w-4 h-4" /> Löschen
              </button>
            </div>
          </li>
        </ul>

        <div :if={!@has_classes} class="flex flex-col items-center text-center px-8 py-16 bg-white">
          <div class="w-14 h-14 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-5">
            <.icon name="hero-user-group" class="w-6 h-6" />
          </div>

          <h3 class="text-base font-semibold text-stone-700 mb-2">Noch keine Klassen</h3>

          <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6] mb-6">
            Erstelle deine erste Klasse, um Schüler zu organisieren und Registrierungslinks zu teilen.
          </p>

          <.link
            navigate={~p"/classes/new"}
            class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Erste Klasse erstellen
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    classes = Classes.list_classes()
    class_count = length(classes)

    {:ok,
     socket
     |> assign(:page_title, "Klassen")
     |> assign(:class_count, class_count)
     |> assign(:has_classes, class_count > 0)
     |> assign(:student_counts, Classes.count_students_per_class())
     |> stream(:classes, classes)}
  end

  @impl true
  def handle_event("copy_link", %{"url" => url}, socket) do
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
        class_count = length(classes)

        {:noreply,
         socket
         |> assign(:class_count, class_count)
         |> assign(:has_classes, class_count > 0)
         |> assign(:student_counts, Classes.count_students_per_class())
         |> stream(:classes, classes, reset: true)
         |> put_flash(:info, "Klasse wurde erfolgreich gelöscht.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Klasse konnte nicht gelöscht werden.")}
    end
  end

  defp registration_url(slug) do
    url(~p"/users/register?class=#{slug}")
  end
end
