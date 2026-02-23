defmodule TaskyWeb.Student.MyTasksLiveTest do
  use TaskyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.TasksFixtures

  describe "Student My Tasks List" do
    setup do
      student = user_fixture(%{role: "student"})
      teacher = user_fixture(%{role: "teacher"})

      task1 = task_fixture(teacher, %{name: "Task 1"})
      task2 = task_fixture(teacher, %{name: "Task 2"})
      task3 = task_fixture(teacher, %{name: "Task 3"})

      %{student: student, teacher: teacher, tasks: [task1, task2, task3]}
    end

    test "renders empty state when no submissions exist", %{
      conn: conn,
      student: student
    } do
      {:ok, _view, html} =
        conn
        |> log_in_user(student)
        |> live(~p"/student/my-tasks")

      assert html =~ "No tasks yet"
      assert html =~ "haven't been assigned any tasks yet"
    end

    test "displays all student submissions", %{
      conn: conn,
      student: student,
      tasks: [task1, task2, task3]
    } do
      # Create submissions by visiting tasks
      scope = Tasky.Accounts.Scope.for_user(student)
      {:ok, _} = Tasky.Tasks.get_or_create_submission(scope, task1.id)
      {:ok, _} = Tasky.Tasks.get_or_create_submission(scope, task2.id)
      {:ok, _} = Tasky.Tasks.get_or_create_submission(scope, task3.id)

      {:ok, _view, html} =
        conn
        |> log_in_user(student)
        |> live(~p"/student/my-tasks")

      assert html =~ "Task 1"
      assert html =~ "Task 2"
      assert html =~ "Task 3"
      assert html =~ "Not started"
    end

    test "shows correct submission statuses", %{
      conn: conn,
      student: student,
      tasks: [task1, task2, task3]
    } do
      scope = Tasky.Accounts.Scope.for_user(student)

      # Create submissions with different statuses
      {:ok, sub1} = Tasky.Tasks.get_or_create_submission(scope, task1.id)
      {:ok, sub2} = Tasky.Tasks.get_or_create_submission(scope, task2.id)
      {:ok, _sub3} = Tasky.Tasks.get_or_create_submission(scope, task3.id)

      # Update statuses
      {:ok, _} = Tasky.Tasks.update_submission_status(scope, sub1.id, "in_progress")
      {:ok, _} = Tasky.Tasks.complete_task(scope, sub2.id)

      {:ok, _view, html} =
        conn
        |> log_in_user(student)
        |> live(~p"/student/my-tasks")

      assert html =~ "Not started"
      assert html =~ "In progress"
      assert html =~ "Completed"
    end

    test "displays grades for graded submissions", %{
      conn: conn,
      student: student,
      teacher: teacher,
      tasks: [task1, _task2, _task3]
    } do
      student_scope = Tasky.Accounts.Scope.for_user(student)
      teacher_scope = Tasky.Accounts.Scope.for_user(teacher)

      # Student completes task
      {:ok, sub} = Tasky.Tasks.get_or_create_submission(student_scope, task1.id)
      {:ok, sub} = Tasky.Tasks.complete_task(student_scope, sub.id)

      # Teacher grades it
      {:ok, _} =
        Tasky.Tasks.grade_submission(teacher_scope, sub.id, %{
          points: 88,
          feedback: "Good job!"
        })

      {:ok, _view, html} =
        conn
        |> log_in_user(student)
        |> live(~p"/student/my-tasks")

      assert html =~ "88"
    end

    test "displays correct stats summary", %{
      conn: conn,
      student: student,
      teacher: teacher,
      tasks: [task1, task2, task3]
    } do
      student_scope = Tasky.Accounts.Scope.for_user(student)
      teacher_scope = Tasky.Accounts.Scope.for_user(teacher)

      # Create and complete some tasks
      {:ok, sub1} = Tasky.Tasks.get_or_create_submission(student_scope, task1.id)
      {:ok, sub2} = Tasky.Tasks.get_or_create_submission(student_scope, task2.id)
      {:ok, _sub3} = Tasky.Tasks.get_or_create_submission(student_scope, task3.id)

      {:ok, sub1} = Tasky.Tasks.complete_task(student_scope, sub1.id)
      {:ok, sub2} = Tasky.Tasks.complete_task(student_scope, sub2.id)

      # Grade one
      {:ok, _} =
        Tasky.Tasks.grade_submission(teacher_scope, sub1.id, %{
          points: 95,
          feedback: "Great!"
        })

      {:ok, _view, html} =
        conn
        |> log_in_user(student)
        |> live(~p"/student/my-tasks")

      assert html =~ "Total Tasks"
      assert html =~ "Completed"
      assert html =~ "Graded"
      # Should show 3 total, 2 completed, 1 graded
    end

    test "clicking view navigates to task detail", %{
      conn: conn,
      student: student,
      tasks: [task1, _task2, _task3]
    } do
      scope = Tasky.Accounts.Scope.for_user(student)
      {:ok, _} = Tasky.Tasks.get_or_create_submission(scope, task1.id)

      {:ok, view, _html} =
        conn
        |> log_in_user(student)
        |> live(~p"/student/my-tasks")

      # Click the view link
      assert view
             |> element("a", "View")
             |> render_click() =~ task1.name
    end

    test "requires student authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/student/my-tasks")
    end

    test "teacher cannot access student my tasks view", %{
      conn: conn,
      teacher: teacher
    } do
      assert {:error, {:redirect, %{to: "/"}}} =
               conn
               |> log_in_user(teacher)
               |> live(~p"/student/my-tasks")
    end

    test "only shows student's own submissions", %{
      conn: conn,
      teacher: teacher,
      tasks: [task1, _task2, _task3]
    } do
      student1 = user_fixture(%{role: "student", email: "student1@test.com"})
      student2 = user_fixture(%{role: "student", email: "student2@test.com"})

      # Both students create submissions
      scope1 = Tasky.Accounts.Scope.for_user(student1)
      scope2 = Tasky.Accounts.Scope.for_user(student2)
      {:ok, _} = Tasky.Tasks.get_or_create_submission(scope1, task1.id)
      {:ok, _} = Tasky.Tasks.get_or_create_submission(scope2, task1.id)

      # Student 1 should only see their own submission
      {:ok, _view, html} =
        conn
        |> log_in_user(student1)
        |> live(~p"/student/my-tasks")

      assert html =~ "Task 1"
      # Should show 1 total task, not 2
      refute html =~ "student2@test.com"
    end
  end
end
