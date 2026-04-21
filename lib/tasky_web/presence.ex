defmodule TaskyWeb.Presence do
  use Phoenix.Presence,
    otp_app: :tasky,
    pubsub_server: Tasky.PubSub
end
