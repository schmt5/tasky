defmodule TaskyWeb.Confirm do
  @moduledoc """
  Confirmation dialogs held by the LiveView, in place of the browser's native
  `data-confirm` prompt (which cannot be styled and cannot be tested).

  A button asks instead of acting: `phx-click="ask_confirm"` with
  `phx-value-action` naming the event that does the work, plus that event's
  own `phx-value-*` params. The LiveView describes the dialog for that action
  and keeps the pending event in `@confirm`; on `"confirmed"` the event runs
  through the LiveView's own `handle_event/3`. The event that does the work is
  therefore unchanged — and, as before, directly reachable: the dialog is a
  safeguard against a slip, not an authorization step.

  Wiring in a LiveView:

      # mount
      |> assign(:confirm, nil)

      # template, anywhere inside <Layouts.app>
      <.confirm_dialog confirm={@confirm} />

      # the button
      <button phx-click="ask_confirm" phx-value-action="delete" phx-value-id={item.id}>

      # events
      def handle_event("ask_confirm", params, socket),
        do: {:noreply, Confirm.ask(socket, params, &describe_confirm(&1, &2, socket))}

      def handle_event("cancel_confirm", _params, socket),
        do: {:noreply, Confirm.cancel(socket)}

      def handle_event("confirmed", _params, socket),
        do: Confirm.run(socket, &handle_event/3)

      # the dialog per action; nil for anything else
      defp describe_confirm("delete", %{"id" => id}, socket), do: %{title: "…", …}
      defp describe_confirm(_action, _params, _socket), do: nil

  A dialog is a map with `:title` (required), `:message`, `:confirm_label`,
  `:icon` and `:tone`. `:tone` is `:danger` (red) only when confirming
  destroys data; everything reversible uses `:primary` (sky).
  """

  import Phoenix.Component, only: [assign: 3]

  @defaults %{message: nil, confirm_label: "Bestätigen", icon: nil, tone: :primary}

  @type dialog :: %{
          required(:title) => String.t(),
          optional(:message) => String.t() | nil,
          optional(:confirm_label) => String.t(),
          optional(:icon) => String.t() | nil,
          optional(:tone) => :danger | :primary
        }

  @doc """
  Opens the dialog for `params["action"]`, as described by `describe`
  (`action, params -> dialog | nil`). Does nothing when `describe` returns nil:
  an unknown action or a record that no longer exists.
  """
  @spec ask(Phoenix.LiveView.Socket.t(), map(), (String.t(), map() -> dialog() | nil)) ::
          Phoenix.LiveView.Socket.t()
  def ask(socket, %{"action" => action} = params, describe)
      when is_binary(action) and is_function(describe, 2) do
    params = Map.delete(params, "action")

    case describe.(action, params) do
      %{title: _} = dialog ->
        pending = @defaults |> Map.merge(dialog) |> Map.merge(%{event: action, params: params})
        pending = Map.update!(pending, :icon, &(&1 || default_icon(pending.tone)))
        assign(socket, :confirm, pending)

      nil ->
        socket
    end
  end

  def ask(socket, _params, _describe), do: socket

  @doc "Closes the dialog without running anything."
  @spec cancel(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def cancel(socket), do: assign(socket, :confirm, nil)

  @doc """
  Closes the dialog and runs the pending event through `handle_event`
  (the LiveView's own `&handle_event/3`). Without a pending event — a stale
  click after the dialog closed — it does nothing.
  """
  @spec run(Phoenix.LiveView.Socket.t(), (String.t(), map(), Phoenix.LiveView.Socket.t() ->
                                            term())) :: term()
  def run(%{assigns: %{confirm: %{event: event, params: params}}} = socket, handle_event),
    do: handle_event.(event, params, cancel(socket))

  def run(socket, _handle_event), do: {:noreply, socket}

  defp default_icon(:danger), do: "hero-trash"
  defp default_icon(_tone), do: "hero-question-mark-circle"
end
