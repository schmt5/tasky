defmodule TaskyWeb.TaskPdfControllerTest do
  use TaskyWeb.ConnCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.TasksFixtures

  defp create_task do
    teacher = user_fixture(%{role: "teacher"})
    task = task_fixture(user_scope_fixture(teacher), %{name: "Brüche üben"})

    %{teacher: teacher, task: task}
  end

  for {path, suffix} <- [{"worksheet.pdf", "Arbeitsblatt"}, {"solution.pdf", "Musterloesung"}] do
    describe "GET /tasks/:id/#{path}" do
      test "downloads the PDF", %{conn: conn} do
        %{teacher: teacher, task: task} = create_task()

        conn = get(log_in_user(conn, teacher), "/tasks/#{task.id}/#{unquote(path)}")

        assert conn.status == 200
        assert get_resp_header(conn, "content-type") == ["application/pdf"]
        assert [disposition] = get_resp_header(conn, "content-disposition")
        assert disposition =~ "-#{unquote(suffix)}.pdf"
        assert "%PDF" <> _ = conn.resp_body
      end

      test "an anonymous visitor is redirected to the log-in", %{conn: conn} do
        %{task: task} = create_task()

        conn = get(conn, "/tasks/#{task.id}/#{unquote(path)}")

        assert redirected_to(conn) == ~p"/users/log-in"
      end

      test "another teacher cannot download it", %{conn: conn} do
        %{task: task} = create_task()
        other = user_fixture(%{role: "teacher"})

        assert_raise Ecto.NoResultsError, fn ->
          get(log_in_user(conn, other), "/tasks/#{task.id}/#{unquote(path)}")
        end
      end
    end
  end
end
