defmodule Tasky.Exams.SebConfig do
  @moduledoc """
  Generates Safe Exam Browser (SEB) configuration files.

  SEB is a lockdown browser used for secure online exams. This module produces
  plain (unencrypted) `.seb` config files that configure SEB to navigate to an
  exam URL with appropriate security settings.

  ## SEB file format (plain/unencrypted)

  1. Build an Apple plist XML document containing the SEB settings.
  2. Gzip-compress the XML.
  3. Prepend the 4-byte ASCII prefix `plnd` ("plain data").
  4. Gzip-compress the entire result (prefix + compressed XML).
  """

  @doc """
  Generates a `.seb` config file binary for the given exam URL and options.

  ## Options

    * `:start_url` (required) – The URL SEB should navigate to.
    * `:quit_url` (required) – The URL that triggers SEB to quit.
    * `:quit_password` (optional) – Plain-text quit password. Will be SHA-256
      hashed for the config. When `nil` or `""`, `ignoreQuitPassword` is set
      to `true`.

  ## Returns

  The `.seb` file as binary data (iodata-safe binary).

  ## Examples

      iex> seb_binary = Tasky.Exams.SebConfig.generate(
      ...>   start_url: "https://example.com/exam/123",
      ...>   quit_url: "https://example.com/exam/123/done"
      ...> )
      iex> is_binary(seb_binary)
      true
  """
  @spec generate(keyword()) :: binary()
  def generate(opts) do
    settings = build_settings(opts)

    settings
    |> settings_to_plist_xml()
    |> :zlib.gzip()
    |> then(fn compressed_xml -> "plnd" <> compressed_xml end)
    |> :zlib.gzip()
  end

  # -- Private helpers -------------------------------------------------------

  defp build_settings(opts) do
    start_url = Keyword.fetch!(opts, :start_url)
    quit_url = Keyword.fetch!(opts, :quit_url)
    quit_password = Keyword.get(opts, :quit_password)

    has_password? = quit_password not in [nil, ""]

    %{
      "startURL" => start_url,
      "quitURL" => quit_url,
      "hashedQuitPassword" => hash_quit_password(quit_password),
      "sebConfigPurpose" => 0,
      "allowQuit" => true,
      "ignoreQuitPassword" => not has_password?,
      "sendBrowserExamKey" => false,
      "allowBrowsingBackForward" => false,
      "enablePrintScreen" => false,
      "allowSpellCheck" => false,
      "allowDictionaryLookup" => false,
      "allowScreenSharing" => false,
      "allowVideoCapture" => false,
      "allowAudioCapture" => false,
      "allowDisplayMirroring" => false,
      "enablePrivateClipboard" => true,
      "showTaskBar" => true,
      "showReloadButton" => true,
      "showTime" => true,
      "enableZoomPage" => true,
      "enableZoomText" => true,
      "browserViewMode" => 0,
      "mainBrowserWindowWidth" => "100%",
      "mainBrowserWindowHeight" => "100%",
      "mainBrowserWindowPositioning" => 1,
      "blockPopUpWindows" => true,
      "URLFilterEnable" => false,
      "allowUserSwitching" => false,
      "allowVirtualMachine" => false,
      "createNewDesktop" => true,
      "killExplorerShell" => false
    }
  end

  defp hash_quit_password(nil), do: ""
  defp hash_quit_password(""), do: ""

  defp hash_quit_password(password) do
    :crypto.hash(:sha256, password) |> Base.encode16(case: :lower)
  end

  @doc false
  @spec settings_to_plist_xml(map()) :: binary()
  def settings_to_plist_xml(settings) do
    entries =
      settings
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map_join("\n", fn {key, value} ->
        "  <key>#{escape_xml(to_string(key))}</key>\n  #{plist_value(value)}"
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    #{entries}
    </dict>
    </plist>
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  defp plist_value(value) when is_binary(value), do: "<string>#{escape_xml(value)}</string>"
  defp plist_value(true), do: "<true/>"
  defp plist_value(false), do: "<false/>"
  defp plist_value(value) when is_integer(value), do: "<integer>#{value}</integer>"

  defp escape_xml(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
