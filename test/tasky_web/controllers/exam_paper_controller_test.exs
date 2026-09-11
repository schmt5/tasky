defmodule TaskyWeb.ExamPaperControllerTest do
  use TaskyWeb.ConnCase, async: true

  import Tasky.AccountsFixtures

  alias Tasky.Exams

  defp create_exam do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    {:ok, exam} =
      Exams.create_exam(scope, %{
        name: "Test Prüfung",
        content: %{"type" => "doc", "content" => []}
      })

    %{teacher: teacher, exam: exam}
  end

  describe "GET /exams/:id/paper.pdf" do
    test "reports the missing PDF service rather than failing opaquely", %{conn: conn} do
      # :test configures no gotenberg_url, so this is the unconfigured branch.
      # Deliberately no test that actually talks to Gotenberg.
      %{teacher: teacher, exam: exam} = create_exam()

      conn = get(log_in_user(conn, teacher), ~p"/exams/#{exam}/paper.pdf")

      assert conn.status == 503
      assert conn.resp_body =~ "Gotenberg"
      # The message must be readable in the tab the link opened, which is why
      # this path is a plain navigation and not a push_event download.
      assert conn.resp_body =~ "nicht konfiguriert"
    end

    test "an anonymous visitor is redirected to the log-in", %{conn: conn} do
      %{exam: exam} = create_exam()

      conn = get(conn, ~p"/exams/#{exam}/paper.pdf")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "another teacher cannot download it", %{conn: conn} do
      %{exam: exam} = create_exam()
      other = user_fixture(%{role: "teacher"})

      assert_raise Ecto.NoResultsError, fn ->
        get(log_in_user(conn, other), ~p"/exams/#{exam}/paper.pdf")
      end
    end
  end
end
