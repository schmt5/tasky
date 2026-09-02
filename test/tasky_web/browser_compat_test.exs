defmodule TaskyWeb.BrowserCompatTest do
  @moduledoc """
  Guards the two things that keep a too-old browser from producing a silent
  white page — the exact failure three participants hit in a graded SEB exam.

  Both are wiring, not logic, and wiring is what rots unnoticed: the layout tag
  and the `static_paths` entry live in different files from the asset they
  point at, and nothing else in the suite would notice either going missing.
  """
  use TaskyWeb.ConnCase, async: true

  describe "browser capability check" do
    test "is served as a static asset", %{conn: conn} do
      conn = get(conn, "/compat/browser-check.js")

      assert conn.status == 200
      assert conn.resp_body =~ "Dieser Browser ist zu alt"
    end

    test "is loaded as a classic script, before the module bundle", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert [compat_tag] = Regex.run(~r|<script[^>]*browser-check[^>]*>|, html)

      # A `type="module"` here would defeat the whole point: the engine this
      # warns about cannot parse a module and would skip the tag silently.
      refute compat_tag =~ "module"

      compat_at = :binary.match(html, "browser-check") |> elem(0)
      bundle_at = :binary.match(html, "/assets/js/app.js") |> elem(0)

      assert compat_at < bundle_at,
             "the check must load before the bundle it warns about"
    end

    test "contains no syntax the browsers it warns about cannot parse" do
      source = File.read!("priv/static/compat/browser-check.js")

      # A crude but effective backstop: ES6+ syntax in this file means an old
      # engine throws a SyntaxError instead of showing the warning. `npx esbuild
      # --target=es5` is the thorough check; this one runs in CI for free.
      refute source =~ ~r/\b(const|let|class)\s/
      refute source =~ "=>"
      refute source =~ "`"
    end
  end

  describe "self-hosted fonts" do
    @faces ~w(
      dm-sans-latin-wght-normal
      dm-sans-latin-wght-italic
      dm-sans-latin-ext-wght-normal
      dm-sans-latin-ext-wght-italic
      instrument-serif-latin-400-normal
      instrument-serif-latin-400-italic
      instrument-serif-latin-ext-400-normal
      instrument-serif-latin-ext-400-italic
    )

    test "every @font-face source is actually served", %{conn: conn} do
      for face <- @faces do
        conn = get(conn, "/fonts/#{face}.woff2")

        assert conn.status == 200, "missing font file: #{face}.woff2"
      end
    end

    test "no stylesheet URL points off-origin" do
      # `style-src 'self'` would block it, Gotenberg renders the print views
      # under the same CSP, and an exam room's firewall is the third way it
      # fails. The previous @import was silently dead for all three reasons.
      #
      # Matches `url(…)` rather than a bare hostname so the prose explaining
      # why we self-host does not trip its own guard.
      css = File.read!("assets/css/app.css")

      refute css =~ ~r|url\(\s*['"]?https?://|
    end
  end
end
