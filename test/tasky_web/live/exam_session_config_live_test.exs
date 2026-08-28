defmodule TaskyWeb.ExamSessionConfigLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp teacher_and_exam(opts \\ []) do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    exam = exam_fixture([scope: scope] ++ opts)
    %{teacher: teacher, scope: scope, exam: exam}
  end

  defp open_config(conn, teacher, exam) do
    conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/cockpit/config")
  end

  describe "draft" do
    test "offers the mode picker and no save button", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam()
      {:ok, _view, html} = open_config(conn, teacher, exam)

      assert html =~ "Durchführung eröffnen"
      assert html =~ "Lernende zuweisen"
      assert html =~ "Einschreibelink teilen"
      assert html =~ ~s(id="participation-mode-assigned")
      refute html =~ ~s(id="save-seb-config-btn")
    end

    test "preselects assigned mode and shows its description", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam()
      {:ok, _view, html} = open_config(conn, teacher, exam)

      assert html =~ "Zugewiesene Lernende sehen die Prüfung auf ihrem Dashboard"
      refute html =~ "Auch für Personen ohne Konto"
    end

    test "switching the mode swaps the description panel", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam()
      {:ok, view, _html} = open_config(conn, teacher, exam)

      html =
        view
        |> element(~s(input#participation-mode-anonymous))
        |> render_click()

      assert html =~ "Auch für Personen ohne Konto"
      refute html =~ "Zugewiesene Lernende sehen die Prüfung auf ihrem Dashboard"
    end

    test "opening in assigned mode leaves the enrollment token unset", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam()
      {:ok, view, _html} = open_config(conn, teacher, exam)

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> form("#seb-config-form") |> render_submit()

      assert to == "/exams/#{exam.id}/cockpit"

      reloaded = Exams.get_exam!(user_scope_fixture(teacher), exam.id)
      assert reloaded.status == "open"
      assert reloaded.participation_mode == "assigned"
      refute reloaded.enrollment_token
    end

    test "opening in anonymous mode mints an enrollment token", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam()
      {:ok, view, _html} = open_config(conn, teacher, exam)

      view |> element(~s(input#participation-mode-anonymous)) |> render_click()
      view |> form("#seb-config-form") |> render_submit()

      reloaded = Exams.get_exam!(user_scope_fixture(teacher), exam.id)
      assert reloaded.participation_mode == "anonymous"
      assert reloaded.enrollment_token
    end

    # The SEB form only persists on its own submit, so opening has to save the
    # pending params first — otherwise the setting is silently lost.
    test "a pending SEB toggle survives opening the session", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam()
      {:ok, view, _html} = open_config(conn, teacher, exam)

      view
      |> form("#seb-config-form", config: %{seb_enabled: "true"})
      |> render_submit()

      reloaded = Exams.get_exam!(user_scope_fixture(teacher), exam.id)
      assert reloaded.status == "open"
      assert reloaded.seb_enabled
      assert reloaded.seb_quit_password
    end
  end

  describe "after opening" do
    test "the mode is read-only and SEB stays editable", %{conn: conn} do
      %{teacher: teacher, exam: exam} =
        teacher_and_exam(status: "open", participation_mode: "assigned")

      {:ok, _view, html} = open_config(conn, teacher, exam)

      refute html =~ ~s(name="participation_mode")
      assert html =~ "Nach dem Eröffnen nicht mehr änderbar"
      assert html =~ "Zuweisung an Lernende"
      assert html =~ ~s(id="save-seb-config-btn")
      refute html =~ "Durchführung eröffnen"
    end

    test "a forged mode switch is ignored", %{conn: conn} do
      %{teacher: teacher, exam: exam} =
        teacher_and_exam(status: "open", participation_mode: "assigned")

      {:ok, view, _html} = open_config(conn, teacher, exam)
      render_hook_result = render_click(view, "select_mode", %{"mode" => "anonymous"})

      assert render_hook_result =~ "Zuweisung an Lernende"

      reloaded = Exams.get_exam!(user_scope_fixture(teacher), exam.id)
      assert reloaded.participation_mode == "assigned"
    end

    test "saving SEB does not touch the mode", %{conn: conn} do
      %{teacher: teacher, exam: exam} =
        teacher_and_exam(status: "open", participation_mode: "assigned")

      {:ok, view, _html} = open_config(conn, teacher, exam)

      view
      |> form("#seb-config-form", config: %{seb_enabled: "true"})
      |> render_submit()

      reloaded = Exams.get_exam!(user_scope_fixture(teacher), exam.id)
      assert reloaded.seb_enabled
      assert reloaded.participation_mode == "assigned"
      assert reloaded.status == "open"
    end
  end

  describe "SEB enforcement" do
    defp enable_seb(conn, teacher, exam) do
      {:ok, view, _html} = open_config(conn, teacher, exam)

      view
      |> form("#seb-config-form", config: %{seb_enabled: "true"})
      |> render_submit()

      {view, Exams.get_exam!(user_scope_fixture(teacher), exam.id)}
    end

    test "enabling SEB mints both passwords, and the admin one stays hidden", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam(status: "open")
      {view, reloaded} = enable_seb(conn, teacher, exam)

      # The quit password's hash travels inside the plain `.seb` file every
      # participant downloads, so it has to be long enough to survive that.
      assert reloaded.seb_quit_password =~ ~r/^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{3}$/
      assert reloaded.seb_admin_password =~ ~r/^[A-Z2-9]{26}$/

      html = render(view)
      assert html =~ reloaded.seb_quit_password
      refute html =~ reloaded.seb_admin_password

      assert view |> element("button", "Anzeigen") |> render_click() =~
               reloaded.seb_admin_password
    end

    test "defaults to observe, so turning SEB on cannot lock a class out", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam(status: "open")
      {_view, reloaded} = enable_seb(conn, teacher, exam)

      assert reloaded.seb_enforcement == "observe"
    end

    test "the mode can be switched, and only to a known value", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam(status: "open")
      {view, _reloaded} = enable_seb(conn, teacher, exam)

      render_click(view, "set_enforcement", %{"mode" => "enforce"})
      assert Exams.get_exam!(user_scope_fixture(teacher), exam.id).seb_enforcement == "enforce"

      # A forged value must not get through — the mode decides whether a
      # participant can reach the exam at all.
      render_click(view, "set_enforcement", %{"mode" => "anything"})
      assert Exams.get_exam!(user_scope_fixture(teacher), exam.id).seb_enforcement == "enforce"
    end

    test "the kill switch appears only under enforce, and suspends it", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam(status: "open")
      {view, _reloaded} = enable_seb(conn, teacher, exam)

      refute has_element?(view, "#seb-bypass-btn")

      render_click(view, "set_enforcement", %{"mode" => "enforce"})
      assert has_element?(view, "#seb-bypass-btn")

      view |> element("#seb-bypass-btn") |> render_click()

      reloaded = Exams.get_exam!(user_scope_fixture(teacher), exam.id)
      assert reloaded.seb_bypass_until
      assert DateTime.compare(reloaded.seb_bypass_until, DateTime.utc_now()) == :gt
      # Still "enforce" on the row — the bypass degrades it at read time, so it
      # comes back on its own when the window closes.
      assert reloaded.seb_enforcement == "enforce"
      assert TaskyWeb.SebGuard.mode(reloaded) == :observe
    end

    test "an observed hash can be accepted, which is the exam-day escape", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam(status: "open")
      {view, _reloaded} = enable_seb(conn, teacher, exam)

      observed = String.duplicate("ab", 32)
      send(view.pid, {:seb_observation, %{exam_token: "tok", observed: observed}})

      assert render(view) =~ String.slice(observed, 0, 24)

      render_click(view, "accept_config_key", %{"hash" => observed})

      reloaded = Exams.get_exam!(user_scope_fixture(teacher), exam.id)
      assert observed in reloaded.seb_accepted_config_keys

      # Once accepted it is no longer offered.
      refute render(view) =~ "Akzeptieren"
    end

    test "a value that is not a hash is refused", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam(status: "open")
      {view, _reloaded} = enable_seb(conn, teacher, exam)

      render_click(view, "accept_config_key", %{"hash" => "nope"})

      reloaded = Exams.get_exam!(user_scope_fixture(teacher), exam.id)
      assert reloaded.seb_accepted_config_keys == []
    end

    test "turning SEB off clears both passwords", %{conn: conn} do
      %{teacher: teacher, exam: exam} = teacher_and_exam(status: "open")
      {view, _reloaded} = enable_seb(conn, teacher, exam)

      view
      |> form("#seb-config-form", config: %{seb_enabled: "false"})
      |> render_submit()

      reloaded = Exams.get_exam!(user_scope_fixture(teacher), exam.id)
      refute reloaded.seb_enabled
      assert reloaded.seb_quit_password == nil
      assert reloaded.seb_admin_password == nil
    end
  end
end
