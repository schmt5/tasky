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
    test "downloads the paper version as a PDF", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam()

      conn = get(log_in_user(conn, teacher), ~p"/exams/#{exam}/paper.pdf")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/pdf"]

      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "Test-Pruefung-Papierversion.pdf"
      assert "%PDF" <> _ = conn.resp_body
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
