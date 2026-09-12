defmodule Tasky.StudentDeleteTest do
  @moduledoc """
  Deleting a learner's account (`Tasky.Accounts.delete_student/2`) and the
  inventory a teacher sees before confirming it
  (`Tasky.Accounts.student_data_summary/2`).

  The driving scenario is a learner who registered twice: one of the two
  accounts has to go, and nothing of the *other* one may move.
  """
  use Tasky.DataCase, async: false

  alias Tasky.Accounts
  alias Tasky.Accounts.Scope
  alias Tasky.Accounts.User
  alias Tasky.Courses.CourseEnrollment
  alias Tasky.Exams.ExamSubmission
  alias Tasky.Tasks.TaskSubmission
  alias Tasky.Uploads

  import Tasky.AccountsFixtures
  import Tasky.ClassesFixtures
  import Tasky.CoursesFixtures
  import Tasky.ExamsFixtures
  import Tasky.OrganizationsFixtures
  import Tasky.TasksFixtures

  setup do
    dir = Path.join(System.tmp_dir!(), "tasky_uploads_test_#{System.unique_integer([:positive])}")
    prev = Application.get_env(:tasky, :uploads_dir)
    Application.put_env(:tasky, :uploads_dir, dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if prev, do: Application.put_env(:tasky, :uploads_dir, prev)
    end)

    org = organization_fixture()
    class = class_fixture(%{organization_id: org.id})
    teacher = user_fixture(%{role: "teacher", organization_id: org.id})

    %{
      dir: dir,
      org: org,
      class: class,
      teacher: teacher,
      scope: Scope.for_user(teacher),
      student: user_fixture(%{role: "student", class_id: class.id})
    }
  end

  defp foreign_student do
    class = class_fixture(%{organization_id: organization_fixture().id})
    user_fixture(%{role: "student", class_id: class.id})
  end

  defp tmp_file(content) do
    path = Path.join(System.tmp_dir!(), "upload_src_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  # A learner's submission on one of the teacher's units, carrying one answer
  # file — the only bytes a user delete can orphan.
  defp submission_with_file(teacher_scope, student, position \\ 0) do
    course = course_fixture(scope: teacher_scope, attrs: %{name: "Kurs #{position}"})

    task =
      task_fixture(teacher_scope, %{
        name: "Einheit #{position}",
        position: position,
        course_id: course.id
      })

    {:ok, submission} = Tasky.Tasks.get_or_create_submission(Scope.for_user(student), task.id)

    {:ok, stored} =
      Uploads.save_task_submission_file(
        task.id,
        submission.id,
        tmp_file("antwort-bytes"),
        "antwort.pdf",
        ["pdf"]
      )

    %{course: course, task: task, submission: submission, stored: stored.stored_filename}
  end

  describe "student_data_summary/2" do
    test "a duplicate account with nothing on it reports all zeroes", %{
      scope: scope,
      student: student
    } do
      assert {:ok, summary} = Accounts.student_data_summary(scope, student)

      assert summary == %{task_submissions: 0, exam_submissions: 0, course_enrollments: 0}
    end

    test "counts what actually hangs off the account", %{scope: scope, student: student} do
      submission_with_file(scope, student, 0)
      submission_with_file(scope, student, 1)

      course = course_fixture(scope: scope, attrs: %{name: "Eingeschrieben"})
      {:ok, _} = Tasky.Courses.enroll_student(course.id, student.id)

      exam = exam_fixture(scope: scope, status: "running", participation_mode: "assigned")
      assigned_submission_fixture(exam, student)

      assert {:ok, summary} = Accounts.student_data_summary(scope, student)

      assert summary == %{task_submissions: 2, exam_submissions: 1, course_enrollments: 1}
    end

    test "counts only this learner's rows, not a namesake's", %{scope: scope, class: class} do
      keep = user_fixture(%{role: "student", class_id: class.id})
      duplicate = user_fixture(%{role: "student", class_id: class.id})

      submission_with_file(scope, keep, 0)

      assert {:ok, %{task_submissions: 1}} = Accounts.student_data_summary(scope, keep)
      assert {:ok, %{task_submissions: 0}} = Accounts.student_data_summary(scope, duplicate)
    end

    test "a foreign student is refused", %{scope: scope} do
      assert {:error, :unauthorized} = Accounts.student_data_summary(scope, foreign_student())
    end
  end

  describe "delete_student/2" do
    test "a teacher deletes a learner of their own organization", %{
      scope: scope,
      student: student
    } do
      assert {:ok, _deleted} = Accounts.delete_student(scope, student)

      refute Repo.get(User, student.id)
    end

    test "the learner's sessions are gone with the row", %{scope: scope, student: student} do
      token = Accounts.generate_user_session_token(student)

      assert {:ok, _} = Accounts.delete_student(scope, student)

      refute Accounts.get_user_by_session_token(token)
    end

    test "learning-unit submissions and enrolments go, exam submissions stay", %{
      scope: scope,
      student: student
    } do
      %{submission: submission} = submission_with_file(scope, student)

      course = course_fixture(scope: scope, attrs: %{name: "Eingeschrieben"})
      {:ok, enrollment} = Tasky.Courses.enroll_student(course.id, student.id)

      exam = exam_fixture(scope: scope, status: "running", participation_mode: "assigned")
      exam_submission = assigned_submission_fixture(exam, student)

      assert {:ok, _} = Accounts.delete_student(scope, student)

      refute Repo.get(TaskSubmission, submission.id)
      refute Repo.get(CourseEnrollment, enrollment.id)

      # Nilified, not cascaded: the copied name and email are what keep a
      # graded exam gradable after the account behind it is gone.
      kept = Repo.get(ExamSubmission, exam_submission.id)
      assert kept
      assert kept.user_id == nil
      assert kept.email == student.email
    end

    test "the stored answer files are cleared, not orphaned", %{scope: scope, student: student} do
      one = submission_with_file(scope, student, 0)
      two = submission_with_file(scope, student, 1)

      for s <- [one, two] do
        assert {:ok, {:file, _}} =
                 Uploads.fetch_task_submission_file(s.task.id, s.submission.id, s.stored)
      end

      assert {:ok, _} = Accounts.delete_student(scope, student)

      # The cascade removes the rows; these assertions are about the bytes,
      # which no foreign key would have reached.
      for s <- [one, two] do
        assert {:error, :not_found} =
                 Uploads.fetch_task_submission_file(s.task.id, s.submission.id, s.stored)
      end
    end

    test "leaves no submission directory behind", %{dir: dir, scope: scope, student: student} do
      %{task: task, submission: submission} = submission_with_file(scope, student)

      path =
        Path.join([dir, "tasks", to_string(task.id), "submissions", to_string(submission.id)])

      assert File.dir?(path)

      assert {:ok, _} = Accounts.delete_student(scope, student)

      refute File.exists?(path)
      # The unit itself is untouched — it belongs to the teacher, not the learner.
      assert File.dir?(Path.join([dir, "tasks", to_string(task.id)]))
      assert Repo.get(Tasky.Tasks.Task, task.id)
    end

    test "does not touch another learner's submission files", %{scope: scope, class: class} do
      doomed = user_fixture(%{role: "student", class_id: class.id})
      kept = user_fixture(%{role: "student", class_id: class.id})

      gone = submission_with_file(scope, doomed, 0)
      stays = submission_with_file(scope, kept, 1)

      assert {:ok, _} = Accounts.delete_student(scope, doomed)

      assert {:error, :not_found} =
               Uploads.fetch_task_submission_file(gone.task.id, gone.submission.id, gone.stored)

      assert {:ok, {:file, _}} =
               Uploads.fetch_task_submission_file(
                 stays.task.id,
                 stays.submission.id,
                 stays.stored
               )

      assert Repo.get(User, kept.id)
      assert Repo.get(TaskSubmission, stays.submission.id)
    end

    test "a teacher may not delete a foreign student", %{scope: scope} do
      foreign = foreign_student()

      assert {:error, :unauthorized} = Accounts.delete_student(scope, foreign)
      assert Repo.get(User, foreign.id)
    end

    test "a teacher without an organization may delete nobody", %{student: student} do
      lonely = user_fixture(%{role: "teacher", organization_id: nil})

      assert {:error, :unauthorized} =
               Accounts.delete_student(Scope.for_user(lonely), student)

      assert Repo.get(User, student.id)
    end

    # The guard that keeps the courses.teacher_id / exams.teacher_id cascades
    # out of reach: they would take a colleague's whole course and every
    # participant's exam submission with them.
    test "a colleague's account is refused, not deleted", %{scope: scope, org: org} do
      colleague = user_fixture(%{role: "teacher", organization_id: org.id})

      assert {:error, :unauthorized} = Accounts.delete_student(scope, colleague)
      assert Repo.get(User, colleague.id)
    end

    test "a teacher cannot delete themselves through this path", %{
      scope: scope,
      teacher: teacher
    } do
      assert {:error, :unauthorized} = Accounts.delete_student(scope, teacher)
      assert Repo.get(User, teacher.id)
    end

    test "an admin's account is refused too", %{scope: scope} do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} = Accounts.delete_student(scope, admin)
      assert Repo.get(User, admin.id)
    end

    test "an admin may delete a student of any organization" do
      admin = user_fixture(%{role: "admin"})
      foreign = foreign_student()

      assert {:ok, _} = Accounts.delete_student(Scope.for_user(admin), foreign)
      refute Repo.get(User, foreign.id)
    end
  end
end
