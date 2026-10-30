defmodule TaskyWeb.ExamLive.CorrectionExam do
  @moduledoc """
  The whole exam of one participant, to read: every part one below the
  other, with its points and status beside it. Grading stays per part in
  `CorrectionPart`; a part here opens it, and `G` switches back and forth.

  Each part is its own read-only editor, mounted only near the viewport, so a
  long exam neither builds all its editors nor loads all its images at once.
  `?part=` names the part to show first: switching participants or coming
  back from grading keeps the place.
  """
  use TaskyWeb, :live_view

  import TaskyWeb.ExamComponents, only: [correction_mode_switch: 1]

  alias Tasky.Exams
  alias Tasky.Grading

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={~p"/exams/#{@exam}"}>
      <div id="correction-exam" phx-hook=".CorrectionExamNav" class="bg-white min-h-screen">
        <div
          id="correction-exam-header"
          class="sticky top-0 z-20 bg-white border-b border-stone-100 px-8 py-3"
        >
          <div class="max-w-7xl mx-auto flex items-center justify-between gap-4">
            <div class="flex items-center gap-2 min-w-0">
              <.back_button
                navigate={~p"/exams/#{@exam}/correction"}
                tooltip="Zurück zur Korrektur"
                size="sm"
              />
              <.breadcrumbs crumbs={[
                %{label: "Prüfungen", navigate: ~p"/exams"},
                %{label: @exam.name, navigate: ~p"/exams/#{@exam}"},
                %{label: "Korrektur", navigate: ~p"/exams/#{@exam}/correction"},
                %{label: participant_name(@submission)}
              ]} />
            </div>

            <div class="flex items-center gap-3 shrink-0">
              <.correction_mode_switch
                :if={@parts != []}
                active={:exam}
                exam_path={~p"/exams/#{@exam}/correction/#{@submission.id}"}
                part_path={hd(@parts).grade_path}
              />

              <div class="inline-flex items-center gap-2 bg-sky-50 border border-sky-200 rounded-lg pl-2.5 pr-1.5 py-1">
                <.icon name="hero-user" class="w-4 h-4 text-sky-700" />
                <span class="text-xs font-semibold text-sky-700 uppercase tracking-wide">
                  Teilnehmer:in
                </span>
                <span class="text-xs font-mono font-semibold text-sky-700">
                  {@submission_index + 1}/{length(@submissions)}
                </span>
                <div class="flex items-center gap-1 ml-1">
                  <.participant_chevron
                    id="exam-prev-participant"
                    direction="up"
                    target={@prev_submission_path}
                    title="Vorheriger Teilnehmer"
                  />
                  <.participant_chevron
                    id="exam-next-participant"
                    direction="down"
                    target={@next_submission_path}
                    title="Nächster Teilnehmer"
                  />
                </div>
              </div>

              <div
                :if={@parts != []}
                class="inline-flex items-center gap-2 bg-sky-50 border border-sky-200 rounded-lg pl-2.5 pr-1.5 py-1"
              >
                <.icon name="hero-document-text" class="w-4 h-4 text-sky-700" />
                <span class="text-xs font-semibold text-sky-700 uppercase tracking-wide">Teil</span>
                <span data-part-counter class="text-xs font-mono font-semibold text-sky-700">
                  1/{length(@parts)}
                </span>
                <div class="flex items-center gap-1 ml-1">
                  <.part_step_button step={-1} icon="hero-chevron-left" title="Vorheriger Teil" />
                  <.part_step_button step={1} icon="hero-chevron-right" title="Nächster Teil" />
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="max-w-7xl mx-auto px-8 py-6">
          <%= if @parts == [] do %>
            <div
              id="correction-exam-empty"
              class="rounded-[14px] border border-dashed border-stone-200 px-6 py-12 text-center"
            >
              <.icon name="hero-document" class="w-8 h-8 text-stone-300 mx-auto" />
              <p class="text-sm text-stone-500 mt-3">Diese Prüfung hat noch keine Teile.</p>
            </div>
          <% else %>
            <div class="grid grid-cols-5 gap-6 items-start">
              <div class="col-span-3 min-w-0 space-y-6">
                <section
                  :for={{part, index} <- Enum.with_index(@parts)}
                  id={"exam-part-#{part.id}"}
                  data-part-id={part.id}
                  data-grade-path={part.grade_path}
                >
                  <.link
                    navigate={part.grade_path}
                    id={"exam-part-grade-#{part.id}"}
                    class="group flex items-center gap-3 mb-2 px-3 py-2 rounded-lg border border-stone-200 bg-stone-50/60 transition-all duration-150 hover:bg-sky-50 hover:border-sky-300 focus:outline-none focus-visible:ring-4 focus-visible:ring-sky-600 focus-visible:ring-offset-2"
                  >
                    <span class="text-xs font-semibold uppercase tracking-wide text-stone-500">
                      Teil {index + 1}
                    </span>
                    <.part_status part={part} />
                    <span class="ml-auto font-mono text-sm font-semibold text-stone-700 tabular-nums">
                      {points_label(part)}
                    </span>
                    <span class="inline-flex items-center gap-1 text-xs font-semibold text-sky-700 transition-transform duration-150 group-hover:translate-x-0.5">
                      Bewerten <.icon name="hero-arrow-right" class="w-3.5 h-3.5" />
                    </span>
                  </.link>
                  <div
                    id={"exam-part-viewer-#{@submission.id}-#{part.id}"}
                    phx-hook="ExamReadOnlyPartViewer"
                    phx-update="ignore"
                    data-content={part.doc_json}
                  >
                  </div>
                </section>
              </div>

              <aside class="col-span-2 sticky top-20">
                <div
                  id="correction-exam-panel"
                  class="bg-white rounded-[14px] border border-stone-100 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]"
                >
                  <div class="px-5 pt-5 pb-4 border-b border-stone-100">
                    <h2 class="text-base font-semibold text-stone-800 truncate">
                      {participant_name(@submission)}
                    </h2>
                    <p class="mt-1 text-sm text-stone-500">
                      {@corrected_count} von {length(@parts)} Teilen erledigt
                    </p>
                    <div id="correction-exam-total" class="mt-3 flex items-baseline gap-2">
                      <span class="text-xs font-semibold text-stone-500 uppercase tracking-wide">
                        Punkte
                      </span>
                      <span class="font-mono text-base font-semibold text-stone-800 tabular-nums">
                        {format_points(@total_points)}
                      </span>
                      <span :if={@max_points} class="text-sm text-stone-500">
                        / {format_points(@max_points)}
                      </span>
                    </div>
                  </div>

                  <nav
                    id="correction-exam-parts"
                    class="p-2 max-h-[calc(100vh-16rem)] overflow-y-auto"
                  >
                    <.link
                      :for={{part, index} <- Enum.with_index(@parts)}
                      navigate={part.grade_path}
                      id={"exam-part-link-#{part.id}"}
                      data-part-link={part.id}
                      class="group flex items-center gap-3 px-3 py-2 rounded-lg border border-transparent transition-all duration-150 hover:bg-stone-50 hover:border-stone-200 data-current:bg-sky-50 data-current:border-sky-200"
                    >
                      <span class="w-6 shrink-0 text-xs font-mono font-semibold text-stone-400 group-data-current:text-sky-700">
                        {index + 1}
                      </span>
                      <span class="flex-1 min-w-0 truncate text-sm text-stone-700 group-data-current:text-sky-900">
                        {part.label}
                      </span>
                      <span class="shrink-0 font-mono text-xs font-semibold text-stone-600 tabular-nums">
                        {points_label(part)}
                      </span>
                      <.part_status_icon part={part} />
                    </.link>
                  </nav>

                  <p class="px-5 py-3 border-t border-stone-100 text-xs text-stone-500">
                    Ein Klick auf einen Teil öffnet das Bewerten.
                  </p>
                </div>
              </aside>
            </div>
          <% end %>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CorrectionExamNav">
        // Which part is in view: highlighted in the panel, counted in the
        // header, and where "Teil" (or G) and the participant arrows go.
        // Links get the place only when followed, as LiveView re-renders
        // them with the server's href.
        const USER_INPUT = ["wheel", "touchstart", "keydown", "mousedown"];
        const ALIGN_MS = 1500;
        const WAIT_MS = 5000;
        // Matches the lazy editors' own margin (create_react_hook.jsx).
        const NEAR_PX = 700;

        // A part whose editor is near enough to mount but has not yet.
        const mounting = (section) => {
          const viewer = section.querySelector("[phx-hook='ExamReadOnlyPartViewer']");
          if (!viewer || viewer.querySelector(".ProseMirror")) return false;
          const rect = viewer.getBoundingClientRect();
          return rect.bottom > -NEAR_PX && rect.top < window.innerHeight + NEAR_PX;
        };

        export default {
          mounted() {
            this.current = 0;

            // A few rects per scroll event, so no throttling needed.
            this.onScroll = () => this.sync();

            this.onClick = (e) => {
              const step = e.target.closest("[data-part-step]");
              if (step) {
                e.preventDefault();
                this.stepPart(parseInt(step.dataset.partStep, 10));
                return;
              }

              const link = e.target.closest("a[href]");
              const section = this.sections()[this.current];
              if (!link || !section) return;

              if (link.id === "correction-mode-part") {
                link.href = section.dataset.gradePath;
              } else if (link.hasAttribute("data-keep-part")) {
                const url = new URL(link.href);
                url.searchParams.set("part", section.dataset.partId);
                link.href = url.toString();
              }
            };

            // Another participant is a patch: the editors are new, the hook
            // is not.
            this.onPatched = (e) => {
              if (e.detail?.kind === "patch") this.restore(true);
            };

            // Scrolling of the teacher's own ends the alignment.
            this.onUserInput = () => {
              this.token = null;
            };

            this.el.addEventListener("click", this.onClick);
            window.addEventListener("scroll", this.onScroll, { passive: true });
            window.addEventListener("phx:page-loading-stop", this.onPatched);
            for (const type of USER_INPUT) {
              window.addEventListener(type, this.onUserInput, { passive: true });
            }

            this.restore(false);
          },

          destroyed() {
            this.token = null;
            window.removeEventListener("scroll", this.onScroll);
            window.removeEventListener("phx:page-loading-stop", this.onPatched);
            for (const type of USER_INPUT) {
              window.removeEventListener(type, this.onUserInput);
            }
          },

          sections() {
            return [...this.el.querySelectorAll("section[data-part-id]")];
          },

          // Content above this line is hidden under the sticky header.
          headerBottom() {
            const header = document.getElementById("correction-exam-header");
            return header ? header.getBoundingClientRect().bottom : 0;
          },

          // A part counts as being read once its top is above this line.
          readingLine() {
            return this.headerBottom() + 24;
          },

          // Where a part's top lands once scrolled to: below the header,
          // which by then sticks to the top of the window.
          landing() {
            const header = document.getElementById("correction-exam-header");
            return (header ? header.offsetHeight : 0) + 16;
          },

          sync() {
            const sections = this.sections();
            if (sections.length === 0) return;

            const line = this.readingLine();
            let index = 0;
            sections.forEach((section, i) => {
              if (section.getBoundingClientRect().top <= line) index = i;
            });
            // At the end of the page the last part is the one being read,
            // however short it is.
            const root = document.documentElement;
            if (window.innerHeight + window.scrollY >= root.scrollHeight - 2) {
              index = sections.length - 1;
            }
            this.current = index;

            const id = sections[index].dataset.partId;
            for (const link of this.el.querySelectorAll("[data-part-link]")) {
              link.toggleAttribute("data-current", link.dataset.partLink === id);
            }
            const counter = this.el.querySelector("[data-part-counter]");
            if (counter) counter.textContent = `${index + 1}/${sections.length}`;
          },

          // The next part starting below the reading line, or the previous
          // one above where parts land. Not by index: at the end of a short
          // page the last part counts as current while the ones before it
          // are still in view.
          stepPart(direction) {
            const line = this.readingLine();
            const landing = this.landing();
            const top = (s) => s.getBoundingClientRect().top;
            const sections = this.sections();
            const section =
              direction > 0
                ? sections.find((s) => top(s) > line)
                : sections.reverse().find((s) => top(s) < landing - 1);
            if (!section) return;
            this.token = null;
            window.scrollBy({
              top: section.getBoundingClientRect().top - this.landing(),
              behavior: "smooth",
            });
          },

          // The editors up to the part mount lazily and change their height
          // when they do, so the part is held in place until they are all
          // there, and a moment longer for their images.
          restore(patched) {
            const part = new URL(window.location.href).searchParams.get("part");
            const sections = this.sections();
            const index = sections.findIndex((s) => s.dataset.partId === part);

            if (index < 0) {
              if (patched) window.scrollTo({ top: 0, behavior: "instant" });
              this.sync();
              return;
            }

            const section = sections[index];
            const above = sections.slice(0, index + 1);
            const token = (this.token = {});
            const giveUp = performance.now() + WAIT_MS;
            let settled = null;

            const step = () => {
              if (this.token !== token) return;
              const delta = section.getBoundingClientRect().top - this.landing();
              if (Math.abs(delta) >= 1) window.scrollBy({ top: delta, behavior: "instant" });
              this.sync();

              const now = performance.now();
              settled = above.some(mounting) ? null : (settled ?? now);
              if (now < giveUp && (settled === null || now - settled < ALIGN_MS)) {
                requestAnimationFrame(step);
              }
            };
            step();
          },
        };
      </script>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :direction, :string, required: true
  attr :target, :string, default: nil
  attr :title, :string, required: true

  # A neighbouring participant's whole exam. `data-keep-part` lets the hook
  # add the part in view, so the new page opens at the same question.
  defp participant_chevron(assigns) do
    assigns =
      assign(
        assigns,
        :icon,
        if(assigns.direction == "up", do: "hero-chevron-up", else: "hero-chevron-down")
      )

    ~H"""
    <div class="tooltip tooltip-bottom tooltip-delayed" data-tip={@title}>
      <%= if @target do %>
        <.link
          id={@id}
          patch={@target}
          data-keep-part
          class="inline-flex items-center justify-center w-7 h-7 rounded-md text-sky-700 bg-white border border-sky-300 transition-all duration-150 hover:bg-sky-100 hover:border-sky-400 hover:text-sky-800"
        >
          <.icon name={@icon} class="w-4 h-4" />
        </.link>
      <% else %>
        <span class="inline-flex items-center justify-center w-7 h-7 rounded-md text-sky-300 bg-white/60 border border-sky-100 cursor-not-allowed">
          <.icon name={@icon} class="w-4 h-4" />
        </span>
      <% end %>
    </div>
    """
  end

  attr :step, :integer, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true

  # Scrolls to the previous or next part on this page (see the hook).
  defp part_step_button(assigns) do
    ~H"""
    <div class="tooltip tooltip-bottom tooltip-delayed" data-tip={@title}>
      <button
        type="button"
        data-part-step={@step}
        aria-label={@title}
        class="inline-flex items-center justify-center w-7 h-7 rounded-md text-sky-700 bg-white border border-sky-300 transition-all duration-150 hover:bg-sky-100 hover:border-sky-400 hover:text-sky-800"
      >
        <.icon name={@icon} class="w-4 h-4" />
      </button>
    </div>
    """
  end

  attr :part, :map, required: true

  defp part_status(assigns) do
    ~H"""
    <%= case @part.status do %>
      <% :corrected -> %>
        <span class="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-green-50 text-green-700">
          <.icon name="hero-check-badge-mini" class="w-3.5 h-3.5" /> Erledigt
        </span>
      <% :auto -> %>
        <span class="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-purple-50 text-purple-600">
          <.icon name="hero-sparkles-mini" class="w-3.5 h-3.5" /> Automatisch korrigiert
        </span>
      <% :open -> %>
        <span class="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-stone-100 text-stone-500">
          Offen
        </span>
    <% end %>
    """
  end

  attr :part, :map, required: true

  defp part_status_icon(assigns) do
    ~H"""
    <%= case @part.status do %>
      <% :corrected -> %>
        <span class="tooltip tooltip-left tooltip-delayed shrink-0" data-tip="Erledigt">
          <.icon name="hero-check-badge-mini" class="w-4 h-4 text-green-600" />
        </span>
      <% :auto -> %>
        <span class="tooltip tooltip-left tooltip-delayed shrink-0" data-tip="Automatisch korrigiert">
          <.icon name="hero-sparkles-mini" class="w-4 h-4 text-purple-500" />
        </span>
      <% :open -> %>
        <span class="tooltip tooltip-left tooltip-delayed shrink-0" data-tip="Offen">
          <span class="block w-4 h-4 rounded-full border-2 border-stone-300"></span>
        </span>
    <% end %>
    """
  end

  @impl true
  def mount(%{"id" => exam_id}, _session, socket) do
    exam = Exams.get_exam!(socket.assigns.current_scope, exam_id)

    # Same order as the arrows of the part correction.
    submissions =
      exam
      |> Exams.list_exam_submissions()
      |> Enum.sort_by(fn s ->
        {String.downcase(s.firstname || ""), String.downcase(s.lastname || "")}
      end)

    {:ok,
     socket
     |> assign(:exam, exam)
     |> assign(:submissions, submissions)
     |> assign(:max_points, Exams.total_points(exam))}
  end

  @impl true
  def handle_params(%{"submission_id" => submission_id}, _uri, socket) do
    %{exam: exam, submissions: submissions} = socket.assigns

    submission = Exams.get_submission!(exam, submission_id)
    index = Enum.find_index(submissions, &(&1.id == submission.id)) || 0
    parts = build_parts(exam, submission)

    {:noreply,
     socket
     |> assign(:page_title, "#{exam.name} – #{participant_name(submission)}")
     |> assign(:submission, submission)
     |> assign(:submission_index, index)
     |> assign(:parts, parts)
     |> assign(:corrected_count, Enum.count(parts, &(&1.status == :corrected)))
     |> assign(:total_points, total_points(parts))
     |> assign(:prev_submission_path, sibling_path(exam, submissions, index, -1))
     |> assign(:next_submission_path, sibling_path(exam, submissions, index, +1))}
  end

  defp build_parts(exam, submission) do
    max_points = exam.sample_solution_points || %{}
    points = submission.points_per_part || %{}

    submission
    |> Exams.correction_content()
    |> Exams.split_content_into_parts(exam.answer_mode)
    |> Enum.map(fn part ->
      %{
        id: part.id,
        label: part.label,
        doc_json: Jason.encode!(%{"type" => "doc", "content" => part.nodes}),
        points: Map.get(points, part.id),
        max_points: Map.get(max_points, part.id),
        status: part_status_of(submission, part.id),
        grade_path: ~p"/exams/#{exam}/correction/#{submission.id}/parts/#{part.id}"
      }
    end)
  end

  # Done by hand wins over the auto-correction, which only pre-judges.
  defp part_status_of(submission, part_id) do
    cond do
      part_id in (submission.corrected_parts || []) -> :corrected
      part_id in (submission.auto_corrected_parts || []) -> :auto
      true -> :open
    end
  end

  # nil while no part has points yet: "—", not a 0 nobody gave.
  defp total_points(parts) do
    case Enum.filter(parts, &is_number(&1.points)) do
      [] -> nil
      scored -> scored |> Enum.map(& &1.points) |> Enum.sum() |> Grading.normalize_points()
    end
  end

  defp sibling_path(exam, submissions, index, delta) do
    target = index + delta

    if target >= 0 and target < length(submissions) do
      ~p"/exams/#{exam}/correction/#{Enum.at(submissions, target).id}"
    end
  end

  defp points_label(%{points: points, max_points: nil}), do: format_points(points)

  defp points_label(%{points: points, max_points: max}),
    do: "#{format_points(points)} / #{format_points(max)}"

  defp participant_name(submission),
    do: String.trim("#{submission.firstname} #{submission.lastname}")

  defp format_points(n), do: Grading.format_points(n)
end
