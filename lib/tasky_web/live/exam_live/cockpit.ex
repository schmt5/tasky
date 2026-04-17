defmodule TaskyWeb.ExamLive.Cockpit do
  use TaskyWeb, :live_view

  alias Tasky.Exams

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/\#{@exam}"}>
      <%!-- Page Header --%>
      <div class="sticky top-0 z-10 bg-white border-b border-stone-100 px-8 py-6 mb-8">
        <div class="max-w-6xl mx-auto">
          <div class="flex items-center justify-between mb-3">
            <.breadcrumbs crumbs={[
              %{label: "Prüfungen", navigate: ~p"/exams"},
              %{label: @exam.name, navigate: ~p"/exams/\#{@exam}"},
              %{label: "Cockpit"}
            ]} />
          </div>

          <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
            Cockpit
          </h1>

          <p class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
            Verwaltungsübersicht für die Prüfung <span class="font-semibold text-stone-700">{@exam.name}</span>.
          </p>
        </div>
      </div>

      <div class="max-w-6xl mx-auto px-8 pb-8 space-y-6">
        <%!-- Enrollment Token Card --%>
        <div class="bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]">
          <div class="p-6 border-b border-stone-100">
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 rounded-[10px] flex items-center justify-center shrink-0 bg-amber-50 text-amber-500">
                <.icon name="hero-key" class="w-5 h-5" />
              </div>
              <div>
                <h2 class="text-lg font-semibold text-stone-800">Einschreibelink</h2>
                <p class="text-sm text-stone-500 mt-0.5">
                  Teile diesen Link mit Lernenden, damit sie sich für die Prüfung einschreiben können.
                </p>
              </div>
            </div>
          </div>
          <div class="p-6">
            <%= if @exam.enrollment_token do %>
              <div class="flex items-center gap-3">
                <input
                  id="enrollment-token-field"
                  type="text"
                  value={"http://localhost:4000/guest/enroll/#{@exam.enrollment_token}"}
                  readonly
                  class="flex-1 font-mono text-sm text-stone-700 bg-stone-50 border border-stone-200 rounded-lg px-4 py-2.5 focus:outline-none focus:ring-2 focus:ring-amber-300 focus:border-amber-400 select-all cursor-text"
                  phx-hook=".CopyToClipboard"
                />
                <button
                  id="copy-token-btn"
                  type="button"
                  phx-hook=".CopyButton"
                  data-target="enrollment-token-field"
                  class="inline-flex items-center gap-2 bg-amber-500 text-white text-sm font-semibold px-4 py-2.5 rounded-lg shadow-[0_2px_8px_rgba(245,158,11,0.25)] transition-all duration-150 hover:bg-amber-600 active:scale-[0.98]"
                >
                  <.icon name="hero-clipboard-document" class="w-4 h-4" />
                  <span>Kopieren</span>
                </button>
              </div>
            <% else %>
              <div class="flex items-center gap-3 text-stone-400">
                <.icon name="hero-exclamation-circle" class="w-5 h-5" />
                <p class="text-sm">
                  Kein Einschreibeschlüssel gesetzt. Du kannst einen in den
                  <.link
                    navigate={~p"/exams/\#{@exam}/edit?return_to=show"}
                    class="text-amber-600 hover:text-amber-700 font-medium underline underline-offset-2"
                  >
                    Prüfungseinstellungen
                  </.link>
                  hinterlegen.
                </p>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              this.el.select();
            });
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyButton">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const targetId = this.el.getAttribute("data-target");
              const input = document.getElementById(targetId);
              if (!input) return;

              navigator.clipboard.writeText(input.value).then(() => {
                const span = this.el.querySelector("span");
                const original = span.textContent;
                span.textContent = "Kopiert!";
                this.el.classList.remove("bg-amber-500", "hover:bg-amber-600");
                this.el.classList.add("bg-emerald-500", "hover:bg-emerald-600");
                setTimeout(() => {
                  span.textContent = original;
                  this.el.classList.remove("bg-emerald-500", "hover:bg-emerald-600");
                  this.el.classList.add("bg-amber-500", "hover:bg-amber-600");
                }, 2000);
              });
            });
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, exam.name <> " – Cockpit")
     |> assign(:exam, exam)}
  end
end
