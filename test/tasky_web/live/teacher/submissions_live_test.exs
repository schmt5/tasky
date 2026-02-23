defmodule TaskyWeb.Teacher.SubmissionsLiveTest do
  use TaskyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.TasksFixtures

  describe "Teacher Submissions List" do
    setup do
      teacher = user_fixture(%{role: "teacher"})
      student1 = user_fixture(%{role: "student", email: "student1@test.com"})
      student2 = user_fixture(%{role: "student", email: "student2@test.com"})
      student3 = user_fixture(%{role: "student", email: "student3@test.com"})

      task = task_fixture(teacher, %{name: "Test Assignment"})

      %{
        teacher: teacher,
        students: [student1, student2, student3],
        task: task
      }
    end

    test "renders empty state when no submissions exist", %{
      conn: conn,
      teacher: teacher,
      task: task
    } do
      {:ok, _view, html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/submissions")

      assert html =~ "No submissions yet"
      assert html =~ "Students haven't started working on this task yet"
    end

    test "displays all student submissions for a task", %{
      conn: conn,
      teacher: teacher,
      students: [student1, student2, student3],
      task: task
    } do
      # Students create submissions
      scope1 = Tasky.Accounts.Scope.for_user(student1)
      scope2 = Tasky.Accounts.Scope.for_user(student2)
      scope3 = Tasky.Accounts.Scope.for_user(student3)

      {:ok, _} = Tasky.Tasks.get_or_create_submission(scope1, task.id)
      {:ok, _} = Tasky.Tasks.get_or_create_submission(scope2, task.id)
      {:ok, _} = Tasky.Tasks.get_or_create_submission(scope3, task.id)

      {:ok, _view, html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/submissions")

      assert html =~ "student1@test.com"
      assert html =~ "student2@test.com"
      assert html =~ "student3@test.com"
    end

    test "shows correct submission statuses", %{
      conn: conn,
      teacher: teacher,
      students: [student1, student2, student3],
      task: task
    } do
      scope1 = Tasky.Accounts.Scope.for_user(student1)
      scope2 = Tasky.Accounts.Scope.for_user(student2)
      scope3 = Tasky.Accounts.Scope.for_user(student3)

      # Different statuses for each student
      {:ok, _sub1} = Tasky.Tasks.get_or_create_submission(scope1, task.id)
      {:ok, sub2} = Tasky.Tasks.get_or_create_submission(scope2, task.id)
      {:ok, sub3} = Tasky.Tasks.get_or_create_submission(scope3, task.id)

      {:ok, _} = Tasky.Tasks.update_submission_status(scope2, sub2.id, "in_progress")
      {:ok, _} = Tasky.Tasks.complete_task(scope3, sub3.id)

      {:ok, _view, html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/submissions")

      assert html =~ "Not started"
      assert html =~ "In progress"
      assert html =~ "Completed"
    end

    test "displays grades for graded submissions", %{
      conn: conn,
      teacher: teacher,
      students: [student1, _student2, _student3],
      task: task
    } do
      student_scope = Tasky.Accounts.Scope.for_user(student1)
      teacher_scope = Tasky.Accounts.Scope.for_user(teacher)

      # Student completes task
      {:ok, sub} = Tasky.Tasks.get_or_create_submission(student_scope, task.id)
      {:ok, sub} = Tasky.Tasks.complete_task(student_scope, sub.id)

      # Teacher grades it
      {:ok, _} =
        Tasky.Tasks.grade_submission(teacher_scope, sub.id, %{
          points: 92,
          feedback: "Well done!"
        })

      {:ok, _view, html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/submissions")

      assert html =~ "92"
      assert html =~ teacher.email
    end

    test "displays correct stats summary", %{
      conn: conn,
      teacher: teacher,
      students: [student1, student2, student3],
      task: task
    } do
      student_scope1 = Tasky.Accounts.Scope.for_user(student1)
      student_scope2 = Tasky.Accounts.Scope.for_user(student2)
      student_scope3 = Tasky.Accounts.Scope.for_user(student3)
      teacher_scope = Tasky.Accounts.Scope.for_user(teacher)

      # Create submissions with different states
      {:ok, sub1} = Tasky.Tasks.get_or_create_submission(student_scope1, task.id)
      {:ok, sub2} = Tasky.Tasks.get_or_create_submission(student_scope2, task.id)
      {:ok, _sub3} = Tasky.Tasks.get_or_create_submission(student_scope3, task.id)

      # Complete two tasks
      {:ok, sub1} = Tasky.Tasks.complete_task(student_scope1, sub1.id)
      {:ok, sub2} = Tasky.Tasks.complete_task(student_scope2, sub2.id)

      # Grade one
      {:ok, _} =
        Tasky.Tasks.grade_submission(teacher_scope, sub1.id, %{
          points: 85,
          feedback: "Good!"
        })

      {:ok, _view, html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/submissions")

      assert html =~ "Total Students"
      assert html =~ "Completed"
      assert html =~ "Graded"
      assert html =~ "Pending"
      # Should show 3 total, 2 completed, 1 graded, 1 pending
    end

    test "grade button only shows for completed submissions", %{
      conn: conn,
      teacher: teacher,
      students: [student1, student2, _student3],
      task: task
    } do
      scope1 = Tasky.Accounts.Scope.for_user(student1)
      scope2 = Tasky.Accounts.Scope.for_user(student2)

      {:ok, _sub1} = Tasky.Tasks.get_or_create_submission(scope1, task.id)
      {:ok, sub2} = Tasky.Tasks.get_or_create_submission(scope2, task.id)
      {:ok, _} = Tasky.Tasks.complete_task(scope2, sub2.id)

      {:ok, view, _html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/submissions")

      # Find the rows
      html = render(view)

      # Student1 (not completed) should show "Not ready"
      assert html =~ "Not ready"

      # Student2 (completed) should have Grade link
      assert html =~ "Grade"
    end

    test "edit grade button shows for already graded submissions", %{
      conn: conn,
      teacher: teacher,
      students: [student1, _student2, _student3],
      task: task
    } do
      student_scope = Tasky.Accounts.Scope.for_user(student1)
      teacher_scope = Tasky.Accounts.Scope.for_user(teacher)

      {:ok, sub} = Tasky.Tasks.get_or_create_submission(student_scope, task.id)
      {:ok, sub} = Tasky.Tasks.complete_task(student_scope, sub.id)

      {:ok, _} =
        Tasky.Tasks.grade_submission(teacher_scope, sub.id, %{
          points: 90,
          feedback: "Great work!"
        })

      {:ok, _view, html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/submissions")

      assert html =~ "Edit Grade"
    end

    test "clicking grade navigates to grading page", %{
      conn: conn,
      teacher: teacher,
      students: [student1, _student2, _student3],
      task: task
    } do
      student_scope = Tasky.Accounts.Scope.for_user(student1)

      {:ok, sub} = Tasky.Tasks.get_or_create_submission(student_scope, task.id)
      {:ok, _} = Tasky.Tasks.complete_task(student_scope, sub.id)

      {:ok, view, _html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/submissions")

      # Click grade link
      assert view
             |> element("a", "Grade")
             |> render_click() =~ "Grade Submission"
    end

    test "requires teacher authentication", %{conn: conn, task: task} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/tasks/#{task.id}/submissions")
    end

    test "student cannot access teacher submissions view", %{
      conn: conn,
      students: [student1, _student2, _student3],
      task: task
    } do
      assert {:error, {:redirect, %{to: "/"}}} =
               conn
               |> log_in_user(student1)
               |> live(~p"/tasks/#{task.id}/submissions")
    end

    test "teacher can only see submissions for their own tasks", %{
      conn: conn,
      students: [student1, _student2, _student3],
      task: task
    } do
      other_teacher = user_fixture(%{role: "teacher", email: "other@teacher.com"})
      student_scope = Tasky.Accounts.Scope.for_user(student1)

      # Student creates submission
      {:ok, _} = Tasky.Tasks.get_or_create_submission(student_scope, task.id)

      # Other teacher tries to view (task was created by first teacher)
      # This should raise because the task doesn't exist in their scope
      assert_raise Ecto.NoResultsError, fn ->
        conn
        |> log_in_user(other_teacher)
        |> live(~p"/tasks/#{task.id}/submissions")
      end
    end

    test "admin can view any teacher's task submissions", %{
      conn: conn,
      students: [student1, _student2, _student3],
      task: task
    } do
      admin = user_fixture(%{role: "admin", email: "admin@test.com"})
      student_scope = Tasky.Accounts.Scope.for_user(student1)

      {:ok, _} = Tasky.Tasks.get_or_create_submission(student_scope, task.id)

      {:ok, _view, html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/tasks/#{task.id}/submissions")

      assert html =~ "student1@test.com"
    end
  end
end
