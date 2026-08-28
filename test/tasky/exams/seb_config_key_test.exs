defmodule Tasky.Exams.SebConfigKeyTest do
  @moduledoc """
  The canonical serialization is the load-bearing part of the SEB Config Key:
  get one escaping or ordering rule wrong and every hash silently disagrees
  with what SEB computes — which, under `enforce`, locks a whole class out of
  their exam. So the rules are pinned individually *and* as a golden byte
  string.
  """
  use ExUnit.Case, async: true

  alias Tasky.Exams.SebConfigKey

  describe "canonical_json/1" do
    test "sorts dictionary keys case-insensitively and emits no whitespace" do
      assert SebConfigKey.canonical_json(%{"b" => 1, "A" => 2, "a" => 3}) ==
               ~s({"A":2,"a":3,"b":1})
    end

    test "sorts nested dictionaries too" do
      assert SebConfigKey.canonical_json(%{"outer" => %{"z" => 1, "a" => 2}}) ==
               ~s({"outer":{"a":2,"z":1}})
    end

    test "renders arrays of dictionaries in order" do
      # This is the shape URLFilterRules takes.
      value = %{"rules" => [%{"b" => true, "a" => 1}, %{"c" => "x"}]}

      assert SebConfigKey.canonical_json(value) ==
               ~s({"rules":[{"a":1,"b":true},{"c":"x"}]})
    end

    test "does not escape forward slashes" do
      # Load-bearing, not theoretical: every settings map carries URLs.
      assert SebConfigKey.canonical_json(%{"u" => "https://a.test/x/y"}) ==
               ~s({"u":"https://a.test/x/y"})
    end

    test "emits non-ASCII as raw UTF-8 rather than \\u escapes" do
      json = SebConfigKey.canonical_json(%{"n" => "Prüfung"})
      assert json == ~s({"n":"Prüfung"})
      assert String.valid?(json)
      refute json =~ "\\u"
    end

    test "escapes quotes, backslashes and control characters" do
      assert SebConfigKey.canonical_json(%{"s" => ~s(a"b\\c)}) == ~s({"s":"a\\"b\\\\c"})
      assert SebConfigKey.canonical_json(%{"s" => "a\nb"}) == ~s({"s":"a\\nb"})
      assert SebConfigKey.canonical_json(%{"s" => <<1>>}) == ~s({"s":"\\u0001"})
    end

    test "keeps empty dictionaries and arrays" do
      assert SebConfigKey.canonical_json(%{"d" => %{}, "a" => []}) == ~s({"a":[],"d":{}})
    end

    test "renders booleans and integers bare, and data as base64" do
      assert SebConfigKey.canonical_json(%{"t" => true, "f" => false, "i" => 7}) ==
               ~s({"f":false,"i":7,"t":true})

      assert SebConfigKey.canonical_json(%{"d" => {:data, "hi"}}) == ~s({"d":"aGk="})
    end

    test "refuses floats instead of guessing a format" do
      # Float formatting is the classic canonical-JSON divergence across
      # languages. A settings map that grows one must fail here, loudly, rather
      # than produce a key that quietly disagrees with SEB's.
      assert_raise ArgumentError, ~r/must not contain floats/, fn ->
        SebConfigKey.canonical_json(%{"x" => 1.5})
      end
    end
  end

  describe "derive/1" do
    test "drops originatorVersion before hashing" do
      with_version = %{"startURL" => "https://a.test", "originatorVersion" => "SEB_Win_3.5.0"}
      without = %{"startURL" => "https://a.test"}

      assert SebConfigKey.derive(with_version) == SebConfigKey.derive(without)
    end

    test "golden: a fixed settings map hashes to a fixed key" do
      # Pins the serialization end to end. If this fails, the canonical JSON
      # changed — which means every `.seb` file already in the wild now has a
      # different Config Key than the server expects.
      settings = %{
        "allowQuit" => true,
        "sebConfigPurpose" => 0,
        "startURL" => "https://tasky.test/guest/exam/abc",
        "URLFilterRules" => [
          %{"action" => 1, "active" => true, "expression" => "https://tasky.test/*"}
        ]
      }

      # Note the order: sorting is case-insensitive, so "URLFilterRules" lands
      # after "startURL" (urlfilterrules > starturl), not first as a
      # case-sensitive sort would put it.
      expected_json =
        ~s({"allowQuit":true,"sebConfigPurpose":0,) <>
          ~s("startURL":"https://tasky.test/guest/exam/abc",) <>
          ~s("URLFilterRules":[{"action":1,"active":true,"expression":"https://tasky.test/*"}]})

      assert SebConfigKey.canonical_json(settings) == expected_json

      assert SebConfigKey.derive(settings) ==
               :crypto.hash(:sha256, expected_json) |> Base.encode16(case: :lower)
    end

    test "any settings change produces a different key" do
      a = SebConfigKey.derive(%{"startURL" => "https://a.test/1"})
      b = SebConfigKey.derive(%{"startURL" => "https://a.test/2"})

      refute a == b
    end
  end

  describe "request_hash/2" do
    test "without a URL the Config Key itself is the expected value" do
      assert SebConfigKey.request_hash(nil, "ABCD") == "abcd"
    end

    test "with a URL it is SHA-256 over url <> key" do
      url = "https://tasky.test/guest/exam/abc"
      key = String.duplicate("a", 64)

      assert SebConfigKey.request_hash(url, key) ==
               :crypto.hash(:sha256, url <> key) |> Base.encode16(case: :lower)
    end
  end

  describe "matches?/2" do
    test "is case-insensitive and tolerates surrounding whitespace" do
      assert SebConfigKey.matches?("  ABC123  ", ["abc123"])
    end

    test "accepts any candidate, which is what the operator override rides on" do
      assert SebConfigKey.matches?("bbb", ["aaa", "bbb"])
      refute SebConfigKey.matches?("ccc", ["aaa", "bbb"])
    end

    test "an absent or empty candidate list never matches" do
      refute SebConfigKey.matches?("aaa", [])
      refute SebConfigKey.matches?(nil, ["aaa"])
    end
  end

  describe "against a real Safe Exam Browser" do
    @tag :skip
    test "our derivation equals the Config Key SEB itself reports" do
      # THE test. Everything above pins our own rules to themselves; only this
      # one proves they are SEB's rules.
      #
      # To fill it in: set the exam to `seb_enforcement: "observe"`, start the
      # real `.seb` on an exam-room machine, open SEB's preferences with the
      # admin password, and copy the Config Key it displays. Paste that config's
      # settings map and the reported key below, drop the @tag :skip, and only
      # then switch any exam to "enforce".
      #
      # Two questions this settles that nothing else can: whether SEB hashes
      # only the keys present in the file or fills in its own defaults first,
      # and whether it drops keys it does not recognise.
      settings = %{}
      reported_by_seb = ""

      assert SebConfigKey.derive(settings) == reported_by_seb
    end
  end
end
