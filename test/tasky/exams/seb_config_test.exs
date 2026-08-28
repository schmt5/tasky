defmodule Tasky.Exams.SebConfigTest do
  @moduledoc """
  `SebConfig` had no tests at all — the plist pipeline, the XML escaping and
  the password hashing were entirely unverified, in a module whose output is
  the only thing standing between a participant and an unlocked browser.
  """
  use ExUnit.Case, async: true

  alias Tasky.Exams.SebConfig
  alias Tasky.Exams.SebConfigKey

  @opts [
    start_url: "https://tasky.test/guest/exam/tok123",
    quit_url: "https://tasky.test/guest/exam/tok123/seb-quit",
    quit_password: "PRZN-9XXN-79Z",
    admin_password: "SSMW6X9PVV54GAN8SDNLLNE69D"
  ]

  defp plist(opts) do
    <<"plnd", inner::binary>> = opts |> SebConfig.generate() |> :zlib.gunzip()
    :zlib.gunzip(inner)
  end

  describe "generate/1 file format" do
    test "is gzip( 'plnd' <> gzip(plist) ) and yields a well-formed document" do
      xml = plist(@opts)

      assert xml =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert xml =~ ~s(<plist version="1.0">)
      assert String.ends_with?(String.trim_trailing(xml), "</plist>")
    end

    test "escapes XML metacharacters in values" do
      xml = plist(Keyword.put(@opts, :start_url, "https://a.test/?a=1&b=2"))

      assert xml =~ "a=1&amp;b=2"
      refute xml =~ "a=1&b=2"
    end

    test "renders nested arrays of dictionaries" do
      xml = plist(@opts)

      assert xml =~ "<key>URLFilterRules</key>"
      assert xml =~ "<array>"
      assert xml =~ "<key>expression</key>"
      assert xml =~ "<string>https://tasky.test/*</string>"
    end
  end

  describe "settings/1 integrity" do
    test "asks SEB to send its exam key, without which nothing can be checked" do
      assert SebConfig.settings(@opts)["sendBrowserExamKey"] == true
    end

    test "hashes the quit password and gates the preferences window" do
      settings = SebConfig.settings(@opts)

      assert settings["hashedQuitPassword"] ==
               :crypto.hash(:sha256, "PRZN-9XXN-79Z") |> Base.encode16(case: :lower)

      assert settings["hashedAdminPassword"] ==
               :crypto.hash(:sha256, "SSMW6X9PVV54GAN8SDNLLNE69D") |> Base.encode16(case: :lower)

      assert settings["allowPreferencesWindow"] == false
      assert settings["allowReconfiguration"] == false
    end

    test "an absent quit password sets ignoreQuitPassword instead" do
      settings = SebConfig.settings(Keyword.put(@opts, :quit_password, nil))

      assert settings["hashedQuitPassword"] == ""
      assert settings["ignoreQuitPassword"] == true

      assert SebConfig.settings(@opts)["ignoreQuitPassword"] == false
    end

    test "blocks capture, mirroring and a second display" do
      settings = SebConfig.settings(@opts)

      for key <- ~w(enablePrintScreen allowScreenSharing allowVideoCapture allowAudioCapture
                    allowDisplayMirroring allowedDisplaysAllowMirroring) do
        assert settings[key] == false, "#{key} must be off"
      end

      assert settings["allowedDisplaysMaxNumber"] == 1
    end

    test "keeps reload working, because LiveView reconnects depend on it" do
      settings = SebConfig.settings(@opts)

      assert settings["browserWindowAllowReload"] == true
      assert settings["showReloadButton"] == true
      assert settings["showReloadWarning"] == false
    end

    test "locks the Windows escape hatches but leaves the shell alive" do
      settings = SebConfig.settings(@opts)

      for key <- ~w(enableAltTab enableAltF4 enableStartMenu enableF12
                    insideSebEnableStartTaskManager insideSebEnableLogOff) do
        assert settings[key] == false, "#{key} must be off"
      end

      # Killing the shell makes a crashed SEB much harder to recover from for a
      # teacher standing at the machine; createNewDesktop already isolates.
      assert settings["killExplorerShell"] == false
      assert settings["createNewDesktop"] == true
    end

    test "contains no floats, so the Config Key stays derivable" do
      # `SebConfigKey.canonical_json/1` raises on floats by design; this asserts
      # the settings map never grows one.
      assert is_binary(SebConfig.config_key(@opts))
    end
  end

  describe "settings/1 file handling" do
    test "keeps downloads and uploads blocked for a text-only exam" do
      settings = SebConfig.settings(@opts)

      assert settings["allowDownUploads"] == false
      refute Map.has_key?(settings, "chooseFileToUploadPolicy")
    end

    test "enables them, with a free file picker, for an exam that has files" do
      settings = SebConfig.settings(Keyword.put(@opts, :allow_files?, true))

      assert settings["allowDownUploads"] == true
      # 0 = pick any file. The other policies restrict uploads to a previously
      # downloaded file, which would make handing in own work impossible.
      assert settings["chooseFileToUploadPolicy"] == 0
    end
  end

  describe "settings/1 URL filter" do
    test "allows the app's own origin" do
      rules = SebConfig.settings(@opts)["URLFilterRules"]

      assert SebConfig.settings(@opts)["URLFilterEnable"] == true
      assert Enum.any?(rules, &(&1["expression"] == "https://tasky.test/*"))
      assert Enum.all?(rules, &(&1["action"] == 1 and &1["active"] == true))
    end

    test "allows the storage origin too, or content images silently break" do
      rules =
        @opts
        |> Keyword.put(:allowed_origins, ["https://bucket.r2.test"])
        |> SebConfig.settings()
        |> Map.fetch!("URLFilterRules")

      assert Enum.any?(rules, &(&1["expression"] == "https://bucket.r2.test/*"))
    end

    test "the content filter stays off, since it breaks asset loading" do
      assert SebConfig.settings(@opts)["URLFilterEnableContentFilter"] == false
    end
  end

  describe "config_key/1" do
    test "hashes exactly the map generate/1 serializes" do
      assert SebConfig.config_key(@opts) == SebConfigKey.derive(SebConfig.settings(@opts))
    end

    test "is per participant, because the start URL carries their token" do
      other = Keyword.put(@opts, :start_url, "https://tasky.test/guest/exam/tok999")

      refute SebConfig.config_key(@opts) == SebConfig.config_key(other)
    end

    test "changing any setting changes the key" do
      # The operational rule this pins: rotating a password or flipping a
      # setting invalidates every `.seb` file already downloaded, so it must
      # never happen mid-session.
      rotated = Keyword.put(@opts, :quit_password, "AAAA-BBBB-CCC")

      refute SebConfig.config_key(@opts) == SebConfig.config_key(rotated)
    end
  end
end
