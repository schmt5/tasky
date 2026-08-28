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

  ## Why the file stays unencrypted

  `pswd` encryption would make SEB prompt the participant for the settings
  password — which therefore has to be *given* to them, so they can decrypt the
  file anyway. Zero gain, one more thing to go wrong on exam day. `pkhs`
  (key-encrypted, X.509) is the only variant with real value, and it needs a
  PKCS#12 identity pre-deployed into every exam machine's keychain; that is the
  upgrade path once the school has a managed lab image, not something to
  attempt for the next exam.

  So the file is public by construction, and the fix is to **stop needing it to
  be secret**: the quit and admin passwords are long random values
  (`Tasky.Exams.generate_quit_password/0`, `generate_admin_password/0`), and
  the wrong-browser guard is the Config Key header check
  (`Tasky.Exams.SebConfigKey`, enforced by `TaskyWeb.SebGuard`).

  ## Config Key coupling

  `settings/1` is public because `config_key/1` must hash *exactly* the map
  that `generate/1` serializes. Never build the settings anywhere else, and
  never add a key without reading the verification caveats in
  `Tasky.Exams.SebConfigKey`: changing any setting changes the Config Key and
  instantly invalidates every `.seb` file already downloaded, so it must never
  happen mid-session.
  """

  alias Tasky.Exams.SebConfigKey

  @typedoc """
  Options for `settings/1`, `generate/1` and `config_key/1`.

    * `:start_url` (required) – the URL SEB navigates to.
    * `:quit_url` (required) – the URL that makes SEB quit.
    * `:quit_password` – plain text; SHA-256 hashed into the config. When `nil`
      or `""`, `ignoreQuitPassword` is set instead.
    * `:admin_password` – plain text; gates SEB's own preferences and
      config-inspection windows. Without it a participant can inspect and alter
      the configuration.
    * `:allow_files?` – whether the exam actually hands out or takes in files.
      Defaults to `false`, which keeps downloads and uploads blocked. Only pass
      `true` for an exam with attachments or upload answer fields: an exam that
      is pure text input is tighter without them.
    * `:allowed_origins` – extra origins SEB may load from, beyond the app's
      own. Pass `TaskyWeb.ContentSecurityPolicy.storage_origins/0` so the URL
      filter and the CSP cannot diverge.
  """
  @type opts :: keyword()

  @doc """
  The settings map that goes into the `.seb` file.

  Public so `config_key/1` and the tests hash the same map the file contains.
  """
  @spec settings(opts()) :: map()
  def settings(opts) do
    start_url = Keyword.fetch!(opts, :start_url)
    quit_url = Keyword.fetch!(opts, :quit_url)
    quit_password = Keyword.get(opts, :quit_password)
    admin_password = Keyword.get(opts, :admin_password)
    allow_files? = Keyword.get(opts, :allow_files?, false)
    allowed_origins = Keyword.get(opts, :allowed_origins, [])

    %{}
    |> Map.merge(core(start_url, quit_url, quit_password, admin_password))
    |> Map.merge(integrity())
    |> Map.merge(reload())
    |> Map.merge(files(allow_files?))
    |> Map.merge(url_filter(start_url, allowed_origins))
    |> Map.merge(display())
    |> Map.merge(macos())
    |> Map.merge(windows())
  end

  @doc """
  Generates a `.seb` config file binary for the given options.

  ## Examples

      iex> seb = Tasky.Exams.SebConfig.generate(
      ...>   start_url: "https://example.com/exam/123",
      ...>   quit_url: "https://example.com/exam/123/done"
      ...> )
      iex> is_binary(seb)
      true
  """
  @spec generate(opts()) :: binary()
  def generate(opts) do
    opts
    |> settings()
    |> settings_to_plist_xml()
    |> :zlib.gzip()
    |> then(fn compressed_xml -> "plnd" <> compressed_xml end)
    |> :zlib.gzip()
  end

  @doc """
  The SEB Config Key for the same options `generate/1` would serialize.

  This is what the `X-SafeExamBrowser-ConfigKeyHash` header is checked against.
  """
  @spec config_key(opts()) :: String.t()
  def config_key(opts), do: opts |> settings() |> SebConfigKey.derive()

  ## Settings groups

  defp core(start_url, quit_url, quit_password, admin_password) do
    %{
      "startURL" => start_url,
      "quitURL" => quit_url,
      # Without this SEB sends no X-SafeExamBrowser-* headers at all, and the
      # server has nothing to check.
      "sendBrowserExamKey" => true,
      "sebConfigPurpose" => 0,
      "allowQuit" => true,
      "hashedQuitPassword" => sha256_hex(quit_password),
      "ignoreQuitPassword" => blank?(quit_password),
      # Confirming the quit URL would leave the participant on a dialog after
      # they hand in; the quit URL is only reached deliberately.
      "quitURLConfirm" => false,
      "hashedAdminPassword" => sha256_hex(admin_password),
      "browserViewMode" => 0,
      "mainBrowserWindowWidth" => "100%",
      "mainBrowserWindowHeight" => "100%",
      "mainBrowserWindowPositioning" => 1,
      "showTaskBar" => true,
      "showTime" => true,
      "enableZoomPage" => true,
      "enableZoomText" => true,
      "blockPopUpWindows" => true
    }
  end

  defp integrity do
    %{
      # The admin password is what actually gates these on Windows; on macOS
      # the preferences window is refused outright.
      "allowPreferencesWindow" => false,
      "allowReconfiguration" => false,
      "examSessionReconfigureAllow" => false,
      "downloadAndOpenSebConfig" => false,
      "allowUserSwitching" => false,
      "allowVirtualMachine" => false,
      "allowSpellCheck" => false,
      "allowDictionaryLookup" => false,
      "enablePrivateClipboard" => true,
      "allowBrowsingBackForward" => false,
      "enableLogging" => true
    }
  end

  defp reload do
    # LiveView reconnects and the occasional manual reload have to work, or a
    # participant whose socket drops is stuck. The reload warnings are off
    # because the answer document is autosaved continuously anyway.
    %{
      "showReloadButton" => true,
      "browserWindowAllowReload" => true,
      "showReloadWarning" => false,
      "newBrowserWindowAllowReload" => true,
      "newBrowserWindowShowReloadWarning" => false
    }
  end

  # An exam that neither hands out attachments nor takes in file answers is
  # tighter with downloads and uploads blocked outright, so that is the
  # default. Derived from the exam rather than hardcoded, because a blocked
  # download is indistinguishable from a broken one for the participant.
  defp files(false) do
    %{
      "allowDownUploads" => false,
      "openDownloads" => false
    }
  end

  defp files(true) do
    %{
      "allowDownUploads" => true,
      "openDownloads" => false,
      # 0 = pick a file manually with the file requester. The other policies
      # restrict uploads to a previously downloaded file, which would make it
      # impossible to hand in the participant's own work.
      "chooseFileToUploadPolicy" => 0,
      "downloadDirectoryOSX" => "~/Downloads",
      "downloadDirectoryWin" => ""
    }
  end

  defp url_filter(start_url, allowed_origins) do
    origins = [origin(start_url) | allowed_origins] |> Enum.uniq() |> Enum.reject(&is_nil/1)

    %{
      "URLFilterEnable" => true,
      # The content filter checks every subresource against the same rules and
      # breaks asset loading; the request filter is what we actually want.
      "URLFilterEnableContentFilter" => false,
      "URLFilterRules" =>
        Enum.map(origins, fn origin ->
          %{
            # 1 = allow.
            "action" => 1,
            "active" => true,
            "expression" => origin <> "/*",
            "regex" => false
          }
        end)
    }
  end

  defp display do
    %{
      "allowedDisplaysMaxNumber" => 1,
      "allowedDisplaysAllowMirroring" => false,
      "allowDisplayMirroring" => false,
      "allowScreenSharing" => false,
      "allowVideoCapture" => false,
      "allowAudioCapture" => false,
      "enablePrintScreen" => false
    }
  end

  defp macos do
    %{
      "allowSwitchToApplications" => false,
      "enableAppSwitcherCheck" => true,
      "forceAppFolderInstall" => true,
      "allowSiri" => false,
      "allowDictation" => false
    }
  end

  defp windows do
    keyboard =
      Map.new(
        ~w(enableAltTab enableAltEsc enableCtrlEsc enableAltF4 enableStartMenu enableRightMouse) ++
          Enum.map(1..12, &"enableF#{&1}"),
        &{&1, false}
      )

    inside_seb =
      Map.new(
        ~w(SwitchUser LockThisComputer ChangeAPassword StartTaskManager LogOff ShutDown
           EaseOfAccess VmWareClientShade),
        &{"insideSebEnable" <> &1, false}
      )

    Map.merge(keyboard, inside_seb)
    |> Map.merge(%{
      "createNewDesktop" => true,
      # Killing the shell makes recovery from a crashed SEB much harder for a
      # teacher standing at the machine, and createNewDesktop already isolates.
      "killExplorerShell" => false,
      "enableEsc" => true,
      "enableWindowsUpdate" => false,
      "enableChromeNotifications" => false
    })
  end

  ## Helpers

  defp blank?(value), do: value in [nil, ""]

  defp sha256_hex(value) do
    if blank?(value),
      do: "",
      else: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  end

  defp origin(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host} = uri} when is_binary(scheme) and is_binary(host) ->
        port = if uri.port in [nil, 80, 443], do: "", else: ":#{uri.port}"
        "#{scheme}://#{host}#{port}"

      _ ->
        nil
    end
  end

  @doc false
  @spec settings_to_plist_xml(map()) :: binary()
  def settings_to_plist_xml(settings) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    #{plist_value(settings, "")}
    </plist>
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  defp plist_value(map, indent) when is_map(map) and not is_struct(map) do
    inner = indent <> "  "

    entries =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map_join("\n", fn {key, value} ->
        "#{inner}<key>#{escape_xml(to_string(key))}</key>\n" <>
          "#{inner}#{plist_value(value, inner)}"
      end)

    case entries do
      "" -> "<dict/>"
      _ -> "<dict>\n#{entries}\n#{indent}</dict>"
    end
  end

  defp plist_value([], _indent), do: "<array/>"

  defp plist_value(list, indent) when is_list(list) do
    inner = indent <> "  "

    entries =
      Enum.map_join(list, "\n", fn value -> "#{inner}#{plist_value(value, inner)}" end)

    "<array>\n#{entries}\n#{indent}</array>"
  end

  defp plist_value(value, _indent) when is_binary(value),
    do: "<string>#{escape_xml(value)}</string>"

  defp plist_value(true, _indent), do: "<true/>"
  defp plist_value(false, _indent), do: "<false/>"
  defp plist_value(value, _indent) when is_integer(value), do: "<integer>#{value}</integer>"

  defp plist_value({:data, bin}, _indent) when is_binary(bin),
    do: "<data>#{Base.encode64(bin)}</data>"

  defp escape_xml(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
