defmodule TaskyWeb.ExamPaperLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures

  alias Tasky.Exams

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

  describe "the teacher's paper view" do
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

    test "offers the PDF download under the app's page header", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam()

      {:ok, view, _html} = live(log_in_user(conn, teacher), ~p"/exams/#{exam}/paper")

      assert has_element?(view, ~s(#paper-pdf-download[href="/exams/#{exam.id}/paper.pdf"]))
      # Breadcrumb and back button lead to the exam, like the other exam pages.
      assert has_element?(view, ~s(nav a[href="/exams/#{exam.id}"]))
    end

    test "leads back to the cockpit when opened from there", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam()
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}/paper?from=cockpit")
      assert has_element?(view, ~s(nav a[href="/exams/#{exam.id}/cockpit"]))
      assert has_element?(view, ~s(.tooltip a[href="/exams/#{exam.id}/cockpit"]))

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}/paper")
      refute has_element?(view, ~s(a[href="/exams/#{exam.id}/cockpit"]))
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
