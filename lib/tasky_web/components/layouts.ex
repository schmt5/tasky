defmodule TaskyWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TaskyWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_path, :string,
    default: nil,
    doc: "the current request path, used to highlight the active nav link"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="px-6 py-4 bg-white border-b border-stone-100">
      <div class="max-w-6xl mx-auto flex items-center justify-between">
        <div class="items-center gap-2.5">
          <.link navigate={~p"/"} class="flex items-center gap-2.5">
            <svg width="36" height="36" viewBox="190 60 370 220" xmlns="http://www.w3.org/2000/svg">
              <g transform="translate(190, 60)">
                <path
                  d="M 55 55 L 55 130 Q 55 195 120 195 Q 185 195 185 130 L 185 120 Q 185 55 250 55 Q 315 55 315 120 L 315 195"
                  style="fill:none;stroke:#0ea5e9;stroke-width:52px;stroke-linecap:round;stroke-linejoin:round;"
                />
                <circle cx="55" cy="55" r="34" style="fill:#0ea5e9;" />
                <circle cx="315" cy="195" r="34" style="fill:#0ea5e9;" />
              </g>
            </svg>
            <span class="text-base font-bold text-stone-800 tracking-tight">LearningLine</span>
          </.link>
        </div>

        <nav class="flex items-center gap-2">
          <%= if @current_scope && @current_scope.user do %>
            <%= cond do %>
              <% Tasky.Accounts.Scope.student?(@current_scope) -> %>
                <.link
                  navigate={~p"/student/courses"}
                  class={[
                    "text-sm font-medium px-3.5 py-2 rounded-[10px] transition-all duration-150",
                    if(String.starts_with?(@current_path || "", "/student/courses"),
                      do: "bg-sky-50 text-sky-600 font-semibold",
                      else: "text-stone-500 hover:bg-sky-50 hover:text-sky-600"
                    )
                  ]}
                >
                  Kurse
                </.link>
                <.link
                  navigate={~p"/student/exams"}
                  class={[
                    "text-sm font-medium px-3.5 py-2 rounded-[10px] transition-all duration-150",
                    if(String.starts_with?(@current_path || "", "/student/exams"),
                      do: "bg-sky-50 text-sky-600 font-semibold",
                      else: "text-stone-500 hover:bg-sky-50 hover:text-sky-600"
                    )
                  ]}
                >
                  Prüfungen
                </.link>
              <% Tasky.Accounts.Scope.admin_or_teacher?(@current_scope) -> %>
                <.link
                  navigate={~p"/courses"}
                  class={[
                    "text-sm font-medium px-3.5 py-2 rounded-[10px] transition-all duration-150",
                    if(String.starts_with?(@current_path || "", "/courses"),
                      do: "bg-sky-50 text-sky-600 font-semibold",
                      else: "text-stone-500 hover:bg-sky-50 hover:text-sky-600"
                    )
                  ]}
                >
                  Kurse
                </.link>
                <.link
                  navigate={~p"/catalog"}
                  class={[
                    "text-sm font-medium px-3.5 py-2 rounded-[10px] transition-all duration-150",
                    if(String.starts_with?(@current_path || "", "/catalog"),
                      do: "bg-sky-50 text-sky-600 font-semibold",
                      else: "text-stone-500 hover:bg-sky-50 hover:text-sky-600"
                    )
                  ]}
                >
                  Katalog
                </.link>
                <.link
                  navigate={~p"/classes"}
                  class={[
                    "text-sm font-medium px-3.5 py-2 rounded-[10px] transition-all duration-150",
                    if(String.starts_with?(@current_path || "", "/classes"),
                      do: "bg-sky-50 text-sky-600 font-semibold",
                      else: "text-stone-500 hover:bg-sky-50 hover:text-sky-600"
                    )
                  ]}
                >
                  Klassen
                </.link>
                <.link
                  navigate={~p"/students"}
                  class={[
                    "text-sm font-medium px-3.5 py-2 rounded-[10px] transition-all duration-150",
                    if(String.starts_with?(@current_path || "", "/students"),
                      do: "bg-sky-50 text-sky-600 font-semibold",
                      else: "text-stone-500 hover:bg-sky-50 hover:text-sky-600"
                    )
                  ]}
                >
                  Lernende
                </.link>
                <.link
                  navigate={~p"/exams"}
                  class={[
                    "text-sm font-medium px-3.5 py-2 rounded-[10px] transition-all duration-150",
                    if(String.starts_with?(@current_path || "", "/exams"),
                      do: "bg-sky-50 text-sky-600 font-semibold",
                      else: "text-stone-500 hover:bg-sky-50 hover:text-sky-600"
                    )
                  ]}
                >
                  Prüfungen
                </.link>
              <% true -> %>
            <% end %>
          <% end %>
        </nav>

        <div class="flex items-center gap-3">
          <%= if @current_scope && @current_scope.user do %>
            <div class="dropdown dropdown-end">
              <label
                tabindex="0"
                class="text-sm font-medium text-stone-500 px-3.5 py-2 rounded-[10px] cursor-pointer flex items-center gap-2 transition-all duration-150 hover:bg-stone-100 hover:text-stone-800"
              >
                <.icon name="hero-user-circle" class="w-5 h-5" />
                {@current_scope.user.email}
              </label>
              <ul
                tabindex="0"
                class="dropdown-content z-[1] menu p-2 shadow-lg bg-white rounded-[10px] w-52 mt-2 border border-stone-100"
              >
                <li>
                  <.link navigate={~p"/users/settings"} class="flex items-center gap-2">
                    <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Einstellungen
                  </.link>
                </li>
                <li>
                  <.link href={~p"/users/log-out"} method="delete" class="flex items-center gap-2">
                    <.icon name="hero-arrow-right-on-rectangle" class="w-4 h-4" /> Abmelden
                  </.link>
                </li>
              </ul>
            </div>
          <% else %>
            <.link
              navigate={~p"/users/log-in"}
              class="text-sm font-medium text-stone-500 transition-colors duration-150 hover:text-sky-600"
            >
              Anmelden
            </.link>
          <% end %>
        </div>
      </div>
    </header>

    <main class="bg-stone-50 min-h-screen">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  Flashes stack in the top-right corner; the connection state gets its own
  slim pill centred under the header, so a reconnect never looks like an
  application error.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed top-20 right-4 z-70 flex flex-col items-end gap-3"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:success} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>

    <.connection_status />
    """
  end

  @doc """
  Shows the LiveView connection state as a slim pill under the header.

  Both pills carry a built-in delay (see `.ll-conn` in `app.css`), so short
  reconnects — the app sleeps on a scale-to-zero machine — stay invisible and
  only a genuinely slow wake-up is announced.
  """
  def connection_status(assigns) do
    ~H"""
    <div class="pointer-events-none fixed inset-x-0 top-20 z-80 flex flex-col items-center gap-2 px-4">
      <div
        id="connection-status"
        class="ll-conn flex items-center gap-2.5 rounded-full border border-sky-200 bg-sky-50/95 px-4 py-2 text-sm font-medium text-sky-900 shadow-[0_10px_30px_-12px_rgba(28,25,23,0.35)] backdrop-blur-sm"
        role="status"
        hidden
        phx-disconnected={JS.remove_attribute("hidden", to: ".phx-client-error #connection-status")}
        phx-connected={JS.set_attribute({"hidden", ""}, to: "#connection-status")}
      >
        <span class="ll-spinner size-4 shrink-0 rounded-full border-2 border-sky-200 border-t-sky-500" />
        Verbindung wird hergestellt …
      </div>

      <div
        id="server-status"
        class="ll-conn flex items-center gap-2.5 rounded-full border border-amber-200 bg-amber-50/95 px-4 py-2 text-sm font-medium text-amber-900 shadow-[0_10px_30px_-12px_rgba(28,25,23,0.35)] backdrop-blur-sm"
        role="status"
        hidden
        phx-disconnected={JS.remove_attribute("hidden", to: ".phx-server-error #server-status")}
        phx-connected={JS.set_attribute({"hidden", ""}, to: "#server-status")}
      >
        <span class="ll-spinner size-4 shrink-0 rounded-full border-2 border-amber-200 border-t-amber-500" />
        Kurz gestolpert – wir versuchen es erneut …
      </div>
    </div>
    """
  end

  @doc """
  Renders a minimal guest layout for exam participants.

  This layout provides a distraction-free experience with just
  the LearningLine logo and no navigation or user controls.

  ## Examples

      <Layouts.guest flash={@flash}>
        <h1>Exam Content</h1>
      </Layouts.guest>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  slot :inner_block, required: true

  def guest(assigns) do
    ~H"""
    <header class="px-6 py-4 bg-white border-b border-stone-100">
      <div class="max-w-4xl mx-auto flex items-center justify-center">
        <svg width="36" height="36" viewBox="190 60 370 220" xmlns="http://www.w3.org/2000/svg">
          <g transform="translate(190, 60)">
            <path
              d="M 55 55 L 55 130 Q 55 195 120 195 Q 185 195 185 130 L 185 120 Q 185 55 250 55 Q 315 55 315 120 L 315 195"
              style="fill:none;stroke:#0ea5e9;stroke-width:52px;stroke-linecap:round;stroke-linejoin:round;"
            />
            <circle cx="55" cy="55" r="34" style="fill:#0ea5e9;" />
            <circle cx="315" cy="195" r="34" style="fill:#0ea5e9;" />
          </g>
        </svg>
        <span class="text-base font-bold text-stone-800 tracking-tight">LearningLine</span>
      </div>
    </header>

    <main class="bg-stone-50 min-h-screen">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
