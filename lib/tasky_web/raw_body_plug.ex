defmodule TaskyWeb.RawBodyPlug do
  @moduledoc """
  Caches the raw request body in conn.private before Plug.Parsers consumes it.

  This is required for webhook HMAC signature verification, which must be
  computed over the original raw bytes — not a re-serialized version of the
  parsed params.

  Usage in endpoint.ex:

      plug TaskyWeb.RawBodyPlug

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library(),
        body_reader: {TaskyWeb.RawBodyPlug, :read_body, []}

  Then retrieve the raw body in a controller or plug via:

      conn.private[:raw_body]
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts), do: conn

  @doc """
  Used as the `:body_reader` option for `Plug.Parsers`. Reads the full body,
  caches it as a binary in `conn.private[:raw_body]`, and returns it so
  `Plug.Parsers` can continue parsing as normal.
  """
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = put_private(conn, :raw_body, body)
        {:ok, body, conn}

      {:more, partial, conn} ->
        # Body exceeds the read chunk — accumulate and cache the full body.
        # This path is uncommon for typical webhook payloads but handled for safety.
        {status, full_body, conn} = read_remaining(conn, partial, opts)
        conn = put_private(conn, :raw_body, full_body)
        {status, full_body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_remaining(conn, acc, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, chunk, conn} ->
        {:ok, acc <> chunk, conn}

      {:more, chunk, conn} ->
        read_remaining(conn, acc <> chunk, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
