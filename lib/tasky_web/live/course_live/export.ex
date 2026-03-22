defmodule TaskyWeb.CourseLive.Export do
  use TaskyWeb, :live_view

  alias Tasky.Courses
  alias Tasky.Tally.Client

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Floating print button (hidden on print via CSS) --%>
    <button
      id="print-fab"
      class="fab"
      phx-hook=".PrintButton"
      aria-label="Als PDF speichern"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
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
          d="M17 17h2a2 2 0 002-2v-4a2 2 0 00-2-2H5a2 2 0 00-2 2v4a2 2 0 002 2h2m2 4h6a2 2 0 002-2v-4a2 2 0 00-2-2H9a2 2 0 00-2 2v4a2 2 0 002 2zm8-12V5a2 2 0 00-2-2H9a2 2 0 00-2 2v4h10z"
        />
      </svg>
      Als PDF drucken
    </button>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PrintButton">
      export default {
        mounted() {
          this.el.addEventListener("click", () => window.print())
        }
      }
    </script>

    <%= if @loading do %>
      <div class="loading-overlay">
        <div class="loading-spinner"></div>

        <p>Inhalte werden geladen…</p>
      </div>
    <% else %>
      <div class="page-wrapper">
        <%!-- Table of Contents sidebar --%>
        <nav class="toc-sidebar" aria-label="Inhaltsverzeichnis">
          <h2 class="toc-heading">Inhalt</h2>

          <ul class="toc-list">
            <%= for task_content <- @task_contents do %>
              <li>
                <a href={"#task-#{task_content.task_id}"} class="toc-link-h1">
                  {task_content.task_name}
                </a>
                <%= for block <- task_content.blocks do %>
                  <%= cond do %>
                    <% block.type == :heading2 -> %>
                      <a href={"#block-#{block.id}"} class="toc-link-h2">{block.text}</a>
                    <% block.type == :heading3 -> %>
                      <a href={"#block-#{block.id}"} class="toc-link-h3">{block.text}</a>
                    <% true -> %>
                  <% end %>
                <% end %>
              </li>
            <% end %>
          </ul>
        </nav>
        <%!-- Main content --%>
        <main class="main-content">
          <h1 class="course-title">{@course.name}</h1>

          <p class="course-subtitle">{length(@task_contents)} Lerneinheiten</p>

          <%= for task_content <- @task_contents do %>
            <section class="task-section" id={"task-#{task_content.task_id}"}>
              <h2 class="task-title">{task_content.task_name}</h2>

              <%= if task_content.error do %>
                <div class="error-notice">
                  Inhalt konnte nicht geladen werden: {task_content.error}
                </div>
              <% end %>

              <%= if is_nil(task_content.tally_form_id) do %>
                <span class="no-tally-notice">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="14"
                    height="14"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                  >
                    <circle cx="12" cy="12" r="10" /> <line x1="12" y1="8" x2="12" y2="12" />
                    <line x1="12" y1="16" x2="12.01" y2="16" />
                  </svg>
                  Kein Tally-Formular verknüpft
                </span>
              <% else %>
                <%= for block <- task_content.blocks do %>
                  <%= cond do %>
                    <% block.type == :heading2 -> %>
                      <h3 class="block-h2" id={"block-#{block.id}"}>{block.text}</h3>
                    <% block.type == :heading3 -> %>
                      <h4 class="block-h3" id={"block-#{block.id}"}>{block.text}</h4>
                    <% block.type == :text -> %>
                      <div class="block-text">
                        {Phoenix.HTML.raw(block.html)}
                      </div>
                    <% block.type == :image -> %>
                      <figure class="block-image">
                        <img src={block.url} alt={block.alt || ""} loading="lazy" />
                        <%= if block.caption && block.caption != "" do %>
                          <figcaption>{block.caption}</figcaption>
                        <% end %>
                      </figure>
                    <% block.type == :video && block.url != "" -> %>
                      <div class="block-video">
                        <a
                          href={block.url}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="block-video-link"
                          phx-no-format
                        >
                          <div class="block-video-icon">
                            <svg
                              xmlns="http://www.w3.org/2000/svg"
                              width="14"
                              height="14"
                              viewBox="0 0 24 24"
                            >
                              <path d="M8 5v14l11-7z" />
                            </svg>
                          </div>
                          Video ansehen: {block.url}
                        </a>
                      </div>
                    <% block.type == :divider -> %>
                      <hr class="block-divider" />
                    <% block.type == :checkbox -> %>
                      <div class="block-checkbox">
                        <span class="block-checkbox-box"></span>
                        <span class="block-checkbox-text">{block.text}</span>
                      </div>
                    <% block.type == :page_break -> %>
                      <hr class="block-page-break" />
                    <% true -> %>
                  <% end %>
                <% end %>
              <% end %>
            </section>
          <% end %>
        </main>
      </div>
    <% end %>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    course = Courses.get_course!(socket.assigns.current_scope, id)

    socket =
      socket
      |> assign(:page_title, "#{course.name} – Export")
      |> assign(:course, course)
      |> assign(:task_contents, [])
      |> assign(:loading, true)

    if connected?(socket) do
      send(self(), :load_content)
    end

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_info(:load_content, socket) do
    tasks =
      socket.assigns.course.tasks
      |> Enum.sort_by(& &1.position)

    current_scope = socket.assigns.current_scope

    task_contents =
      tasks
      |> Task.async_stream(
        fn task ->
          if task.tally_form_id do
            case Client.fetch_form_content(current_scope, task.tally_form_id) do
              {:ok, %{blocks: blocks}} ->
                %{
                  task_id: task.id,
                  task_name: task.name,
                  tally_form_id: task.tally_form_id,
                  blocks: blocks,
                  error: nil
                }

              {:error, reason} ->
                %{
                  task_id: task.id,
                  task_name: task.name,
                  tally_form_id: task.tally_form_id,
                  blocks: [],
                  error: inspect(reason)
                }
            end
          else
            %{
              task_id: task.id,
              task_name: task.name,
              tally_form_id: nil,
              blocks: [],
              error: nil
            }
          end
        end,
        timeout: :infinity,
        max_concurrency: 4
      )
      |> Enum.map(fn {:ok, result} -> result end)

    {:noreply,
     socket
     |> assign(:task_contents, task_contents)
     |> assign(:loading, false)}
  end
end
