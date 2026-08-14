defmodule TaskyWeb.GuestRateLimit do
  @moduledoc """
  `on_mount` hook that spends the guest probing budget on LiveView mounts.

  The `:guest_rate_limit` pipeline only runs on HTTP requests. Both guest
  LiveViews live in the same `live_session`, so after one legitimate page load a
  client can `live_redirect` to arbitrary `/guest/enroll/:token` and
  `/guest/exam/:token` URLs over the open websocket — and `EnrollLive.mount`
  answers each with a clean invalid/valid/unavailable oracle. Without this hook
  the per-IP cap covers only the first request of a session.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias TaskyWeb.Plugs.RateLimit

  @bucket :guest
  @limit 300
  @window_ms 60_000

  def on_mount(:default, _params, session, socket) do
    case RateLimit.check(@bucket, client_ip(session, socket), @limit, @window_ms) do
      :ok ->
        {:cont, socket}

      :rate_limited ->
        {:halt,
         socket
         |> assign(:page_title, "Zu viele Anfragen")
         |> redirect(to: "/")}
    end
  end

  # The plug stashes the resolved client IP in the session on the HTTP request
  # that opened this LiveView. `peer_data` is only a fallback for a socket that
  # somehow never went through the pipeline — behind Fly's proxy it resolves to
  # the proxy, so it buckets every guest together and must not be the norm.
  defp client_ip(session, socket) do
    case session do
      %{"client_ip" => ip} when is_binary(ip) ->
        ip

      _ ->
        case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
          %{address: address} -> address |> :inet.ntoa() |> to_string()
          _ -> "unknown"
        end
    end
  end
end
