defmodule TaskyWeb.Plugs.RateLimit do
  @moduledoc """
  Minimal fixed-window per-IP rate limiter for the guest exam-token routes —
  the tokens are short strings, so unlimited probing would make them
  brute-forceable. The limit is generous enough for a whole class behind one
  school NAT while making token guessing (32^6 combinations) hopeless.

  State lives in a public ETS table created by `Tasky.Application`; entries
  from past windows are pruned opportunistically.
  """

  import Plug.Conn

  @table :tasky_rate_limit

  @doc "Creates the shared ETS table (called once from the application start)."
  def create_table do
    :ets.new(@table, [:named_table, :public, write_concurrency: true])
  end

  def init(opts) do
    %{
      bucket: Keyword.fetch!(opts, :bucket),
      limit: Keyword.get(opts, :limit, 300),
      window_ms: Keyword.get(opts, :window_ms, 60_000)
    }
  end

  def call(conn, %{bucket: bucket, limit: limit, window_ms: window_ms}) do
    window = div(System.system_time(:millisecond), window_ms)
    key = {bucket, client_ip(conn), window}
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})

    maybe_prune(bucket, window)

    if count > limit do
      conn
      |> put_status(:too_many_requests)
      |> Phoenix.Controller.text("Zu viele Anfragen – bitte kurz warten.")
      |> halt()
    else
      conn
    end
  end

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
