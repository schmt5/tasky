defmodule TaskyWeb.Presence do
  @moduledoc """
  Phoenix.Presence process for tracking online users across LiveViews.
  """

  use Phoenix.Presence,
    otp_app: :tasky,
    pubsub_server: Tasky.PubSub
end
