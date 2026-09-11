defmodule TaskyWeb.ExamPaperLayoutApiControllerTest do
  use TaskyWeb.ConnCase, async: true

  import Tasky.AccountsFixtures

  alias Tasky.Exams

  defp exam_content do
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

  defp create_exam do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    {:ok, exam} =
      Exams.create_exam(scope, %{name: "Test Prüfung", content: exam_content()})

    %{teacher: teacher, scope: scope, exam: exam}
  end

  # The paper editor sends a whole document, exactly like every other editor.
  defp paper_doc(lines) do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-1"},
          "content" => [%{"type" => "text", "text" => "Frage Eins (2 Punkte)"}]
        },
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => "a1"},
          "content" => List.duplicate(%{"type" => "paragraph"}, lines)
        }
      ]
    }
  end

  defp put_layout(conn, exam, doc) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(~p"/api/exams/#{exam}/paper-layout", %{"content" => doc})
  end

  describe "PUT /api/exams/:id/paper-layout" do
    test "persists the line counts", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam()

      conn = put_layout(log_in_user(conn, teacher), exam, paper_doc(6))

      assert json_response(conn, 200)["ok"] == true
      assert Exams.get_exam!(scope, exam.id).paper_layout == %{"a1" => 6}
    end

    test "leaves the exam content untouched", %{conn: conn} do
      # The load-bearing guarantee: the print geometry must never reach the
      # document the learners sit.
      %{teacher: teacher, scope: scope, exam: exam} = create_exam()

      put_layout(log_in_user(conn, teacher), exam, paper_doc(9))

      assert Exams.get_exam!(scope, exam.id).content == exam_content()
    end

    test "text the teacher typed into a box is not persisted", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam()

      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "answerBlock",
            "attrs" => %{"answerId" => "a1"},
            "content" => [
              %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Notiz"}]},
              %{"type" => "paragraph"}
            ]
          }
        ]
      }

      put_layout(log_in_user(conn, teacher), exam, doc)

      assert Exams.get_exam!(scope, exam.id).paper_layout == %{"a1" => 2}
    end

    test "rejects a request without a content field", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam()

      conn =
        log_in_user(conn, teacher)
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/exams/#{exam}/paper-layout", %{})

      assert json_response(conn, 400)["error"] =~ "content"
    end

    test "another teacher cannot write the layout", %{conn: conn} do
      %{exam: exam} = create_exam()
      other = user_fixture(%{role: "teacher"})

      assert_raise Ecto.NoResultsError, fn ->
        put_layout(log_in_user(conn, other), exam, paper_doc(3))
      end
    end

    test "an anonymous request is refused", %{conn: conn} do
      %{exam: exam} = create_exam()

      conn = put_layout(conn, exam, paper_doc(3))

      assert conn.status in [302, 401, 403]
    end
  end
end
