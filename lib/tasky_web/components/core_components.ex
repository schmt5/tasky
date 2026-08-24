defmodule TaskyWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: TaskyWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  Four kinds are supported: `:info` and `:success` are transient and fade out
  on their own, `:warning` and `:error` stay until they are dismissed.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:success} phx-mounted={show("#flash")}>Willkommen zurück!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil

  attr :kind, :atom,
    values: [:info, :success, :warning, :error],
    doc: "used for styling and flash lookup"

  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  # Tone per kind: a soft tinted card, a matching icon badge and the colour of
  # the countdown line. `:dismiss_after` is the auto-dismiss delay in ms —
  # `nil` keeps the message up until it is clicked away.
  @flash_tones %{
    info: %{
      icon: "hero-information-circle",
      card: "bg-sky-50 border-sky-200",
      badge: "bg-sky-100 text-sky-600",
      title: "text-sky-900",
      bar: "bg-sky-400",
      dismiss_after: 5000
    },
    success: %{
      icon: "hero-check-circle",
      card: "bg-emerald-50 border-emerald-200",
      badge: "bg-emerald-100 text-emerald-600",
      title: "text-emerald-900",
      bar: "bg-emerald-400",
      dismiss_after: 5000
    },
    warning: %{
      icon: "hero-exclamation-triangle",
      card: "bg-amber-50 border-amber-200",
      badge: "bg-amber-100 text-amber-700",
      title: "text-amber-900",
      bar: "bg-amber-400",
      dismiss_after: nil
    },
    error: %{
      icon: "hero-exclamation-circle",
      card: "bg-rose-50 border-rose-200",
      badge: "bg-rose-100 text-rose-600",
      title: "text-rose-900",
      bar: "bg-rose-400",
      dismiss_after: nil
    }
  }

  def flash(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn -> "flash-#{assigns.kind}" end)
      |> assign(:tone, Map.fetch!(@flash_tones, assigns.kind))

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      phx-hook=".FlashAutoDismiss"
      data-dismiss-after={@tone.dismiss_after}
      role={if @kind in [:warning, :error], do: "alert", else: "status"}
      class={[
        "ll-flash pointer-events-auto w-80 sm:w-96 cursor-pointer overflow-hidden",
        "rounded-xl border shadow-[0_10px_30px_-12px_rgba(28,25,23,0.35)]",
        @tone.card
      ]}
      {@rest}
    >
      <div class="flex items-start gap-3 px-4 py-3.5">
        <span class={[
          "mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full",
          @tone.badge
        ]}>
          <.icon name={@tone.icon} class="size-5" />
        </span>
        <div class="min-w-0 flex-1">
          <p :if={@title} class={["text-sm font-semibold", @tone.title]}>{@title}</p>
          <p class={["text-sm leading-relaxed text-stone-600 text-wrap", @title && "mt-0.5"]}>
            {msg}
          </p>
        </div>
        <button
          type="button"
          class="-mr-1 shrink-0 rounded-lg p-1 text-stone-400 transition-colors duration-150 hover:bg-stone-900/5 hover:text-stone-600"
          aria-label={gettext("close")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <div
        :if={@tone.dismiss_after}
        class={["ll-flash-progress h-0.5 w-full origin-left", @tone.bar]}
        style={"animation-duration: #{@tone.dismiss_after}ms"}
      />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".FlashAutoDismiss">
        // Auto-dismisses transient flashes after `data-dismiss-after` ms and
        // pauses the countdown (and the progress line) while hovered, so a
        // message is never yanked away mid-read.
        export default {
          mounted() {
            // Warning and error flashes carry no `data-dismiss-after`: they
            // stay up until the reader clicks them away.
            this.remaining = parseInt(this.el.dataset.dismissAfter || "0", 10);
            if (!this.remaining) return;
            this.armed = true;

            this.onEnter = () => this.pause();
            this.onLeave = () => this.resume();
            this.el.addEventListener("mouseenter", this.onEnter);
            this.el.addEventListener("mouseleave", this.onLeave);
            this.resume();
          },
          resume() {
            this.startedAt = Date.now();
            this.timer = setTimeout(() => this.el.click(), this.remaining);
          },
          pause() {
            clearTimeout(this.timer);
            this.remaining -= Date.now() - this.startedAt;
          },
          destroyed() {
            if (!this.armed) return;
            clearTimeout(this.timer);
            this.el.removeEventListener("mouseenter", this.onEnter);
            this.el.removeEventListener("mouseleave", this.onLeave);
          },
        }
      </script>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={
              @class ||
                "w-[18px] h-[18px] rounded-md border-stone-300 text-sky-500 focus:ring-sky-500/30 focus:ring-offset-0 cursor-pointer transition-colors duration-150 shrink-0"
            }
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0 bg-zinc-50/90 transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white p-14 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label="close"
                >
                  <.icon name="hero-x-mark-solid" class="h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  ## JS Commands

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Renders a back navigation link with a left arrow icon.

  ## Examples

      <.back_link navigate={~p"/courses"} />
      <.back_link navigate={~p"/courses/1"} label="Zurück zum Kurs" />
  """
  attr :navigate, :string, required: true
  attr :label, :string, default: "Zurück"

  def back_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="inline-flex items-center gap-1.5 text-[13px] font-semibold text-stone-600 hover:text-stone-900 transition-colors duration-150"
    >
      <.icon name="hero-arrow-left" class="w-4 h-4" />{@label}
    </.link>
    """
  end

  @doc """
  Renders a circular icon-only back button, typically placed to the left of a page heading.

  The `tooltip` is shown via the daisyUI `tooltip-delayed` pattern.

  ## Examples

      <.back_button navigate={~p"/exams/\#{@exam}"} tooltip={"Zurück zu \#{@exam.name}"} />
  """
  attr :navigate, :string, required: true
  attr :tooltip, :string, required: true
  attr :tooltip_position, :string, default: "tooltip-right"
  attr :size, :string, default: "md", values: ~w(md sm)

  def back_button(assigns) do
    {box, icon} =
      case assigns.size do
        "sm" -> {"w-7 h-7", "w-4 h-4"}
        _ -> {"w-10 h-10", "w-5 h-5"}
      end

    assigns = assign(assigns, box_class: box, icon_class: icon)

    ~H"""
    <div class={["tooltip tooltip-delayed", @tooltip_position]} data-tip={@tooltip}>
      <.link
        navigate={@navigate}
        class={[
          "inline-flex items-center justify-center rounded-full text-stone-500 hover:bg-stone-100/60 hover:text-stone-700 transition-colors duration-150",
          @box_class
        ]}
      >
        <.icon name="hero-arrow-left" class={@icon_class} />
      </.link>
    </div>
    """
  end

  @doc """
  Renders a breadcrumb trail.

  Each crumb is a map with `:label` (string) and optionally `:navigate` (path).
  The last crumb is rendered as plain text (current page).

  ## Examples

      <.breadcrumbs crumbs={[
        %{label: "Kurse", navigate: ~p"/courses"},
        %{label: @course.name, navigate: ~p"/courses/\#{@course}"},
        %{label: "Fortschritt"}
      ]} />
  """
  attr :crumbs, :list, required: true

  def breadcrumbs(assigns) do
    ~H"""
    <nav class="flex items-center gap-1.5 text-[13px] font-semibold flex-wrap">
      <%= for {crumb, index} <- Enum.with_index(@crumbs) do %>
        <%= if index < length(@crumbs) - 1 do %>
          <.link
            navigate={crumb.navigate}
            class="text-stone-400 hover:text-stone-700 transition-colors duration-150 whitespace-nowrap"
          >
            {crumb.label}
          </.link>
          <span class="text-stone-300 select-none">/</span>
        <% else %>
          <span class="text-stone-800 whitespace-nowrap">{crumb.label}</span>
        <% end %>
      <% end %>
    </nav>
    """
  end

  @doc ~S|Initials for an avatar chip, e.g. "MH"; missing names yield "?".|
  def initials(%{firstname: firstname, lastname: lastname}) do
    initial(firstname) <> initial(lastname)
  end

  defp initial(nil), do: "?"
  defp initial(""), do: "?"
  defp initial(name), do: name |> String.first() |> String.upcase()

  @doc """
  Round initials chip for a person — a student, a user or an exam submission.

  One component for every surface that lists people, so the exam path cannot
  drift away from the course/admin pages again (it had grown its own
  blue-to-indigo gradient). It also goes through `initials/1`, which survives a
  missing first or last name — inlined `String.first/1` raises on `nil`.

  ## Examples

      <.participant_avatar person={submission} />
      <.participant_avatar person={student} size="sm" />
  """
  attr :person, :map, required: true
  attr :size, :string, default: "md", values: ~w(md sm lg)
  attr :class, :any, default: nil

  def participant_avatar(assigns) do
    ~H"""
    <div
      class={[
        "rounded-full flex items-center justify-center shrink-0 bg-sky-100 text-sky-700 font-semibold",
        avatar_size(@size),
        @class
      ]}
      aria-hidden="true"
    >
      {initials(@person)}
    </div>
    """
  end

  defp avatar_size("sm"), do: "w-8 h-8 text-[11px]"
  defp avatar_size("lg"), do: "w-12 h-12 text-[15px]"
  defp avatar_size(_), do: "w-9 h-9 text-xs"

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(TaskyWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(TaskyWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Status chip for a learning unit (`draft`, `published` or `archived`).

  Shared so the course overview and the reorder page cannot drift apart.
  """
  attr :status, :string, required: true

  def task_status_chip(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center text-[11px] font-semibold px-2.5 py-0.5 rounded-full whitespace-nowrap tracking-[0.01em]",
      case @status do
        "published" -> "bg-emerald-100 text-emerald-700"
        "archived" -> "bg-stone-100 text-stone-600"
        _ -> "bg-amber-100 text-amber-700"
      end
    ]}>
      {case @status do
        "published" -> "Veröffentlicht"
        "archived" -> "Archiviert"
        _ -> "Entwurf"
      end}
    </span>
    """
  end

  @doc """
  Chip marking a learning unit as an "erweiterte Lerneinheit" — a voluntary
  extra that does not count towards the mandatory progress bar.

  Violet is reserved for this axis: it must not collide with the status chip
  (emerald/amber/stone) or the "Gesperrt" chip (red).
  """
  attr :label, :string, default: "Erweitert"

  def extended_chip(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 text-[11px] font-semibold px-2.5 py-0.5 rounded-full whitespace-nowrap tracking-[0.01em] bg-violet-100 text-violet-700">
      <.icon name="hero-sparkles" class="w-3 h-3" />{@label}
    </span>
    """
  end

  @doc """
  Progress modal for the file-copy phase of a course duplication or a
  catalog import.

  Deliberately without a close button or backdrop click: the records are
  already committed when this appears (see `Tasky.Courses.DuplicateRunner`), so
  there is nothing left to cancel. `@status` is the `%{done:, total:}` map the
  runner reports.
  """
  attr :id, :string, default: "duplicate-progress-modal"
  attr :status, :map, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true

  def duplicate_progress_modal(assigns) do
    ~H"""
    <dialog id={@id} class="modal modal-open">
      <div class="modal-backdrop bg-stone-900/50"></div>
      <div class="modal-box max-w-md p-0 bg-white rounded-[14px] shadow-2xl border border-stone-200">
        <div class="p-6 border-b border-stone-100">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-xl bg-sky-50 flex items-center justify-center shrink-0">
              <.icon name="hero-arrow-path" class="w-5 h-5 text-sky-600 motion-safe:animate-spin" />
            </div>
            <div>
              <h3 class="text-lg font-semibold text-stone-800">{@title}</h3>
              <p class="text-xs text-stone-400 mt-0.5">{@subtitle}</p>
            </div>
          </div>
        </div>
        <div class="p-6">
          <div class="flex items-center justify-between text-sm text-stone-600">
            <span>Dateien</span>
            <span class="font-semibold text-stone-800 tabular-nums">
              {@status.done}/{@status.total}
            </span>
          </div>
          <div
            class="mt-3 h-2 w-full rounded-full bg-stone-100 overflow-hidden"
            role="progressbar"
            aria-valuemin="0"
            aria-valuemax={@status.total}
            aria-valuenow={@status.done}
            aria-label="Fortschritt beim Kopieren der Dateien"
          >
            <div
              class="h-full rounded-full bg-sky-500 transition-[width] duration-300"
              style={"width: #{copy_percent(@status)}%"}
            >
            </div>
          </div>
        </div>
      </div>
    </dialog>
    """
  end

  defp copy_percent(%{total: total}) when total <= 0, do: 100
  defp copy_percent(%{done: done, total: total}), do: round(done / total * 100)

  @doc """
  A vertical radio group where every option carries a label and a description.

  Das Gegenstück zu `checkbox_field/1` für Felder mit mehr als zwei Zuständen:
  `<.input type="select">` versteckt die Erklärung der einzelnen Optionen hinter
  dem Aufklappen, hier steht sie neben der Auswahl.

  `options` ist eine Liste von `%{value:, label:, description:}` — die
  Beschreibung ist optional.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :legend, :string, default: nil
  attr :accent, :string, default: "sky", values: ~w(sky violet)
  attr :options, :list, required: true

  def radio_group(assigns) do
    ~H"""
    <fieldset>
      <legend :if={@legend} class="text-sm font-medium text-stone-700 mb-2">{@legend}</legend>
      <div class="space-y-2">
        <label
          :for={option <- @options}
          class={[
            "flex items-start gap-3 cursor-pointer rounded-lg border px-3.5 py-3 transition-colors duration-150",
            "border-stone-200 hover:bg-stone-50",
            @accent == "sky" && "has-[:checked]:border-sky-300 has-[:checked]:bg-sky-50/60",
            @accent == "violet" && "has-[:checked]:border-violet-300 has-[:checked]:bg-violet-50/60"
          ]}
        >
          <input
            type="radio"
            id={"#{@field.id}-#{option.value}"}
            name={@field.name}
            value={option.value}
            checked={to_string(@field.value) == to_string(option.value)}
            class={[
              "mt-0.5 w-[18px] h-[18px] border-stone-300 cursor-pointer transition-colors duration-150 shrink-0 focus:ring-offset-0",
              @accent == "violet" && "text-violet-500 focus:ring-violet-500/30",
              @accent == "sky" && "text-sky-500 focus:ring-sky-500/30"
            ]}
          />
          <span class="min-w-0">
            <span class="block text-sm font-medium text-stone-700">{option.label}</span>
            <span
              :if={Map.get(option, :description)}
              class="block text-xs text-stone-500 mt-0.5 leading-relaxed"
            >
              {option.description}
            </span>
          </span>
        </label>
      </div>
    </fieldset>
    """
  end

  @doc """
  A checkbox with a bold label and an explanatory description underneath.

  `<.input type="checkbox">` renders the label inline and has nowhere to put a
  description, so this is the house pattern for flags that need explaining.
  Bind it to a form field so the value round-trips like any other input.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :description, :string, required: true
  attr :accent, :string, default: "sky", values: ~w(sky violet)

  def checkbox_field(assigns) do
    ~H"""
    <label class="flex items-start gap-3 cursor-pointer">
      <input type="hidden" name={@field.name} value="false" />
      <input
        type="checkbox"
        id={@field.id}
        name={@field.name}
        value="true"
        checked={Phoenix.HTML.Form.normalize_value("checkbox", @field.value)}
        class={[
          "mt-0.5 w-[18px] h-[18px] rounded-md border-stone-300 cursor-pointer transition-colors duration-150 shrink-0 focus:ring-offset-0",
          @accent == "violet" && "text-violet-500 focus:ring-violet-500/30",
          @accent == "sky" && "text-sky-500 focus:ring-sky-500/30"
        ]}
      />
      <span class="min-w-0">
        <span class="block text-sm font-medium text-stone-700">{@label}</span>
        <span class="block text-xs text-stone-500 mt-0.5 leading-relaxed">{@description}</span>
      </span>
    </label>
    """
  end

  attr :status, :string, required: true

  def exam_status_chip(assigns) do
    ~H"""
    <%= cond do %>
      <% @status == "open" -> %>
        <span class="inline-flex items-center gap-1.5 bg-blue-50 text-blue-600 text-xs font-semibold px-3 py-1 rounded-full ring-1 ring-blue-200">
          <span class="w-1.5 h-1.5 rounded-full bg-blue-500"></span> Offen
        </span>
      <% @status == "running" -> %>
        <span class="inline-flex items-center gap-1.5 bg-emerald-50 text-emerald-600 text-xs font-semibold px-3 py-1 rounded-full ring-1 ring-emerald-200">
          <span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span> Laufend
        </span>
      <% @status == "finished" -> %>
        <span class="inline-flex items-center gap-1.5 bg-stone-100 text-stone-500 text-xs font-semibold px-3 py-1 rounded-full ring-1 ring-stone-200">
          <span class="w-1.5 h-1.5 rounded-full bg-stone-400"></span> Beendet
        </span>
      <% @status == "archived" -> %>
        <span class="inline-flex items-center gap-1.5 bg-stone-100 text-stone-400 text-xs font-semibold px-3 py-1 rounded-full ring-1 ring-stone-200">
          <span class="w-1.5 h-1.5 rounded-full bg-stone-300"></span> Archiviert
        </span>
      <% true -> %>
        <span class="inline-flex items-center gap-1.5 bg-amber-50 text-amber-600 text-xs font-semibold px-3 py-1 rounded-full ring-1 ring-amber-200">
          <span class="w-1.5 h-1.5 rounded-full bg-amber-400"></span> Entwurf
        </span>
    <% end %>
    """
  end
end
