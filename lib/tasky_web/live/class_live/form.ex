defmodule TaskyWeb.ClassLive.Form do
  use TaskyWeb, :live_view

  alias Tasky.Classes
  alias Tasky.Classes.Class

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-gradient-to-br from-sky-50 via-white to-stone-50 flex items-center justify-center px-4 py-12">
        <div class="w-full max-w-[540px]">
          <%!-- Header --%>
          <div class="text-center mb-8">
            <.link
              navigate={~p"/classes"}
              class="inline-flex items-center gap-2 text-[14px] text-stone-500 hover:text-stone-700 transition-colors duration-150 mb-6"
            >
              <svg
                width="16"
                height="16"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                stroke-width="2"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
              </svg>
              Zurück zu Klassen
            </.link>

            <div class="inline-flex items-center justify-center w-16 h-16 rounded-[16px] bg-gradient-to-br from-sky-400 to-sky-600 shadow-[0_4px_16px_rgba(14,165,233,0.25)] mb-6">
              <svg
                width="32"
                height="32"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                stroke-width="2"
                class="text-white"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                />
              </svg>
            </div>

            <h1 class="font-serif text-[38px] text-stone-900 leading-[1.1] mb-3 font-normal">
              {if @live_action == :new, do: "Neue Klasse", else: "Klasse bearbeiten"}
            </h1>

            <p class="text-[15px] text-stone-500 leading-[1.6]">
              <%= if @live_action == :new do %>
                Erstellen Sie eine neue Klasse für Ihre Schüler.
              <% else %>
                Bearbeiten Sie die Details dieser Klasse.
              <% end %>
            </p>
          </div>
          <%!-- Form Card --%>
          <div class="bg-white rounded-[16px] border border-stone-100 shadow-[0_2px_12px_rgba(0,0,0,0.08)] overflow-hidden">
            <.form for={@form} id="class-form" phx-submit="save" phx-change="validate">
              <div class="p-8 space-y-5">
                <.input
                  field={@form[:name]}
                  type="text"
                  label="Klassenname"
                  required
                  phx-mounted={JS.focus()}
                  class="w-full px-4 py-3 text-[15px] text-stone-900 bg-white border border-stone-200 rounded-[10px] transition-all duration-150 placeholder:text-stone-400 focus:outline-none focus:border-sky-400 focus:ring-4 focus:ring-sky-100"
                  placeholder="z.B. Klasse 5a, Mathematik 2024"
                />

                <%= if @slug_preview do %>
                  <div class="bg-stone-50 rounded-[10px] p-4 border border-stone-200">
                    <label class="block text-[12px] font-semibold text-stone-600 uppercase tracking-wide mb-2">
                      URL-Slug (wird automatisch generiert)
                    </label>
                    <p class="text-[14px] text-stone-700 font-mono">
                      {Class.slugify(@slug_preview)}
                    </p>
                    <p class="text-[12px] text-stone-500 mt-2">
                      Dieser Slug wird im Registrierungslink verwendet
                    </p>
                  </div>
                <% end %>

                <div class="bg-sky-50 rounded-[10px] p-4 border border-sky-100">
                  <div class="flex items-start gap-3">
                    <div class="mt-0.5">
                      <svg
                        width="20"
                        height="20"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                        stroke-width="2"
                        class="text-sky-600"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                    </div>
                    <div class="flex-1">
                      <p class="text-[13px] text-stone-700 leading-[1.5]">
                        Nach dem Erstellen erhalten Sie einen Link, den Sie an Ihre Schüler weitergeben können. Schüler, die sich über diesen Link registrieren, werden automatisch dieser Klasse zugeordnet.
                      </p>
                    </div>
                  </div>
                </div>
              </div>

              <div class="px-8 pb-8 flex items-center gap-3">
                <.link
                  navigate={~p"/classes"}
                  class="flex-1 inline-flex items-center justify-center gap-2 bg-stone-100 text-stone-700 text-[15px] font-semibold px-6 py-3.5 rounded-[10px] transition-all duration-150 hover:bg-stone-200 active:scale-[0.98]"
                >
                  Abbrechen
                </.link>
                <button
                  type="submit"
                  phx-disable-with="Wird gespeichert..."
                  class="flex-1 inline-flex items-center justify-center gap-2 bg-sky-500 text-white text-[15px] font-semibold px-6 py-3.5 rounded-[10px] shadow-[0_2px_12px_rgba(14,165,233,0.3)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
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
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  {if @live_action == :new, do: "Klasse erstellen", else: "Änderungen speichern"}
                </button>
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
    class =
      case socket.assigns.live_action do
        :new -> %Class{}
        :edit -> Classes.get_class!(params["id"])
      end

    changeset = Classes.change_class(class)

    socket =
      socket
      |> assign(:class, class)
      |> assign_form(changeset)
      |> assign(:slug_preview, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"class" => class_params}, socket) do
    changeset =
      socket.assigns.class
      |> Classes.change_class(class_params)
      |> Map.put(:action, :validate)

    slug_preview = Map.get(class_params, "name")

    socket =
      socket
      |> assign_form(changeset)
      |> assign(:slug_preview, slug_preview)

    {:noreply, socket}
  end

  def handle_event("save", %{"class" => class_params}, socket) do
    save_class(socket, socket.assigns.live_action, class_params)
  end

  defp save_class(socket, :new, class_params) do
    case Classes.create_class(class_params) do
      {:ok, class} ->
        {:noreply,
         socket
         |> put_flash(:info, "Klasse \"#{class.name}\" wurde erfolgreich erstellt.")
         |> push_navigate(to: ~p"/classes")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_class(socket, :edit, class_params) do
    case Classes.update_class(socket.assigns.class, class_params) do
      {:ok, class} ->
        {:noreply,
         socket
         |> put_flash(:info, "Klasse \"#{class.name}\" wurde erfolgreich aktualisiert.")
         |> push_navigate(to: ~p"/classes")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
