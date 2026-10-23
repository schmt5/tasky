defmodule TaskyWeb.ExamShowLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  defp show(conn, opts) do
    teacher = user_fixture(%{role: "teacher"})
    exam = exam_fixture([scope: user_scope_fixture(teacher)] ++ opts)
    {:ok, _view, html} = conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}")
    html
  end

  describe "status description for an open session" do
    test "assigned mode points at the dashboard, not the enrolment link", %{conn: conn} do
      html = show(conn, status: "open", participation_mode: "assigned")

      assert html =~ "Die Durchführung ist offen."
      assert html =~ "zugewiesenen Lernenden sehen die Prüfung auf ihrem Dashboard"
      refute html =~ "Einschreibelink einschreiben"
    end

    test "anonymous mode points at the enrolment link", %{conn: conn} do
      html = show(conn, status: "open", participation_mode: "anonymous")

      assert html =~ "Die Durchführung ist offen."
      assert html =~ "Einschreibelink einschreiben"
      refute html =~ "auf ihrem Dashboard"
    end
  end

  describe "archiving" do
    setup %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      %{conn: log_in_user(conn, teacher), scope: user_scope_fixture(teacher)}
    end

    test "archives a draft and restores it", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope)

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}")
      refute has_element?(view, "#archived-notice")

      view |> element("#archive-exam") |> render_click()
      assert has_element?(view, "#archived-notice")
      assert Tasky.Exams.archived?(Tasky.Exams.get_exam!(scope, exam.id))

      view |> element("#archived-notice-unarchive") |> render_click()
      refute has_element?(view, "#archived-notice")
      refute Tasky.Exams.archived?(Tasky.Exams.get_exam!(scope, exam.id))
    end

    test "asks before archiving a running session", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope, status: "running")

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}")

      assert has_element?(view, "#archive-exam[data-confirm]")
    end

    test "archives a finished exam without asking", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope, status: "finished")

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}")

      refute has_element?(view, "#archive-exam[data-confirm]")
    end
  end

  describe "renaming and duplicating" do
    setup %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      %{conn: log_in_user(conn, teacher), scope: user_scope_fixture(teacher)}
    end

    test "renames the exam in a dialog", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope, attrs: %{name: "Alt"})

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}")
      view |> element("#rename-exam") |> render_click()

      view
      |> form("#rename-exam-form-#{exam.id}", exam: %{name: "Neu"})
      |> render_submit()

      refute has_element?(view, "#rename-exam-modal")
      assert Tasky.Exams.get_exam!(scope, exam.id).name == "Neu"
    end

    test "names the copy, then opens it", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope, attrs: %{name: "Original"})

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}")
      view |> element("#duplicate-exam") |> render_click()

      copy = Enum.find(Tasky.Exams.list_exams(scope), &(&1.id != exam.id))

      {:ok, _copy_view, html} =
        view
        |> form("#rename-exam-form-#{copy.id}", exam: %{name: "Zweitversion"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/exams/#{copy}")

      assert html =~ "Zweitversion"
    end
  end

  describe "content" do
    setup %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      %{conn: log_in_user(conn, teacher), scope: user_scope_fixture(teacher)}
    end

    test "shows the whole exam read-only with an edit action", %{conn: conn, scope: scope} do
      content = %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hallo"}]}
        ]
      }

      exam = exam_fixture(scope: scope, attrs: %{content: content})

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}")

      assert has_element?(
               view,
               ~s(#exam-content-viewer-#{exam.id}[phx-hook="ExamReadOnlyViewer"])
             )

      assert has_element?(view, ~s(#edit-exam-content[href="/exams/#{exam.id}/content"]))
      refute has_element?(view, "#exam-content-empty")
    end

    test "shows an empty state without content", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope)

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}")

      assert has_element?(view, "#exam-content-empty")
      refute has_element?(view, "#exam-content-viewer-#{exam.id}")
    end
  end
end
