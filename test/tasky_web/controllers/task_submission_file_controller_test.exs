defmodule TaskyWeb.TaskSubmissionFileControllerTest do
  @moduledoc """
  Download und Inline-Ansicht einer Datei-Abgabe.

  Der interessante Teil ist die Inline-Route: sie liefert Bytes einer/eines
  Lernenden auf der App-Origin aus, darf das also nur für Bild- und
  PDF-Inhaltstypen tun und muss die Antwort so härten, dass daraus im
  Browser nichts ausgeführt werden kann.
  """
  use TaskyWeb.ConnCase, async: false

  import Tasky.AccountsFixtures
  import Tasky.TasksFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Courses
  alias Tasky.Tasks
  alias Tasky.Uploads

  setup do
    dir = Path.join(System.tmp_dir!(), "tasky_subfile_#{System.unique_integer([:positive])}")
    prev = Application.get_env(:tasky, :uploads_dir)
    Application.put_env(:tasky, :uploads_dir, dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if prev, do: Application.put_env(:tasky, :uploads_dir, prev)
    end)

    teacher = user_fixture(%{role: "teacher"})
    teacher_scope = Scope.for_user(teacher)
    student = user_fixture(%{role: "student"})

    {:ok, course} = Courses.create_course(teacher_scope, %{name: "Testkurs"})
    task = task_fixture(teacher_scope, %{course_id: course.id})
    {:ok, _} = Courses.enroll_student(course.id, student.id)

    {:ok, field} =
      Tasks.create_task_upload_field(teacher_scope, task, %{
        "label" => "Abgabe",
        "allowed_types" => ["image", "pdf", "docx"]
      })

    {:ok, submission} = Tasks.get_or_create_submission(Scope.for_user(student), task.id)

    %{teacher: teacher, task: task, field: field, submission: submission}
  end

  defp upload(task, submission, field, filename) do
    src = Path.join(System.tmp_dir!(), "src_#{System.unique_integer([:positive])}")
    File.write!(src, "bytes-of-#{filename}")

    {:ok, meta} =
      Uploads.save_task_submission_file(
        task.id,
        submission.id,
        src,
        filename,
        field.allowed_types
      )

    {:ok, file} =
      Tasks.put_submission_file(submission, field, Map.put(meta, :original_name, filename))

    file
  end

  describe "download" do
    test "serves the file as an attachment", ctx do
      %{conn: conn, teacher: teacher, task: task, submission: submission, field: field} = ctx
      file = upload(task, submission, field, "bild.png")

      conn =
        conn
        |> log_in_user(teacher)
        |> get(~p"/tasks/#{task.id}/submissions/#{submission.id}/files/#{file.id}")

      assert response(conn, 200) == "bytes-of-bild.png"

      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "attachment"
    end

    test "refuses another teacher", ctx do
      %{conn: conn, task: task, submission: submission, field: field} = ctx
      file = upload(task, submission, field, "bild.png")

      conn = log_in_user(conn, user_fixture(%{role: "teacher"}))

      assert_error_sent 404, fn ->
        get(conn, ~p"/tasks/#{task.id}/submissions/#{submission.id}/files/#{file.id}")
      end
    end
  end

  describe "inline" do
    test "serves an image inline, hardened and privately cached", ctx do
      %{conn: conn, teacher: teacher, task: task, submission: submission, field: field} = ctx
      file = upload(task, submission, field, "bild.png")

      conn =
        conn
        |> log_in_user(teacher)
        |> get(~p"/tasks/#{task.id}/submissions/#{submission.id}/files/#{file.id}/inline")

      assert response(conn, 200) == "bytes-of-bild.png"
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert get_resp_header(conn, "content-disposition") == []
      assert get_resp_header(conn, "content-security-policy") == ["default-src 'none'; sandbox"]
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end

    test "serves a PDF inline without sandbox, which would kill the viewer", ctx do
      %{conn: conn, teacher: teacher, task: task, submission: submission, field: field} = ctx
      file = upload(task, submission, field, "bericht.pdf")

      conn =
        conn
        |> log_in_user(teacher)
        |> get(~p"/tasks/#{task.id}/submissions/#{submission.id}/files/#{file.id}/inline")

      assert response(conn, 200) == "bytes-of-bericht.pdf"
      assert get_resp_header(conn, "content-type") == ["application/pdf"]

      assert get_resp_header(conn, "content-security-policy") ==
               ["default-src 'none'; object-src 'self'"]
    end

    test "refuses a type that is not an image or PDF", ctx do
      %{conn: conn, teacher: teacher, task: task, submission: submission, field: field} = ctx
      file = upload(task, submission, field, "text.docx")

      conn =
        conn
        |> log_in_user(teacher)
        |> get(~p"/tasks/#{task.id}/submissions/#{submission.id}/files/#{file.id}/inline")

      assert response(conn, 404)
    end

    test "refuses another teacher", ctx do
      %{conn: conn, task: task, submission: submission, field: field} = ctx
      file = upload(task, submission, field, "bild.png")

      conn = log_in_user(conn, user_fixture(%{role: "teacher"}))

      assert_error_sent 404, fn ->
        get(conn, ~p"/tasks/#{task.id}/submissions/#{submission.id}/files/#{file.id}/inline")
      end
    end

    test "refuses a file id from a different submission", ctx do
      %{conn: conn, teacher: teacher, task: task, submission: submission, field: field} = ctx
      file = upload(task, submission, field, "bild.png")

      other_student = user_fixture(%{role: "student"})
      {:ok, other} = Tasks.get_or_create_submission(Scope.for_user(other_student), task.id)

      conn =
        conn
        |> log_in_user(teacher)
        |> get(~p"/tasks/#{task.id}/submissions/#{other.id}/files/#{file.id}/inline")

      assert response(conn, 404)
    end
  end
end
