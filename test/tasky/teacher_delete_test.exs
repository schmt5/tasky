defmodule Tasky.TeacherDeleteTest do
  @moduledoc """
  Deleting a teacher's account (`Tasky.Accounts.delete_teacher/2`) and the
  inventory an admin sees before confirming it
  (`Tasky.Accounts.teacher_deletion_summary/2`).

  Everything the teacher owns goes, except the courses published to the
  catalog: those move to the deleting admin with their units intact.
  """
  # Not async: Tasky.ProbeStorage swaps the storage adapter for the whole VM.
  use Tasky.DataCase, async: false

  alias Tasky.Accounts
  alias Tasky.Accounts.Scope
  alias Tasky.Accounts.User
  alias Tasky.Courses.Course
  alias Tasky.Courses.CourseEnrollment
  alias Tasky.Exams.Exam
  alias Tasky.Tasks.Task
  alias Tasky.Tasks.TaskSubmission
  alias Tasky.Uploads

  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.ExamsFixtures
  import Tasky.TasksFixtures

  @png_bytes <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "fake-image-data">>

  setup do
    admin = user_fixture(%{role: "admin"})
    teacher = user_fixture(%{role: "teacher"})

    %{
      dir: Uploads.dir(),
      admin: admin,
      admin_scope: Scope.for_user(admin),
      teacher: teacher,
      scope: Scope.for_user(teacher)
    }
  end

  defp tmp_file(content) do
    path = Path.join(System.tmp_dir!(), "upload_src_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp unit_with_image(scope, attrs) do
    task = task_fixture(scope, Map.merge(%{name: "Einheit", position: 0}, attrs))

    upload = %Plug.Upload{
      path: tmp_file(@png_bytes),
      content_type: "image/png",
      filename: "bild.png"
    }

    {:ok, url} = Uploads.save_task_image(task.id, upload)
    {task, url |> String.split("/") |> List.last()}
  end

  defp exam_with_attachment(scope) do
    exam = exam_fixture(scope: scope, status: "running")
    {:ok, stored} = Uploads.save_exam_attachment(exam.id, tmp_file("bytes"), "blatt.pdf")
    {exam, stored.stored_filename}
  end

  defp submit(task, student) do
    {:ok, submission} = Tasky.Tasks.get_or_create_submission(Scope.for_user(student), task.id)
    submission
  end

  describe "delete_teacher/2 authorization" do
    test "a teacher may not delete a colleague", %{teacher: teacher} do
      colleague = user_fixture(%{role: "teacher"})

      assert {:error, :unauthorized} =
               Accounts.delete_teacher(Scope.for_user(colleague), teacher)

      assert Repo.get(User, teacher.id)
    end

    test "only teachers can be deleted from here", %{admin_scope: admin_scope, admin: admin} do
      student = user_fixture(%{role: "student"})
      other_admin = user_fixture(%{role: "admin"})

      for target <- [student, other_admin, admin] do
        assert {:error, :unauthorized} = Accounts.delete_teacher(admin_scope, target)
        assert Repo.get(User, target.id)
      end
    end
  end

  describe "delete_teacher/2" do
    test "removes an unpublished course with its units, enrolments and files", %{
      admin_scope: admin_scope,
      scope: scope,
      teacher: teacher,
      dir: dir
    } do
      course = course_fixture(scope: scope)
      {task, image} = unit_with_image(scope, %{course_id: course.id})
      student = user_fixture(%{role: "student"})
      enroll_fixture(course, student)
      submit(task, student)

      assert {:ok, %{transferred: 0, tasks_deleted: 1}} =
               Accounts.delete_teacher(admin_scope, teacher)

      refute Repo.get(User, teacher.id)
      refute Repo.get(Course, course.id)
      refute Repo.get(Task, task.id)
      refute Repo.get_by(CourseEnrollment, course_id: course.id)
      assert {:error, :not_found} = Uploads.fetch_task_image(task.id, image)
      refute File.exists?(Path.join([dir, "tasks", to_string(task.id)]))
      # The learner stays.
      assert Repo.get(User, student.id)
    end

    test "hands a published course with its units, enrolments and submissions to the admin",
         %{admin_scope: admin_scope, admin: admin, scope: scope, teacher: teacher} do
      course = course_fixture(scope: scope, attrs: %{name: "Im Katalog"})
      {task, image} = unit_with_image(scope, %{course_id: course.id})
      course = catalog_course_fixture(scope: scope, course: course)
      student = user_fixture(%{role: "student"})
      enroll_fixture(course, student)
      submission = submit(task, student)

      assert {:ok, %{transferred: 1, tasks_deleted: 0}} =
               Accounts.delete_teacher(admin_scope, teacher)

      assert %Course{teacher_id: admin_id} = Repo.get(Course, course.id)
      assert admin_id == admin.id
      assert %Task{user_id: ^admin_id} = Repo.get(Task, task.id)
      assert Repo.get_by(CourseEnrollment, course_id: course.id, student_id: student.id)
      assert Repo.get(TaskSubmission, submission.id)
      assert {:ok, {{:file, _}, _}} = Uploads.fetch_task_image(task.id, image)
    end

    test "a unit of the teacher in a colleague's course stays with that course", %{
      admin_scope: admin_scope,
      teacher: teacher
    } do
      colleague = user_fixture(%{role: "teacher"})
      course = course_fixture(scope: Scope.for_user(colleague))
      # As if the teacher had written it there; the API only allows this to admins.
      {task, _image} = unit_with_image(Scope.for_user(colleague), %{course_id: course.id})
      Repo.update_all(where(Task, [t], t.id == ^task.id), set: [user_id: teacher.id])

      assert {:ok, _} = Accounts.delete_teacher(admin_scope, teacher)

      colleague_id = colleague.id
      assert %Task{user_id: ^colleague_id} = Repo.get(Task, task.id)
    end

    test "removes a unit that belongs to no course", %{
      admin_scope: admin_scope,
      scope: scope,
      teacher: teacher
    } do
      {task, image} = unit_with_image(scope, %{})

      assert {:ok, %{tasks_deleted: 1}} = Accounts.delete_teacher(admin_scope, teacher)

      refute Repo.get(Task, task.id)
      assert {:error, :not_found} = Uploads.fetch_task_image(task.id, image)
    end

    test "removes exams with submissions and their files", %{
      admin_scope: admin_scope,
      scope: scope,
      teacher: teacher,
      dir: dir
    } do
      {exam, stored} = exam_with_attachment(scope)
      exam_submission_fixture(exam)

      assert {:ok, %{exams_deleted: 1}} = Accounts.delete_teacher(admin_scope, teacher)

      refute Repo.get(Exam, exam.id)
      assert {:error, _} = Uploads.fetch_attachment(exam.id, stored)
      refute File.exists?(Path.join([dir, "exams", to_string(exam.id)]))
    end

    test "returns the session tokens so the caller can disconnect them", %{
      admin_scope: admin_scope,
      teacher: teacher
    } do
      token = Accounts.generate_user_session_token(teacher)

      assert {:ok, %{expired_tokens: [%{token: ^token}]}} =
               Accounts.delete_teacher(admin_scope, teacher)

      refute Accounts.get_user_by_session_token(token)
    end

    test "leaves another teacher's data alone", %{
      admin_scope: admin_scope,
      teacher: teacher
    } do
      other_scope = Scope.for_user(user_fixture(%{role: "teacher"}))
      course = course_fixture(scope: other_scope)
      {task, image} = unit_with_image(other_scope, %{course_id: course.id})
      exam = exam_fixture(scope: other_scope)

      assert {:ok, _} = Accounts.delete_teacher(admin_scope, teacher)

      assert Repo.get(Course, course.id)
      assert Repo.get(Exam, exam.id)
      assert {:ok, {{:file, _}, _}} = Uploads.fetch_task_image(task.id, image)
    end

    @tag :capture_log
    test "a storage adapter that raises does not fail the delete", %{
      admin_scope: admin_scope,
      scope: scope,
      teacher: teacher
    } do
      unit_with_image(scope, %{})
      exam_with_attachment(scope)
      Tasky.ProbeStorage.install(delete_prefix_result: :raise)

      assert {:ok, _} = Accounts.delete_teacher(admin_scope, teacher)
      refute Repo.get(User, teacher.id)
    end
  end

  describe "teacher_deletion_summary/2" do
    test "counts what goes and lists what is handed over", %{
      admin_scope: admin_scope,
      scope: scope,
      teacher: teacher
    } do
      doomed = course_fixture(scope: scope, attrs: %{name: "Weg"})
      {task, _} = unit_with_image(scope, %{course_id: doomed.id})
      unit_with_image(scope, %{name: "Lose"})

      published = catalog_course_fixture(scope: scope)

      one = user_fixture(%{role: "student"})
      two = user_fixture(%{role: "student"})
      enroll_fixture(doomed, one)
      submit(task, two)
      # Enrolled in a surviving course only: not affected.
      enroll_fixture(published, user_fixture(%{role: "student"}))

      exam = exam_fixture(scope: scope, status: "running", participation_mode: "assigned")
      assigned_submission_fixture(exam, one)
      exam_submission_fixture(exam_fixture(scope: scope, status: "running"))

      assert {:ok, summary} = Accounts.teacher_deletion_summary(admin_scope, teacher)

      assert summary.courses_deleted == 1
      assert summary.tasks_deleted == 2
      assert summary.exams_deleted == 2
      assert summary.exam_submissions_deleted == 2
      assert summary.learners_affected == 2

      assert [%{id: id, unit_count: 1}] = summary.courses_transferred
      assert id == published.id
    end

    test "is for admins only", %{scope: scope, teacher: teacher} do
      colleague = user_fixture(%{role: "teacher"})

      assert {:error, :unauthorized} =
               Accounts.teacher_deletion_summary(Scope.for_user(colleague), teacher)

      assert {:error, :unauthorized} = Accounts.teacher_deletion_summary(scope, teacher)
    end
  end
end
