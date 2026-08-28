defmodule Tasky.Exams.SebConfigKey do
  @moduledoc """
  Derives the Safe Exam Browser **Config Key** from a settings map, and the
  per-request hash SEB sends in the `X-SafeExamBrowser-ConfigKeyHash` header.

  ## What this buys, and what it does not

  The `.seb` file is handed to every participant, and the Config Key is a pure
  function of the settings inside it — so every participant *can* compute it.
  Checking the header therefore raises the bar from "flip one string in a
  user-agent switcher" to "reimplement SEB's canonical hash and inject headers
  from an extension". For a supervised school exam that is a large and worthwhile
  jump. It is **not** a cryptographic boundary, and must never be described as
  one. The mechanisms that would be are the Browser Exam Key (hashes the SEB
  binary, so it cannot be derived from the config) and a key-encrypted (`pkhs`)
  config whose X.509 identity is pre-installed on the exam machines.

  ## Canonical serialization

  SEB specifies the Config Key as SHA-256 over a canonical JSON rendering of
  the settings dictionary:

    * `originatorVersion` is removed before hashing.
    * Dictionary keys are sorted case-insensitively, recursively.
    * No whitespace anywhere.
    * Strings use standard JSON escaping, but `/` is **not** escaped and
      non-ASCII is emitted as raw UTF-8 (PHP's
      `JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE`).
    * Booleans as `true`/`false`, integers bare.
    * Floats are refused outright — see `canonical_json/1`.

  > #### Verify against a real client before enforcing {: .warning}
  >
  > These rules are reconstructed from the SEB specification and the Moodle
  > `seb` plugin. Two questions can only be settled empirically, and both are
  > why `Tasky.Exams.Exam`'s `seb_enforcement` defaults to `"observe"`:
  >
  >   1. Does SEB hash only the keys present in the file, or the full settings
  >      set with its own defaults filled in? If the latter, a server-side
  >      derivation from our own map can never match and the accepted-key
  >      override is the only workable path.
  >   2. Are unknown or other-platform keys included in SEB's own hash? If they
  >      are dropped, every key we add that a given SEB build does not know
  >      breaks the derivation.
  >
  > `test/tasky/exams/seb_config_key_test.exs` carries a skipped fixture test
  > for a real config plus the Config Key a real SEB reported for it. Fill it
  > in and un-skip it before switching any exam to `"enforce"`.
  """

  @doc """
  The Config Key for a settings map: SHA-256 over `canonical_json/1`, hex,
  lowercase.
  """
  @spec derive(map()) :: String.t()
  def derive(settings) when is_map(settings) do
    settings
    |> Map.delete("originatorVersion")
    |> canonical_json()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  The canonical JSON rendering used for the hash.

  Public so the golden test can assert the exact byte string — an accidental
  change to the serialization must fail loudly in CI rather than silently lock
  a class out of their exam.
  """
  @spec canonical_json(term()) :: binary()
  def canonical_json(value), do: value |> encode() |> IO.iodata_to_binary()

  @doc """
  The value SEB sends in `X-SafeExamBrowser-ConfigKeyHash` for a given request:
  SHA-256 over the request URL concatenated with the Config Key.

  Pass `nil` as the URL for a build whose hash is not URL-salted; the plain
  Config Key is then the expected value.
  """
  @spec request_hash(String.t() | nil, String.t()) :: String.t()
  def request_hash(nil, key) when is_binary(key), do: String.downcase(key)

  def request_hash(url, key) when is_binary(url) and is_binary(key) do
    :crypto.hash(:sha256, url <> key) |> Base.encode16(case: :lower)
  end

  @doc """
  True when `observed` matches any candidate. Constant-time per candidate, and
  tolerant of the case SEB chose for its hex.
  """
  @spec matches?(String.t() | nil, [String.t()]) :: boolean()
  def matches?(observed, candidates) when is_binary(observed) and is_list(candidates) do
    normalized = observed |> String.trim() |> String.downcase()

    Enum.any?(candidates, fn candidate ->
      is_binary(candidate) and byte_size(candidate) == byte_size(normalized) and
        Plug.Crypto.secure_compare(candidate, normalized)
    end)
  end

  def matches?(_observed, _candidates), do: false

  ## Encoding

  defp encode(value) when is_map(value) do
    inner =
      value
      # Case-insensitive, with the exact key as tie-break so the order is
      # total. Our own key set has no case collisions; SEB's tie-break for keys
      # differing only in case is unknown, so do not rely on it.
      |> Enum.sort_by(fn {k, _v} -> {String.downcase(to_string(k)), to_string(k)} end)
      |> Enum.map(fn {k, v} -> [encode_string(to_string(k)), ?:, encode(v)] end)
      |> Enum.intersperse(?,)

    [?{, inner, ?}]
  end

  defp encode(value) when is_list(value) do
    [?[, value |> Enum.map(&encode/1) |> Enum.intersperse(?,), ?]]
  end

  defp encode(true), do: "true"
  defp encode(false), do: "false"
  defp encode(nil), do: "null"
  defp encode(value) when is_integer(value), do: Integer.to_string(value)
  defp encode(value) when is_binary(value), do: encode_string(value)
  defp encode(value) when is_atom(value), do: encode_string(Atom.to_string(value))
  defp encode({:data, bin}) when is_binary(bin), do: encode_string(Base.encode64(bin))

  # Deliberately no float clause. Float formatting is the classic
  # canonical-JSON divergence between languages, and a settings map that grows
  # one would produce a Config Key that silently disagrees with SEB's. Failing
  # here is the whole point.
  defp encode(value) when is_float(value) do
    raise ArgumentError,
          "SEB settings must not contain floats (got #{inspect(value)}) — " <>
            "float formatting is not portable across canonical-JSON implementations. " <>
            "Use an integer, or a string if SEB expects one."
  end

  # Standard JSON escaping, except `/` is left alone and non-ASCII is emitted
  # as raw UTF-8.
  defp encode_string(string) do
    [?", escape(string, []), ?"]
  end

  defp escape(<<>>, acc), do: Enum.reverse(acc)
  defp escape(<<?", rest::binary>>, acc), do: escape(rest, ["\\\"" | acc])
  defp escape(<<?\\, rest::binary>>, acc), do: escape(rest, ["\\\\" | acc])
  defp escape(<<?\n, rest::binary>>, acc), do: escape(rest, ["\\n" | acc])
  defp escape(<<?\r, rest::binary>>, acc), do: escape(rest, ["\\r" | acc])
  defp escape(<<?\t, rest::binary>>, acc), do: escape(rest, ["\\t" | acc])
  defp escape(<<?\b, rest::binary>>, acc), do: escape(rest, ["\\b" | acc])
  defp escape(<<?\f, rest::binary>>, acc), do: escape(rest, ["\\f" | acc])

  defp escape(<<char, rest::binary>>, acc) when char < 0x20 do
    escape(rest, [:io_lib.format("\\u~4.16.0b", [char]) | acc])
  end

  defp escape(<<char::utf8, rest::binary>>, acc), do: escape(rest, [<<char::utf8>> | acc])
end
