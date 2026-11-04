defmodule TaskyWeb.AudioControllerTest do
  @moduledoc """
  Audio-Blöcke über HTTP: Upload und Wiedergabe für die Lehrperson, und für
  Lernende die Datei nur während eines Durchgangs — in Byte-Bereichen, wie sie
  ein `<audio>`-Element anfragt.
  """
  use TaskyWeb.ConnCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures
  import Tasky.TasksFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.{Courses, Exams, Tasks}

  @mp3 "ID3" <> :binary.copy(<<1, 2, 3, 4>>, 64)

  defp tmp(bytes) do
    path = Path.join(System.tmp_dir!(), "audio_#{System.unique_integer([:positive])}")
    File.write!(path, bytes)
    path
  end

  defp upload(bytes, filename),
    do: %Plug.Upload{path: tmp(bytes), filename: filename, content_type: "audio/mpeg"}

  defp audio_doc(src, max) do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "audio",
          "attrs" => %{
            "audioId" => "hoer-1",
            "src" => src,
            "maxPlays" => max,
            "title" => "Hörtext"
          }
        }
      ]
    }
  end

  defp exam_with_audio(max) do
    teacher = user_fixture(%{role: "teacher"})
    scope = Scope.for_user(teacher)
    exam = exam_fixture(scope: scope, status: "running")
    {:ok, src} = Tasky.Uploads.save_exam_audio(exam.id, upload(@mp3, "a.mp3"))

    exam =
      exam
      |> Exams.Exam.document_changeset(%{"content" => audio_doc(src, max)})
      |> Tasky.Repo.update!()

    %{teacher: teacher, exam: exam, src: src, submission: exam_submission_fixture(exam)}
  end

  describe "teacher" do
    test "uploads an audio file and plays it back", %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      exam = exam_fixture(scope: Scope.for_user(teacher))
      conn = log_in_user(conn, teacher)

      %{"url" => "/uploads/exams/" <> rest} =
        conn
        |> post(~p"/api/exams/#{exam}/audio", %{"audio" => upload(@mp3, "Hörtext.mp3")})
        |> json_response(200)

      [_id, filename] = String.split(rest, "/")

      # Never public …
      assert build_conn() |> get("/uploads/exams/#{exam.id}/#{filename}") |> response(404)
      # … only to its teacher.
      assert conn |> get("/exams/#{exam.id}/audio/#{filename}") |> response(200) == @mp3
    end

    test "refuses what is not audio", %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      exam = exam_fixture(scope: Scope.for_user(teacher))
      conn = log_in_user(conn, teacher)

      assert conn
             |> post(~p"/api/exams/#{exam}/audio", %{"audio" => upload("<html>", "a.mp3")})
             |> json_response(422)

      assert conn
             |> post(~p"/api/exams/#{exam}/audio", %{"audio" => upload(@mp3, "a.wav")})
             |> json_response(422)
    end
  end

  describe "exam participant" do
    test "gets the file only during a play, in ranges", %{conn: conn} do
      %{submission: s} = exam_with_audio(1)
      file = "/guest/exam/#{s.exam_token}/audio/hoer-1"
      api = "/api/guest/exam/#{s.exam_token}/audio/hoer-1"

      assert conn |> get(file) |> response(403)

      conn = conn |> get(~p"/") |> recycle()
      csrf = Plug.CSRFProtection.get_csrf_token()

      started =
        conn
        |> put_req_header("x-csrf-token", csrf)
        |> post(api <> "/start")
        |> json_response(200)

      assert %{"started" => 1, "active" => true, "maxPlays" => 1} = started

      ranged = build_conn() |> put_req_header("range", "bytes=0-9") |> get(file)
      assert response(ranged, 206) == binary_part(@mp3, 0, 10)
      assert get_resp_header(ranged, "content-range") == ["bytes 0-9/#{byte_size(@mp3)}"]
      assert get_resp_header(ranged, "cache-control") == ["private, no-store"]

      # A reversed range is no range: the whole file (RFC 9110).
      assert build_conn() |> put_req_header("range", "bytes=9-0") |> get(file) |> response(200) ==
               @mp3

      assert build_conn() |> put_req_header("range", "bytes=-0") |> get(file) |> response(416)

      assert build_conn() |> put_req_header("range", "bytes=-4") |> get(file) |> response(206) ==
               binary_part(@mp3, byte_size(@mp3) - 4, 4)

      {:ok, _} = Exams.finish_audio_play(s, "hoer-1")
      assert build_conn() |> get(file) |> response(403)
      assert {:error, :exhausted} = Exams.start_audio_play(s, "hoer-1")
    end

    test "a block without a limit plays while the exam runs", %{conn: conn} do
      %{submission: s} = exam_with_audio(nil)
      assert conn |> get("/guest/exam/#{s.exam_token}/audio/hoer-1") |> response(200) == @mp3
    end
  end

  describe "student" do
    setup %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      teacher_scope = Scope.for_user(teacher)
      student = user_fixture(%{role: "student"})
      {:ok, course} = Courses.create_course(teacher_scope, %{name: "Kurs"})
      task = task_fixture(teacher_scope, %{course_id: course.id, status: "open"})
      {:ok, _} = Courses.enroll_student(course.id, student.id)
      {:ok, src} = Tasky.Uploads.save_task_audio(task.id, upload(@mp3, "a.mp3"))
      {:ok, task} = Tasks.save_task_content(teacher_scope, task, audio_doc(src, 1))
      {:ok, _} = Tasks.get_or_create_submission(Scope.for_user(student), task.id)

      %{conn: log_in_user(conn, student), task: task}
    end

    test "plays once, then the file stays shut", %{conn: conn, task: task} do
      file = "/student/tasks/#{task.id}/audio/hoer-1"
      api = "/api/student/tasks/#{task.id}/audio/hoer-1"

      assert conn |> get(file) |> response(403)

      conn = conn |> get(~p"/student/courses") |> recycle()
      csrf = Plug.CSRFProtection.get_csrf_token()

      post_api = fn conn, path ->
        conn |> put_req_header("x-csrf-token", csrf) |> post(api <> path)
      end

      assert %{"started" => 1} = conn |> post_api.("/start") |> json_response(200)
      assert conn |> recycle() |> get(file) |> response(200) == @mp3

      assert %{"active" => false} =
               conn |> recycle() |> post_api.("/finish") |> json_response(200)

      assert conn |> recycle() |> post_api.("/start") |> json_response(409)
      assert conn |> recycle() |> get(file) |> response(403)
    end
  end
end
