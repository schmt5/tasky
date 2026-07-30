defmodule TaskyWeb.AuthorizationTest do
  @moduledoc """
  The route-level authorization matrix for the critical endpoints: every row
  asserts what a given role may NOT reach. Context-level rules live in
  `Tasky.Policy` and are tested with the contexts; this file guards the
  pipelines and the scoped lookups in front of them.
  """
  use TaskyWeb.ConnCase, async: false

  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures
  import Tasky.TasksFixtures

  alias Tasky.Accounts.Scope

  @doc_body %{"content" => %{"type" => "doc", "content" => []}}

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    teacher_scope = Scope.for_user(teacher)
    exam = exam_fixture(scope: teacher_scope)
    task = task_fixture(teacher_scope, %{name: "AuthZ-Task"})

    %{conn: conn, teacher: teacher, exam: exam, task: task}
  end

  defp log_in_role(conn, role) do
    log_in_user(conn, user_fixture(%{role: role}))
  end

  describe "teacher/admin JSON APIs (/api)" do
    test "anonymous requests are rejected", %{conn: conn, exam: exam} do
      conn = put(conn, "/api/exams/#{exam.id}/content", @doc_body)
      assert conn.status in [302, 401, 403]
      refute conn.status == 200
    end

    test "students cannot reach the exam content API", %{conn: conn, exam: exam} do
      conn = conn |> log_in_role("student") |> put("/api/exams/#{exam.id}/content", @doc_body)
      assert conn.status in [302, 401, 403]
    end

    test "a foreign teacher gets 404 for another teacher's exam", %{conn: conn, exam: exam} do
      conn = log_in_role(conn, "teacher")

      assert_error_sent 404, fn ->
        put(conn, "/api/exams/#{exam.id}/content", @doc_body)
      end
    end

    test "a foreign teacher gets 404 for another teacher's task", %{conn: conn, task: task} do
      conn = log_in_role(conn, "teacher")

      assert_error_sent 404, fn ->
        put(conn, "/api/tasks/#{task.id}/content", @doc_body)
      end
    end

    test "an admin may edit any teacher's exam content", %{conn: conn, exam: exam} do
      conn = conn |> log_in_role("admin") |> put("/api/exams/#{exam.id}/content", @doc_body)
      assert json_response(conn, 200)["ok"] == true
    end
  end

  describe "correction API" do
    test "a foreign teacher cannot write corrections", %{conn: conn} do
      exam =
        exam_fixture(scope: Scope.for_user(user_fixture(%{role: "teacher"})), status: "running")

      {:ok, submission} = Tasky.Exams.create_exam_submission(exam, valid_enrollment_attrs())

      conn = log_in_role(conn, "teacher")

      assert_error_sent 404, fn ->
        put(
          conn,
          "/api/exams/#{exam.id}/submissions/#{submission.id}/parts/q-1/content",
          %{"nodes" => []}
        )
      end
    end
  end

  describe "teacher file downloads" do
    test "a foreign teacher cannot download submission files", %{conn: conn} do
      owner_scope = Scope.for_user(user_fixture(%{role: "teacher"}))
      exam = exam_fixture(scope: owner_scope, status: "running")
      {:ok, submission} = Tasky.Exams.create_exam_submission(exam, valid_enrollment_attrs())

      conn = log_in_role(conn, "teacher")

      assert_error_sent 404, fn ->
        get(conn, "/exams/#{exam.id}/submissions/#{submission.id}/files/1")
      end
    end
  end

  describe "guest exam API" do
    test "an unknown exam token is a 404, not a crash page", %{conn: conn} do
      assert_error_sent 404, fn ->
        put(conn, "/api/guest/exam/does-not-exist/content", @doc_body)
      end
    end
  end

  describe "role-gated browser scopes" do
    test "students cannot open the teacher exam list", %{conn: conn} do
      conn = conn |> log_in_role("student") |> get("/exams")
      assert redirected_to(conn) == "/"
    end

    test "teachers cannot open the admin user list", %{conn: conn} do
      conn = conn |> log_in_role("teacher") |> get("/admin/users")
      assert redirected_to(conn) == "/"
    end

    test "teachers cannot open student routes", %{conn: conn, task: task} do
      conn = conn |> log_in_role("teacher") |> get("/student/tasks/#{task.id}")
      assert redirected_to(conn) == "/"
    end

    test "anonymous users are sent to login for authenticated pages", %{conn: conn} do
      conn = get(conn, "/exams")
      assert redirected_to(conn) =~ "/users/log-in"
    end
  end
end
