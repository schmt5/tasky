defmodule TaskyWeb.ConfirmTest do
  use ExUnit.Case, async: true

  alias TaskyWeb.Confirm

  defp socket, do: %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, confirm: nil}}

  defp describe_dialog("delete", %{"id" => "7"}), do: %{title: "Löschen?", tone: :danger}
  defp describe_dialog(_action, _params), do: nil

  describe "ask/3" do
    test "holds the event and its params, without the action key" do
      socket = Confirm.ask(socket(), %{"action" => "delete", "id" => "7"}, &describe_dialog/2)

      assert %{event: "delete", params: %{"id" => "7"}, title: "Löschen?", tone: :danger} =
               socket.assigns.confirm
    end

    test "fills in the defaults" do
      socket = Confirm.ask(socket(), %{"action" => "delete", "id" => "7"}, &describe_dialog/2)

      assert %{confirm_label: "Bestätigen", message: nil, icon: "hero-trash"} =
               socket.assigns.confirm
    end

    test "opens nothing for an action the LiveView does not describe" do
      assert Confirm.ask(socket(), %{"action" => "other"}, &describe_dialog/2).assigns.confirm ==
               nil

      assert Confirm.ask(socket(), %{"id" => "7"}, &describe_dialog/2).assigns.confirm == nil
    end
  end

  describe "run/2" do
    test "runs the pending event with its params and closes the dialog" do
      socket = Confirm.ask(socket(), %{"action" => "delete", "id" => "7"}, &describe_dialog/2)

      assert {:ran, "delete", %{"id" => "7"}, nil} =
               Confirm.run(socket, fn event, params, socket ->
                 {:ran, event, params, socket.assigns.confirm}
               end)
    end

    test "does nothing without a pending event" do
      assert {:noreply, %{assigns: %{confirm: nil}}} =
               Confirm.run(socket(), fn _, _, _ -> flunk("must not run") end)
    end
  end

  test "cancel/1 closes the dialog" do
    socket = Confirm.ask(socket(), %{"action" => "delete", "id" => "7"}, &describe_dialog/2)
    assert Confirm.cancel(socket).assigns.confirm == nil
  end
end
