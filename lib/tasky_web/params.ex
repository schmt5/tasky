defmodule TaskyWeb.Params do
  @moduledoc """
  Safe parsing of client-supplied params. Malformed input yields `nil`
  instead of crashing the LiveView process (`String.to_integer/1` raises on
  garbage, and anything the client sends can be garbage).
  """

  @doc "Parses an integer param; returns nil for anything malformed."
  def int(value) when is_integer(value), do: value

  def int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  def int(_), do: nil
end
