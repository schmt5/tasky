defmodule TaskyWeb.ExamIndexLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    %{conn: log_in_user(conn, teacher), scope: scope}
  end

  describe "status filter" do
    test "shows only exams in the chosen phase", %{conn: conn, scope: scope} do
      draft = exam_fixture(scope: scope)
      finished = exam_fixture(scope: scope, status: "finished")

      {:ok, view, _html} = live(conn, ~p"/exams?status=ready_to_return")

      assert has_element?(view, "#status-filter option[value=ready_to_return][selected]")
      assert has_element?(view, "#exams-#{finished.id}")
      refute has_element?(view, "#exams-#{draft.id}")
    end

    test "switches the filter through the URL", %{conn: conn, scope: scope} do
      draft = exam_fixture(scope: scope)
      finished = exam_fixture(scope: scope, status: "finished")

      {:ok, view, _html} = live(conn, ~p"/exams")
      view |> form("#status-filter", filter: %{status: "draft"}) |> render_change()

      assert_patch(view, ~p"/exams?status=draft")
      assert has_element?(view, "#exams-#{draft.id}")
      refute has_element?(view, "#exams-#{finished.id}")
    end

    test "counts the exams of each phase", %{conn: conn, scope: scope} do
      exam_fixture(scope: scope)
      exam_fixture(scope: scope)
      exam_fixture(scope: scope, status: "finished")

      {:ok, view, _html} = live(conn, ~p"/exams")

      assert view |> element("#status-filter option[value=draft]") |> render() =~ "(2)"
      assert view |> element("#status-filter option[value=ready_to_return]") |> render() =~ "(1)"
      assert view |> element("#status-filter option[value=all]") |> render() =~ "(3)"
    end

    test "separates exams still being corrected from returned ones", %{conn: conn, scope: scope} do
      content = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "heading",
            "attrs" => %{"level" => 3, "partId" => "p1"},
            "content" => [%{"type" => "text", "text" => "Frage"}]
          }
        ]
      }

      correcting = exam_fixture(scope: scope, status: "running", attrs: %{content: content})
      exam_submission_fixture(correcting)
      {:ok, correcting} = Tasky.Exams.update_exam_status(scope, correcting, "finished")

      returned =
        exam_fixture(scope: scope, status: "finished")
        |> Tasky.Exams.Exam.return_changeset(%{returned_at: DateTime.utc_now(:second)})
        |> Tasky.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/exams?status=correcting")
      assert has_element?(view, "#exams-#{correcting.id}")
      refute has_element?(view, "#exams-#{returned.id}")

      {:ok, view, _html} = live(conn, ~p"/exams?status=returned")
      assert has_element?(view, "#exams-#{returned.id}")
      refute has_element?(view, "#exams-#{correcting.id}")
    end

    test "falls back to all for an unknown status", %{conn: conn, scope: scope} do
      draft = exam_fixture(scope: scope)

      {:ok, view, _html} = live(conn, ~p"/exams?status=finished")

      assert has_element?(view, "#status-filter option[value=all][selected]")
      assert has_element?(view, "#exams-#{draft.id}")
    end

    test "shows an empty state when no exam matches", %{conn: conn, scope: scope} do
      exam_fixture(scope: scope)

      {:ok, view, _html} = live(conn, ~p"/exams?status=running")

      assert has_element?(view, "#exams-empty")
    end
  end

  describe "archiving" do
    test "only finished exams offer the archive button", %{conn: conn, scope: scope} do
      draft = exam_fixture(scope: scope)
      finished = exam_fixture(scope: scope, status: "finished")

      {:ok, view, _html} = live(conn, ~p"/exams")

      assert has_element?(view, "#archive-#{finished.id}")
      refute has_element?(view, "#archive-#{draft.id}")
    end

    test "moves a finished exam from the list to the archive", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope, status: "finished")

      {:ok, view, _html} = live(conn, ~p"/exams")
      view |> element("#archive-#{exam.id}") |> render_click()

      refute has_element?(view, "#exams-#{exam.id}")

      {:ok, archive, _html} = live(conn, ~p"/exams/archive")
      assert has_element?(archive, "#archived-exams #exams-#{exam.id}")
    end

    test "leaves archived exams out of the list", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope, status: "finished", archived: true)

      {:ok, view, _html} = live(conn, ~p"/exams")

      refute has_element?(view, "#exams-#{exam.id}")
      assert has_element?(view, "#archive-link")
    end
  end

  describe "row actions" do
    test "every exam offers view and duplicate", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope)

      {:ok, view, _html} = live(conn, ~p"/exams")

      assert has_element?(view, ~s(#view-#{exam.id}[href="/exams/#{exam.id}"]))
      assert has_element?(view, "#duplicate-#{exam.id}")
    end

    test "duplicating opens the rename dialog for the copy", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope, attrs: %{name: "Algebra"})

      {:ok, view, _html} = live(conn, ~p"/exams")
      view |> element("#duplicate-#{exam.id}") |> render_click()

      copy = Enum.find(Tasky.Exams.list_exams(scope), &(&1.id != exam.id))
      assert has_element?(view, "#rename-exam-form-#{copy.id}")
      assert has_element?(view, "#exams-#{copy.id}")

      view
      |> form("#rename-exam-form-#{copy.id}", exam: %{name: "Algebra B"})
      |> render_submit()

      refute has_element?(view, "#rename-exam-modal")
      assert Tasky.Exams.get_exam!(scope, copy.id).name == "Algebra B"
      assert Tasky.Exams.get_exam!(scope, exam.id).name == "Algebra"
    end

    test "keeping the name leaves the copy in the list", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope)

      {:ok, view, _html} = live(conn, ~p"/exams")
      view |> element("#duplicate-#{exam.id}") |> render_click()
      view |> element("#rename-exam-cancel") |> render_click()

      refute has_element?(view, "#rename-exam-modal")
      assert length(Tasky.Exams.list_exams(scope)) == 2
    end

    test "an empty name is refused", %{conn: conn, scope: scope} do
      exam = exam_fixture(scope: scope)

      {:ok, view, _html} = live(conn, ~p"/exams")
      view |> element("#duplicate-#{exam.id}") |> render_click()
      copy = Enum.find(Tasky.Exams.list_exams(scope), &(&1.id != exam.id))

      view
      |> form("#rename-exam-form-#{copy.id}", exam: %{name: ""})
      |> render_submit()

      assert has_element?(view, "#rename-exam-modal")
    end
  end
end
