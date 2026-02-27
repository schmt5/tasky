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

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="flex items-center justify-between px-6 py-4 bg-white border-b border-stone-100">
      <div class="flex items-center gap-2.5">
        <.link navigate={~p"/"} class="flex items-center gap-2.5">
          <div class="w-9 h-9 flex items-center justify-center shrink-0 bg-gradient-to-br from-sky-400 to-sky-600 rounded-[10px] shadow-[0_2px_6px_rgba(14,165,233,0.3)]">
            <svg
              width="18"
              height="18"
              fill="none"
              viewBox="0 0 24 24"
              stroke="white"
              stroke-width="2.5"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
              />
            </svg>
          </div>
          <span class="text-base font-bold text-stone-800 tracking-tight">Tasky</span>
        </.link>
      </div>

      <nav class="flex items-center gap-2">
        <%= if @current_scope && @current_scope.user do %>
          <%= cond do %>
            <% Tasky.Accounts.Scope.student?(@current_scope) -> %>
              <.link
                navigate={~p"/student/courses"}
                class="text-sm font-medium text-stone-500 px-3.5 py-2 rounded-[10px] transition-all duration-150 hover:bg-sky-50 hover:text-sky-600"
              >
                Courses
              </.link>
              <.link
                navigate={~p"/student/my-tasks"}
                class="text-sm font-medium text-stone-500 px-3.5 py-2 rounded-[10px] transition-all duration-150 hover:bg-sky-50 hover:text-sky-600"
              >
                My Tasks
              </.link>
            <% Tasky.Accounts.Scope.admin_or_teacher?(@current_scope) -> %>
              <.link
                navigate={~p"/courses"}
                class="text-sm font-medium text-stone-500 px-3.5 py-2 rounded-[10px] transition-all duration-150 hover:bg-sky-50 hover:text-sky-600"
              >
                Courses
              </.link>
              <.link
                navigate={~p"/tasks"}
                class="text-sm font-medium text-stone-500 px-3.5 py-2 rounded-[10px] transition-all duration-150 hover:bg-sky-50 hover:text-sky-600"
              >
                Tasks
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
                  <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Settings
                </.link>
              </li>
              <li>
                <.link href={~p"/users/log-out"} method="delete" class="flex items-center gap-2">
                  <.icon name="hero-arrow-right-on-rectangle" class="w-4 h-4" /> Log out
                </.link>
              </li>
            </ul>
          </div>
        <% else %>
          <.link
            navigate={~p"/users/log-in"}
            class="text-sm font-medium text-stone-500 transition-colors duration-150 hover:text-sky-600"
          >
            Log in
          </.link>
          <.link
            navigate={~p"/users/register"}
            class="inline-flex items-center gap-2 bg-sky-500 text-white text-sm font-semibold px-5 py-2.5 rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]"
          >
            Sign up
          </.link>
        <% end %>
      </div>
    </header>

    <main class="bg-stone-50 min-h-screen">
      <div class="max-w-6xl mx-auto px-6 py-8">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
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
