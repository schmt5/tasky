defmodule TaskyWeb.Plugs.RateLimit do
  @moduledoc """
  Minimal fixed-window per-IP rate limiter for the guest exam-token routes —
  the tokens are short strings, so unlimited probing would make them
  brute-forceable. The limit is generous enough for a whole class behind one
  school NAT while making token guessing hopeless.

  State lives in a public ETS table created by `Tasky.Application`; entries
  from past windows are pruned opportunistically.

  A plug only covers HTTP requests. The guest LiveViews sit in one
  `live_session`, so a client that has loaded one guest page can `live_redirect`
  to arbitrary tokens over the already-open websocket without ever passing
  through a pipeline again. `TaskyWeb.GuestRateLimit` closes that path by
  calling `check/4` from an `on_mount` hook, which is why the counting logic
  lives in a plain function here rather than inside `call/2`.
  """

  import Plug.Conn

  @table :tasky_rate_limit

  @doc """
  Counts one hit for `ip` in `bucket` and returns `:ok` or `:rate_limited`.
  Shared by the plug and the LiveView `on_mount` hook so both spend the same
  budget.
  """
  def check(bucket, ip, limit, window_ms) do
    window = div(System.system_time(:millisecond), window_ms)
    key = {bucket, ip, window}
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})

    maybe_prune(bucket, window)

    if count > limit, do: :rate_limited, else: :ok
  end

  @doc "Creates the shared ETS table (called once from the application start)."
  def create_table do
    :ets.new(@table, [:named_table, :public, write_concurrency: true])
  end

  def init(opts) do
    %{
      bucket: Keyword.fetch!(opts, :bucket),
      limit: Keyword.get(opts, :limit, 300),
      window_ms: Keyword.get(opts, :window_ms, 60_000),
      stash_ip: Keyword.get(opts, :stash_ip, false)
    }
  end

  def call(conn, %{bucket: bucket, limit: limit, window_ms: window_ms} = opts) do
    ip = client_ip(conn)
    conn = maybe_stash_ip(conn, ip, opts.stash_ip)

    case check(bucket, ip, limit, window_ms) do
      :ok ->
        conn

      :rate_limited ->
        conn
        |> put_status(:too_many_requests)
        |> Phoenix.Controller.text("Zu viele Anfragen – bitte kurz warten.")
        |> halt()
    end
  end

  # Stashes the resolved client IP so the LiveView hook can spend the same
  # per-IP budget: a websocket carries no `fly-client-ip` header, and its peer
  # is the Fly proxy, which would otherwise put every guest in one bucket.
  # Opt-in, because only pipelines that also run `fetch_session` have a session
  # to write to — `:public_share` deliberately does not.
  defp maybe_stash_ip(conn, _ip, false), do: conn
  defp maybe_stash_ip(conn, ip, true), do: put_session(conn, :client_ip, ip)

  defp client_ip(conn) do
    # Fly terminates TLS and sets fly-client-ip; fall back to the peer.
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] -> ip
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  # Drop entries from earlier windows now and then so the table stays small.
  defp maybe_prune(bucket, current_window) do
    if :rand.uniform(100) == 1 do
      :ets.select_delete(@table, [
        {{{bucket, :_, :"$1"}, :_}, [{:<, :"$1", current_window}], [true]}
      ])
    end

    :ok
  end
end
