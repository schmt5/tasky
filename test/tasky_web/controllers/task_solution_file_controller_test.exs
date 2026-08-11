defmodule TaskyWeb.TaskSolutionFileControllerTest do
  @moduledoc """
  Der Download einer Musterlösungs-Datei — für Lehrpersonen über den Scope,
  für Lernende nur nach Freigabe.

  Der wichtige Teil ist der 404: dass es zu einer Lerneinheit überhaupt eine
  Lösungsdatei gibt, darf ohne Freigabe nicht sichtbar werden.
  """
  use TaskyWeb.ConnCase, async: false

  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.TasksFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Courses
  alias Tasky.Tasks

  setup do
    dir = Path.join(System.tmp_dir!(), "tasky_uploads_test_#{System.unique_integer([:positive])}")
    prev = Application.get_env(:tasky, :uploads_dir)
    Application.put_env(:tasky, :uploads_dir, dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if prev, do: Application.put_env(:tasky, :uploads_dir, prev)
    end)

    teacher = user_fixture(%{role: "teacher"})
    teacher_scope = Scope.for_user(teacher)
    course = course_fixture(scope: teacher_scope)

    task =
      task_fixture(teacher_scope, %{status: "published", course_id: course.id})

    student = user_fixture(%{role: "student"})
    {:ok, _} = Courses.enroll_student(course.id, student.id)

    path = Path.join(System.tmp_dir!(), "sol_#{System.unique_integer([:positive])}")
    File.write!(path, "docx-bytes")
    {:ok, meta} = Tasky.Uploads.save_task_solution_file(task.id, path, "loesung.docx")

    {:ok, file} =
      Tasks.create_task_solution_file(
        teacher_scope,
        task,
        Map.put(meta, :original_name, "loesung.docx")
      )

    %{
      teacher: teacher,
      teacher_scope: teacher_scope,
      course: course,
      task: task,
      student: student,
      solution_file: file
    }
  end

  describe "Lehrperson" do
    test "lädt die eigene Lösungsdatei herunter", %{
      conn: conn,
      teacher: teacher,
      task: task,
      solution_file: file
    } do
      conn =
        conn
        |> log_in_user(teacher)
        |> get(~p"/tasks/#{task.id}/solution-files/#{file.id}")

      assert response(conn, 200) == "docx-bytes"
    end

    test "kommt nicht an die Datei einer fremden Lehrperson", %{
      conn: conn,
      task: task,
      solution_file: file
    } do
      other = user_fixture(%{role: "teacher"})
      conn = log_in_user(conn, other)

      assert_error_sent 404, fn ->
        get(conn, ~p"/tasks/#{task.id}/solution-files/#{file.id}")
      end
    end
  end

  describe "Lernende" do
    test "bekommen ohne Freigabe 404", %{
      conn: conn,
      student: student,
      task: task,
      solution_file: file
    } do
      conn =
        conn
        |> log_in_user(student)
        |> get(~p"/student/tasks/#{task.id}/solution-files/#{file.id}")

      assert response(conn, 404)
    end

    test "laden nach der Freigabe herunter", %{
      conn: conn,
      teacher_scope: teacher_scope,
      student: student,
      task: task,
      solution_file: file
    } do
      {:ok, task} = Tasks.update_task(teacher_scope, task, %{solution_release_mode: "manual"})
      {:ok, submission} = Tasks.get_or_create_submission(Scope.for_user(student), task.id)
      {:ok, _} = Tasks.release_solution(teacher_scope, task, submission.id)

      conn =
        conn
        |> log_in_user(student)
        |> get(~p"/student/tasks/#{task.id}/solution-files/#{file.id}")

      assert response(conn, 200) == "docx-bytes"
    end

    test "bekommen im Modus never auch mit Freigabe 404", %{
      conn: conn,
      teacher_scope: teacher_scope,
      student: student,
      task: task,
      solution_file: file
    } do
      {:ok, released_task} =
        Tasks.update_task(teacher_scope, task, %{solution_release_mode: "manual"})

      {:ok, submission} = Tasks.get_or_create_submission(Scope.for_user(student), task.id)
      {:ok, _} = Tasks.release_solution(teacher_scope, released_task, submission.id)

      {:ok, _} =
        Tasks.update_task(teacher_scope, released_task, %{solution_release_mode: "never"})

      conn =
        conn
        |> log_in_user(student)
        |> get(~p"/student/tasks/#{task.id}/solution-files/#{file.id}")

      assert response(conn, 404)
    end

    test "aus einem anderen Kurs bekommen 404", %{
      conn: conn,
      teacher_scope: teacher_scope,
      task: task,
      solution_file: file
    } do
      {:ok, _task} =
        Tasks.update_task(teacher_scope, task, %{solution_release_mode: "on_complete"})

      outsider = user_fixture(%{role: "student"})

      conn =
        conn
        |> log_in_user(outsider)
        |> get(~p"/student/tasks/#{task.id}/solution-files/#{file.id}")

      assert response(conn, 404)
    end
  end
end
