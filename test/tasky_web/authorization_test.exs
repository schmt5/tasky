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

    test "students cannot reach the sample solution API", %{conn: conn, task: task} do
      conn =
        conn
        |> log_in_role("student")
        |> put("/api/tasks/#{task.id}/sample-solution", @doc_body)

      assert conn.status in [302, 401, 403]
    end

    test "a foreign teacher gets 404 for another teacher's sample solution", %{
      conn: conn,
      task: task
    } do
      conn = log_in_role(conn, "teacher")

      assert_error_sent 404, fn ->
        put(conn, "/api/tasks/#{task.id}/sample-solution", @doc_body)
      end
    end

    test "a foreign teacher gets 404 for another teacher's task correction", %{
      conn: conn,
      task: task
    } do
      conn = log_in_role(conn, "teacher")

      assert_error_sent 404, fn ->
        put(conn, "/api/tasks/#{task.id}/submissions/1/correction", @doc_body)
      end
    end

    test "students cannot reach the task correction API", %{conn: conn, task: task} do
      conn =
        conn
        |> log_in_role("student")
        |> put("/api/tasks/#{task.id}/submissions/1/correction", @doc_body)

      assert conn.status in [302, 401, 403]
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

    test "teachers cannot open the student exam list", %{conn: conn} do
      conn = conn |> log_in_role("teacher") |> get("/student/exams")
      assert redirected_to(conn) == "/"
    end

    test "anonymous users cannot open the student exam list", %{conn: conn} do
      assert redirected_to(get(conn, "/student/exams")) =~ "/users/log-in"
    end

    test "students cannot open the session config", %{conn: conn, exam: exam} do
      conn = conn |> log_in_role("student") |> get("/exams/#{exam.id}/cockpit/config")
      assert redirected_to(conn) == "/"
    end

    test "a foreign teacher cannot open another teacher's session config", %{
      conn: conn,
      exam: exam
    } do
      assert_raise Ecto.NoResultsError, fn ->
        conn |> log_in_role("teacher") |> get("/exams/#{exam.id}/cockpit/config")
      end
    end
  end

  describe "course feedback mailbox" do
    setup do
      owner_scope = Scope.for_user(user_fixture(%{role: "teacher"}))
      {:ok, course} = Tasky.Courses.create_course(owner_scope, %{name: "Briefkastenkurs"})

      %{course: course}
    end

    test "a foreign teacher gets 404 for another teacher's mailbox", %{
      conn: conn,
      course: course
    } do
      conn = log_in_role(conn, "teacher")

      assert_error_sent 404, fn -> get(conn, "/courses/#{course.id}/feedback") end
    end

    test "students cannot open the teacher mailbox", %{conn: conn, course: course} do
      conn = conn |> log_in_role("student") |> get("/courses/#{course.id}/feedback")
      assert redirected_to(conn) == "/"
    end

    test "teachers cannot open the student feedback form", %{conn: conn, course: course} do
      conn = conn |> log_in_role("teacher") |> get("/student/courses/#{course.id}/feedback")
      assert redirected_to(conn) == "/"
    end

    test "a student who is not enrolled is sent away", %{conn: conn, course: course} do
      conn = conn |> log_in_role("student") |> get("/student/courses/#{course.id}/feedback")
      assert redirected_to(conn) == "/student/courses"
    end

    test "anonymous users cannot reach either side", %{conn: conn, course: course} do
      assert redirected_to(get(conn, "/courses/#{course.id}/feedback")) =~ "/users/log-in"

      assert redirected_to(get(conn, "/student/courses/#{course.id}/feedback")) =~
               "/users/log-in"
    end
  end

  describe "Kurs-Katalog" do
    setup do
      owner_scope = Scope.for_user(user_fixture(%{role: "teacher"}))
      {:ok, course} = Tasky.Courses.create_course(owner_scope, %{name: "Katalogkurs"})
      task_fixture(owner_scope, %{name: "Einheit", position: 0, course_id: course.id})
      {:ok, published} = Tasky.Courses.publish_to_catalog(owner_scope, course)

      %{course: course, published: published}
    end

    # The one positive row in this file: cross-teacher reading IS the feature.
    test "a foreign teacher may browse the catalog and preview a course", %{
      conn: conn,
      published: published
    } do
      conn = log_in_role(conn, "teacher")

      assert html_response(get(conn, "/catalog"), 200)
      assert html_response(get(conn, "/catalog/#{published.id}"), 200)
    end

    test "a foreign teacher gets 404 for a course that is not in the catalog", %{conn: conn} do
      private_scope = Scope.for_user(user_fixture(%{role: "teacher"}))
      {:ok, private} = Tasky.Courses.create_course(private_scope, %{name: "Privat"})

      conn = log_in_role(conn, "teacher")

      assert_error_sent 404, fn -> get(conn, "/catalog/#{private.id}") end
    end

    test "students cannot reach the catalog", %{conn: conn, published: published} do
      conn = log_in_role(conn, "student")

      assert redirected_to(get(conn, "/catalog")) == "/"
      assert redirected_to(get(conn, "/catalog/#{published.id}")) == "/"
    end

    test "anonymous users are sent to login", %{conn: conn, published: published} do
      assert redirected_to(get(conn, "/catalog")) =~ "/users/log-in"
      assert redirected_to(get(conn, "/catalog/#{published.id}")) =~ "/users/log-in"
    end
  end
end
