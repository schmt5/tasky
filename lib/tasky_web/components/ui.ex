defmodule TaskyWeb.UI do
  @moduledoc """
  Reusable UI components using Tailwind CSS utilities.
  Based on Tally.so-inspired design system.
  """
  use Phoenix.Component
  import TaskyWeb.CoreComponents, only: [icon: 1]

  @doc """
  Primary button - sky blue with shadow.

  ## Examples

      <.button_primary navigate={~p"/tasks/new"}>
        <.icon name="hero-plus" class="w-4 h-4" /> New Task
      </.button_primary>
  """
  attr :navigate, :string, default: nil
  attr :href, :string, default: nil
  attr :patch, :string, default: nil
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def button_primary(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      href={@href}
      patch={@patch}
      class={[
        "inline-flex items-center gap-2 bg-sky-500 text-white font-semibold rounded-[10px] shadow-[0_2px_8px_rgba(14,165,233,0.25)] transition-all duration-150 hover:bg-sky-600 active:scale-[0.98]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Secondary button - white with sky border.
  """
  attr :navigate, :string, default: nil
  attr :href, :string, default: nil
  attr :patch, :string, default: nil
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def button_secondary(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      href={@href}
      patch={@patch}
      class={[
        "inline-flex items-center gap-2 bg-white text-sky-600 font-semibold rounded-[10px] border-[1.5px] border-sky-200 transition-all duration-150 hover:bg-sky-50 active:scale-[0.98]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Ghost button - transparent with hover effect.
  """
  attr :navigate, :string, default: nil
  attr :href, :string, default: nil
  attr :patch, :string, default: nil
  attr :phx_click, :string, default: nil
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def button_ghost(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      href={@href}
      patch={@patch}
      phx-click={@phx_click}
      class={[
        "inline-flex items-center gap-2 bg-transparent text-stone-500 font-medium rounded-[10px] transition-all duration-150 hover:bg-sky-50 hover:text-sky-600",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Danger ghost button - red text with hover effect.
  """
  attr :phx_click, :string, default: nil
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def button_danger(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@phx_click}
      class={[
        "inline-flex items-center gap-2 text-red-600 font-medium rounded-[10px] transition-all duration-150 hover:bg-red-100 hover:text-red-700",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Status badge component.

  ## Examples

      <.badge color="sky">Published</.badge>
      <.badge color="green">Completed</.badge>
      <.badge color="red">Archived</.badge>
  """
  attr :color, :string, default: "stone"
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center text-[11px] font-semibold px-2.5 py-0.5 rounded-full whitespace-nowrap tracking-[0.01em]",
      badge_color(@color),
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_color("sky"), do: "bg-sky-100 text-sky-700"
  defp badge_color("green"), do: "bg-green-50 text-green-700"
  defp badge_color("red"), do: "bg-red-100 text-red-700"
  defp badge_color("amber"), do: "bg-amber-50 text-amber-700"
  defp badge_color("stone"), do: "bg-stone-100 text-stone-600"
  defp badge_color(_), do: "bg-stone-100 text-stone-600"

  @doc """
  Page header with eyebrow, title, and description.

  ## Examples

      <.page_header eyebrow="Task Management">
        <:title>Listing <em>Tasks</em></:title>
        <:description>Manage all tasks and assignments.</:description>
      </.page_header>
  """
  attr :eyebrow, :string, required: true
  slot :title, required: true
  slot :description, required: false

  def page_header(assigns) do
    ~H"""
    <div class="bg-white border-b border-stone-100 px-8 py-12">
      <div class="text-[11px] tracking-[0.1em] uppercase font-semibold text-sky-500 mb-3">
        {@eyebrow}
      </div>
      <h1 class="font-serif text-[42px] text-stone-900 leading-[1.1] mb-3 font-normal">
        {render_slot(@title)}
      </h1>
      <p :if={@description != []} class="text-[15px] text-stone-500 max-w-[560px] leading-[1.7]">
        {render_slot(@description)}
      </p>
    </div>
    """
  end

  @doc """
  Content card container.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={[
      "bg-white rounded-[14px] border border-stone-100 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.07),0_1px_2px_rgba(0,0,0,0.04)]",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Card header with title and optional action.
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :action, required: false

  def card_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-6 border-b border-stone-100">
      <div>
        <h2 class="text-lg font-semibold text-stone-800">{@title}</h2>
        <p :if={@subtitle} class="text-sm text-stone-500 mt-1">{@subtitle}</p>
      </div>
      <div :if={@action != []}>{render_slot(@action)}</div>
    </div>
    """
  end

  @doc """
  Empty state component.
  """
  attr :icon_name, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  slot :action, required: false

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center text-center px-8 py-16 bg-white">
      <div class="w-14 h-14 rounded-[14px] bg-sky-50 flex items-center justify-center text-sky-400 mb-5">
        <.icon name={@icon_name} class="w-6 h-6" />
      </div>
      <h3 class="text-base font-semibold text-stone-700 mb-2">{@title}</h3>
      <p class="text-sm text-stone-400 max-w-[320px] leading-[1.6]">{@description}</p>
      <div :if={@action != []} class="mt-6">{render_slot(@action)}</div>
    </div>
    """
  end

  @doc """
  List item icon with background color.
  """
  attr :color, :string, default: "sky"
  attr :icon_name, :string, required: true
  attr :navigate, :string, default: nil

  def list_icon(assigns) do
    ~H"""
    <.link
      :if={@navigate}
      navigate={@navigate}
      class={[
        "w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5",
        icon_color(@color)
      ]}
    >
      <.icon name={@icon_name} class="w-5 h-5" />
    </.link>
    <div
      :if={!@navigate}
      class={[
        "w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0 mt-0.5",
        icon_color(@color)
      ]}
    >
      <.icon name={@icon_name} class="w-5 h-5" />
    </div>
    """
  end

  defp icon_color("sky"), do: "bg-sky-100 text-sky-600"
  defp icon_color("green"), do: "bg-green-50 text-green-700"
  defp icon_color("red"), do: "bg-red-100 text-red-600"
  defp icon_color("amber"), do: "bg-amber-50 text-amber-700"
  defp icon_color("stone"), do: "bg-stone-100 text-stone-500"
  defp icon_color(_), do: "bg-stone-100 text-stone-500"

  @doc """
  Eyebrow badge for hero sections.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <div class={[
      "inline-flex items-center gap-1.5 bg-sky-50 text-sky-600 text-xs font-semibold px-3.5 py-1.5 rounded-full tracking-wide",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Size variants for buttons.
  """
  def button_size("sm"), do: "text-[13px] px-3.5 py-1.5 rounded-[6px]"
  def button_size("md"), do: "text-sm px-5 py-2.5 rounded-[10px]"
  def button_size("lg"), do: "text-[15px] px-7 py-3.5 rounded-[14px]"
  def button_size(_), do: button_size("md")
end
