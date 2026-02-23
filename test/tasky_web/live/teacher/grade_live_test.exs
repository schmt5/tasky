defmodule TaskyWeb.Teacher.GradeLiveTest do
  use TaskyWeb.ConnCase

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.TasksFixtures

  describe "Teacher Grade Submission" do
    setup do
      teacher = user_fixture(%{role: "teacher"})
      student = user_fixture(%{role: "student", email: "student@test.com"})
      task = task_fixture(teacher, %{name: "Test Assignment"})

      # Student completes the task
      student_scope = Tasky.Accounts.Scope.for_user(student)
      {:ok, submission} = Tasky.Tasks.get_or_create_submission(student_scope, task.id)
      {:ok, submission} = Tasky.Tasks.complete_task(student_scope, submission.id)

      %{
        teacher: teacher,
        student: student,
        task: task,
        submission: submission
      }
    end

    test "renders grading form for completed submission", %{
      conn: conn,
      teacher: teacher,
      task: task,
      submission: submission
    } do
      {:ok, _view, html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/grade/#{submission.id}")

      assert html =~ "Grade Submission"
      assert html =~ "student@test.com"
      assert html =~ task.name
      assert html =~ "Points"
      assert html =~ "Feedback"
    end

    test "teacher can grade a submission", %{
      conn: conn,
      teacher: teacher,
      task: task,
      submission: submission
    } do
      {:ok, view, _html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/grade/#{submission.id}")

      # Submit the grade form
      view
      |> form("#grade-form", %{points: "85", feedback: "Great work!"})
      |> render_submit()

      # Should redirect to submissions list
      assert_redirected(view, ~p"/tasks/#{task.id}/submissions")

      # Verify the grade was saved
      teacher_scope = Tasky.Accounts.Scope.for_user(teacher)
      graded_submission = Tasky.Tasks.get_submission!(teacher_scope, submission.id)
      assert graded_submission.points == 85
      assert graded_submission.feedback == "Great work!"
      assert graded_submission.graded_at != nil
      assert graded_submission.graded_by_id == teacher.id
    end

    test "teacher can update an existing grade", %{
      conn: conn,
      teacher: teacher,
      task: task,
      submission: submission
    } do
      # First grade the submission
      teacher_scope = Tasky.Accounts.Scope.for_user(teacher)

      {:ok, _} =
        Tasky.Tasks.grade_submission(teacher_scope, submission.id, %{
          points: 75,
          feedback: "Good effort"
        })

      # Now update the grade
      {:ok, view, html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/grade/#{submission.id}")

      assert html =~ "Update Grade"
      assert html =~ "Current Grade"
      assert html =~ "75"

      # Update the grade
      view
      |> form("#grade-form", %{points: "90", feedback: "Much better!"})
      |> render_submit()

      # Verify the update
      updated_submission = Tasky.Tasks.get_submission!(teacher_scope, submission.id)
      assert updated_submission.points == 90
      assert updated_submission.feedback == "Much better!"
    end

    test "validates points are within 0-100 range", %{
      conn: conn,
      teacher: teacher,
      task: task,
      submission: submission
    } do
      {:ok, view, _html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/grade/#{submission.id}")

      # Try to submit invalid points
      html =
        view
        |> form("#grade-form", %{points: "150", feedback: "Great!"})
        |> render_submit()

      assert html =~ "Failed to grade submission"
    end

    test "feedback is optional", %{
      conn: conn,
      teacher: teacher,
      task: task,
      submission: submission
    } do
      {:ok, view, _html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/grade/#{submission.id}")

      # Submit without feedback
      view
      |> form("#grade-form", %{points: "80", feedback: ""})
      |> render_submit()

      # Should succeed
      teacher_scope = Tasky.Accounts.Scope.for_user(teacher)
      graded_submission = Tasky.Tasks.get_submission!(teacher_scope, submission.id)
      assert graded_submission.points == 80
      assert graded_submission.feedback == ""
    end

    test "displays submission details", %{
      conn: conn,
      teacher: teacher,
      task: task,
      submission: submission
    } do
      {:ok, _view, html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/grade/#{submission.id}")

      assert html =~ "Submission Details"
      assert html =~ "Completed"
      assert html =~ "Completed At"
    end

    test "shows task link if available", %{
      conn: conn,
      teacher: teacher,
      student: student
    } do
      teacher_scope = Tasky.Accounts.Scope.for_user(teacher)
      student_scope = Tasky.Accounts.Scope.for_user(student)

      task_with_link =
        task_fixture(teacher, %{name: "Task with Link", link: "https://example.com"})

      {:ok, submission} =
        Tasky.Tasks.get_or_create_submission(student_scope, task_with_link.id)

      {:ok, submission} = Tasky.Tasks.complete_task(student_scope, submission.id)

      {:ok, _view, html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task_with_link.id}/grade/#{submission.id}")

      assert html =~ "https://example.com"
      assert html =~ "Task Link"
    end

    test "cancel button navigates back to submissions list", %{
      conn: conn,
      teacher: teacher,
      task: task,
      submission: submission
    } do
      {:ok, view, _html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/grade/#{submission.id}")

      # Click cancel button
      html = view |> element("button", "Cancel") |> render_click()

      # Should navigate back
      assert html =~ "Submissions for"
    end

    test "requires teacher authentication", %{conn: conn, task: task, submission: submission} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/tasks/#{task.id}/grade/#{submission.id}")
    end

    test "student cannot access grading page", %{
      conn: conn,
      student: student,
      task: task,
      submission: submission
    } do
      assert {:error, {:redirect, %{to: "/"}}} =
               conn
               |> log_in_user(student)
               |> live(~p"/tasks/#{task.id}/grade/#{submission.id}")
    end

    test "teacher cannot grade submission from another teacher's task", %{
      conn: conn,
      student: student,
      task: task,
      submission: submission
    } do
      other_teacher = user_fixture(%{role: "teacher", email: "other@teacher.com"})

      # Other teacher tries to grade (task was created by first teacher)
      assert_raise Ecto.NoResultsError, fn ->
        conn
        |> log_in_user(other_teacher)
        |> live(~p"/tasks/#{task.id}/grade/#{submission.id}")
      end
    end

    test "admin can grade any submission", %{
      conn: conn,
      student: student,
      task: task,
      submission: submission
    } do
      admin = user_fixture(%{role: "admin", email: "admin@test.com"})

      {:ok, view, html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/tasks/#{task.id}/grade/#{submission.id}")

      assert html =~ "Grade Submission"
      assert html =~ "student@test.com"

      # Admin can grade
      view
      |> form("#grade-form", %{points: "100", feedback: "Perfect!"})
      |> render_submit()

      admin_scope = Tasky.Accounts.Scope.for_user(admin)
      graded_submission = Tasky.Tasks.get_submission!(admin_scope, submission.id)
      assert graded_submission.points == 100
      assert graded_submission.graded_by_id == admin.id
    end

    test "validates submission belongs to the task", %{
      conn: conn,
      teacher: teacher,
      student: student,
      submission: submission
    } do
      # Create a different task
      other_task = task_fixture(teacher, %{name: "Other Task"})

      # Try to grade with mismatched task_id and submission_id
      assert_raise Ecto.NoResultsError, fn ->
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{other_task.id}/grade/#{submission.id}")
      end
    end

    test "displays graded_by information for already graded submissions", %{
      conn: conn,
      teacher: teacher,
      task: task,
      submission: submission
    } do
      # Grade the submission
      teacher_scope = Tasky.Accounts.Scope.for_user(teacher)

      {:ok, _} =
        Tasky.Tasks.grade_submission(teacher_scope, submission.id, %{
          points: 88,
          feedback: "Well done!"
        })

      # View the grading page
      {:ok, _view, html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/tasks/#{task.id}/grade/#{submission.id}")

      assert html =~ "Previously Graded"
      assert html =~ teacher.email
    end
  end
end
