defmodule TaskyWeb.Student.TaskLiveTest do
  use TaskyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.TasksFixtures

  describe "Student Task View" do
    setup do
      student = user_fixture(%{role: "student"})
      teacher = user_fixture(%{role: "teacher"})
      task = task_fixture(teacher)

      %{student: student, teacher: teacher, task: task}
    end

    test "renders task details and creates submission on mount", %{
      conn: conn,
      student: student,
      task: task
    } do
      {:ok, view, html} =
        conn
        |> log_in_user(student)
        |> live(~p"/student/tasks/#{task.id}")

      assert html =~ task.name
      assert html =~ "Not started"
      assert html =~ "Start Task"
    end

    test "student can start a task", %{conn: conn, student: student, task: task} do
      {:ok, view, _html} =
        conn
        |> log_in_user(student)
        |> live(~p"/student/tasks/#{task.id}")

      # Click start task button
      html = view |> element("button", "Start Task") |> render_click()

      assert html =~ "Task started"
      assert html =~ "In progress"
      assert html =~ "Mark as Complete"
    end

    test "student can complete a task", %{conn: conn, student: student, task: task} do
      {:ok, view, _html} =
        conn
        |> log_in_user(student)
        |> live(~p"/student/tasks/#{task.id}")

      # Start the task
      view |> element("button", "Start Task") |> render_click()

      # Complete the task
      html = view |> element("button", "Mark as Complete") |> render_click()

      assert html =~ "Task completed"
      assert html =~ "Completed"
      assert html =~ "Waiting for grade"
    end

    test "student sees grade after teacher grades submission", %{
      conn: conn,
      student: student,
      teacher: teacher,
      task: task
    } do
      # Student completes task
      {:ok, view, _html} =
        conn
        |> log_in_user(student)
        |> live(~p"/student/tasks/#{task.id}")

      view |> element("button", "Start Task") |> render_click()
      view |> element("button", "Mark as Complete") |> render_click()

      # Get submission
      submission =
        Tasky.Tasks.list_task_submissions(
          Tasky.Accounts.Scope.for_user(teacher),
          task.id
        )
        |> List.first()

      # Teacher grades it
      {:ok, _} =
        Tasky.Tasks.grade_submission(
          Tasky.Accounts.Scope.for_user(teacher),
          submission.id,
          %{points: 95, feedback: "Excellent work!"}
        )

      # Student views the grade
      {:ok, _view, html} =
        conn
        |> log_in_user(student)
        |> live(~p"/student/tasks/#{task.id}")

      assert html =~ "95"
      assert html =~ "Excellent work!"
      assert html =~ "graded"
    end

    test "requires student authentication", %{conn: conn, task: task} do
      # Try to access without login
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/student/tasks/#{task.id}")
    end

    test "teacher cannot access student task view", %{conn: conn, teacher: teacher, task: task} do
      # Teacher tries to access student view
      assert {:error, {:redirect, %{to: "/"}}} =
               conn
               |> log_in_user(teacher)
               |> live(~p"/student/tasks/#{task.id}")
    end
  end
end
