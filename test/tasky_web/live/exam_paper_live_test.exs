defmodule TaskyWeb.ExamPaperLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures

  alias Tasky.Exams
  alias Tasky.Exams.ExamPrintToken

  defp content_with_answer do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-1"},
          "content" => [%{"type" => "text", "text" => "Frage Eins"}]
        },
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => "a1"},
          "content" => [%{"type" => "paragraph"}]
        }
      ]
    }
  end

  defp create_exam(opts \\ []) do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    {:ok, exam} =
      Exams.create_exam(scope, %{
        name: "Test Prüfung",
        content: Keyword.get(opts, :content, content_with_answer()),
        answer_mode: Keyword.get(opts, :answer_mode, "answer_fields")
      })

    %{teacher: teacher, scope: scope, exam: exam}
  end

  defp sign(endpoint, user_id, exam_id) do
    ExamPrintToken.sign(endpoint, user_id, to_string(exam_id), %{})
  end

  describe "the teacher's paper view (cookie auth)" do
    test "renders the sheet with the editable paper island", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam()

      {:ok, _view, html} = live(log_in_user(conn, teacher), ~p"/exams/#{exam}/paper")

      assert html =~ "Papierversion"
      assert html =~ "Test Prüfung"
      assert html =~ ~s(id="exam-paper-#{exam.id}")
      assert html =~ ~s(phx-hook="ExamPaperEditor")
      # Blank header fields for name / class / date.
      assert html =~ "paper-field"
    end

    test "does not carry the Gotenberg readiness marker", %{conn: conn} do
      # There are no read-only viewers on this page to wait for, so the marker
      # would arm print_ready.js for nothing.
      %{teacher: teacher, exam: exam} = create_exam()

      {:ok, _view, html} = live(log_in_user(conn, teacher), ~p"/exams/#{exam}/paper")

      refute html =~ "print-ready-signal"
      refute html =~ ~s(phx-hook="ExamReadOnlyViewer")
    end

    test "offers the browser-print fallback even without Gotenberg", %{conn: conn} do
      # :test has no gotenberg_url, so @pdf_enabled is false here.
      %{teacher: teacher, exam: exam} = create_exam()

      {:ok, _view, html} = live(log_in_user(conn, teacher), ~p"/exams/#{exam}/paper")

      assert html =~ "PDF-Dienst nicht verfügbar"
      assert html =~ "drucken"
    end

    test "another teacher cannot open it", %{conn: conn} do
      %{exam: exam} = create_exam()
      other = user_fixture(%{role: "teacher"})

      assert_raise Ecto.NoResultsError, fn ->
        live(log_in_user(conn, other), ~p"/exams/#{exam}/paper")
      end
    end

    test "a learner is redirected", %{conn: conn} do
      %{exam: exam} = create_exam()
      student = user_fixture(%{role: "student"})

      assert {:error, {:redirect, _}} =
               live(log_in_user(conn, student), ~p"/exams/#{exam}/paper")
    end

    test "an anonymous visitor is redirected", %{conn: conn} do
      %{exam: exam} = create_exam()

      assert {:error, {:redirect, _}} = live(conn, ~p"/exams/#{exam}/paper")
    end
  end

  describe "the Gotenberg print view (token auth)" do
    test "a valid token renders the sheet read-only", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam()
      token = sign(TaskyWeb.Endpoint, teacher.id, exam.id)

      {:ok, _view, html} = live(conn, ~p"/print/exam-paper/#{exam.id}?token=#{token}")

      assert html =~ "Test Prüfung"
      assert html =~ ~s(phx-hook="ExamReadOnlyViewer")
      assert html =~ ~s(id="print-ready-signal")
      # No editing chrome on the page Gotenberg renders.
      refute html =~ ~s(phx-hook="ExamPaperEditor")
      refute html =~ "PDF erstellen"
    end

    test "no session cookie is needed", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam()
      token = sign(TaskyWeb.Endpoint, teacher.id, exam.id)

      assert {:ok, _view, _html} = live(conn, ~p"/print/exam-paper/#{exam.id}?token=#{token}")
    end

    test "a token for another teacher's exam does not grant access", %{conn: conn} do
      %{exam: exam} = create_exam()
      other = user_fixture(%{role: "teacher"})
      token = sign(TaskyWeb.Endpoint, other.id, exam.id)

      # The scope is rebuilt from the token's user id and the exam is fetched
      # through the ordinary scoped accessor, so ownership still decides.
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/print/exam-paper/#{exam.id}?token=#{token}")
      end
    end

    test "a token minted for a different exam is rejected", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam()
      %{exam: other_exam} = create_exam()
      token = sign(TaskyWeb.Endpoint, teacher.id, other_exam.id)

      {:ok, _view, html} = live(conn, ~p"/print/exam-paper/#{exam.id}?token=#{token}")

      assert html =~ "Token entspricht nicht der angeforderten Druckansicht."
    end

    test "a garbage token renders the error page, not a crash", %{conn: conn} do
      %{exam: exam} = create_exam()

      {:ok, _view, html} = live(conn, ~p"/print/exam-paper/#{exam.id}?token=nonsense")

      assert html =~ "Papierversion nicht verfügbar"
      assert html =~ "Token ungültig oder abgelaufen"
    end

    test "a missing token renders the error page", %{conn: conn} do
      %{exam: exam} = create_exam()

      {:ok, _view, html} = live(conn, ~p"/print/exam-paper/#{exam.id}")

      assert html =~ "Token ungültig oder abgelaufen (missing)"
    end

    test "a submission print token cannot be replayed here", %{conn: conn} do
      # The two views use different salts on purpose: one salt, one audience.
      %{teacher: teacher, exam: exam} = create_exam()

      wrong =
        Tasky.Exams.PrintToken.sign(
          TaskyWeb.Endpoint,
          teacher.id,
          to_string(exam.id),
          "1",
          %{}
        )

      {:ok, _view, html} = live(conn, ~p"/print/exam-paper/#{exam.id}?token=#{wrong}")

      assert html =~ "Token ungültig oder abgelaufen"
    end
  end

  describe "free_document exams" do
    test "get blank ruled pages instead of answer boxes", %{conn: conn} do
      %{teacher: teacher, exam: exam} =
        create_exam(
          answer_mode: "free_document",
          content: %{
            "type" => "doc",
            "content" => [
              %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Aufsatz"}]}
            ]
          }
        )

      {:ok, _view, html} = live(log_in_user(conn, teacher), ~p"/exams/#{exam}/paper")

      assert html =~ "paper-lined-page"
      assert html =~ "paper-rule"
      assert html =~ "Seite 2 von #{Tasky.ExamPaper.lined_page_count() + 1}"
    end

    test "an answer_fields exam gets no blank pages", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam()

      {:ok, _view, html} = live(log_in_user(conn, teacher), ~p"/exams/#{exam}/paper")

      refute html =~ "paper-lined-page"
    end
  end
end
