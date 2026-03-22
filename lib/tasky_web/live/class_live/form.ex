defmodule TaskyWeb.ClassLive.Form do
  use TaskyWeb, :live_view

  alias Tasky.Classes
  alias Tasky.Classes.Class

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/classes"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <%= if @live_action == :new do %>
              <.breadcrumbs crumbs={[
                %{label: "Klassen", navigate: ~p"/classes"},
                %{label: "Neue Klasse"}
              ]} />
            <% else %>
              <.breadcrumbs crumbs={[
                %{label: "Klassen", navigate: ~p"/classes"},
                %{label: @class.name},
                %{label: "Bearbeiten"}
              ]} />
            <% end %>
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            {@page_title}
          </h1>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            {if @live_action == :new,
              do: "Erstelle eine neue Klasse für deine Schüler.",
              else: "Bearbeite die Klasseninformationen."}
          </p>
        </div>
      </div>
      <%!-- Form Card --%>
      <div class="max-w-6xl mx-auto px-8 pb-8">
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6">
            <.form
              for={@form}
              id="class-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-6"
            >
              <.input
                field={@form[:name]}
                type="text"
                label="Klassenname"
                required
                placeholder="z.B. Klasse 5a, Mathematik 2024"
              />
              <div class="bg-sky-50 rounded-[10px] p-4 border border-sky-100">
                <div class="flex items-start gap-3">
                  <div class="mt-0.5">
                    <.icon name="hero-information-circle" class="w-5 h-5 text-sky-600" />
                  </div>

                  <div class="flex-1">
                    <p class="text-[13px] text-stone-700 leading-[1.5]">
                      Nach dem Erstellen erhältst du einen Link, den du an deine Schüler weitergeben kannst. Schüler, die sich über diesen Link registrieren, werden automatisch dieser Klasse zugeordnet.
                    </p>
                  </div>
                </div>
              </div>

              <div class="flex items-center gap-3 pt-4 border-t border-stone-100">
                <.button
                  phx-disable-with="Speichert..."
                  class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
                >
                  {if @live_action == :new, do: "Klasse erstellen", else: "Änderungen speichern"}
                </.button>
                <.link
                  navigate={~p"/classes"}
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
    {:ok, socket |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    class = Classes.get_class!(id)

    socket
    |> assign(:page_title, "Klasse bearbeiten")
    |> assign(:class, class)
    |> assign(:form, to_form(Classes.change_class(class)))
  end

  defp apply_action(socket, :new, _params) do
    class = %Class{}

    socket
    |> assign(:page_title, "Neue Klasse")
    |> assign(:class, class)
    |> assign(:form, to_form(Classes.change_class(class)))
  end

  @impl true
  def handle_event("validate", %{"class" => class_params}, socket) do
    changeset = Classes.change_class(socket.assigns.class, class_params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"class" => class_params}, socket) do
    save_class(socket, socket.assigns.live_action, class_params)
  end

  defp save_class(socket, :edit, class_params) do
    case Classes.update_class(socket.assigns.class, class_params) do
      {:ok, class} ->
        {:noreply,
         socket
         |> put_flash(:info, "Klasse \"#{class.name}\" wurde erfolgreich aktualisiert.")
         |> push_navigate(to: ~p"/classes")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_class(socket, :new, class_params) do
    case Classes.create_class(class_params) do
      {:ok, class} ->
        {:noreply,
         socket
         |> put_flash(:info, "Klasse \"#{class.name}\" wurde erfolgreich erstellt.")
         |> push_navigate(to: ~p"/classes")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
