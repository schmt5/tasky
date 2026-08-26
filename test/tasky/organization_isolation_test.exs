defmodule Tasky.OrganizationIsolationTest do
  @moduledoc """
  The cross-organization boundary on the paths where ids arrive off the wire.

  Filtering the pickers only cleans up the modals — these event handlers are
  directly reachable, so the rule has to hold in the context. Each of these
  derives the organization from the **owner** of the course or exam rather than
  from a caller scope, which is why the checks also hold when an admin (who has
  no organization) performs the action.
  """

  use Tasky.DataCase, async: true

  alias Tasky.Courses
  alias Tasky.Exams

  import Tasky.AccountsFixtures
  import Tasky.ClassesFixtures
  import Tasky.CoursesFixtures
  import Tasky.ExamsFixtures
  import Tasky.OrganizationsFixtures

  defp teacher_in(organization) do
    user_scope_fixture(user_fixture(%{role: "teacher", organization_id: organization.id}))
  end

  defp student_in(organization) do
    class = class_fixture(%{organization_id: organization.id})
    user_fixture(%{role: "student", class_id: class.id})
  end

  describe "Courses.enroll_student/2" do
    setup do
      organization = organization_fixture()
      scope = teacher_in(organization)
      %{organization: organization, scope: scope, course: course_fixture(scope: scope)}
    end

    test "enrolls a student of the owner's organization", %{
      organization: organization,
      course: course
    } do
      student = student_in(organization)

      assert {:ok, _} = Courses.enroll_student(course.id, student.id)
    end

    test "refuses a student of another organization", %{course: course} do
      foreign = student_in(organization_fixture())

      assert {:error, :different_organization} = Courses.enroll_student(course.id, foreign.id)
    end

    test "refuses a student without a class, who belongs to no organization", %{course: course} do
      classless = user_fixture(%{role: "student", class_id: nil})

      assert {:error, :different_organization} = Courses.enroll_student(course.id, classless.id)
    end

    test "refuses everyone when the course owner has no organization" do
      orphan_scope = user_scope_fixture(user_fixture(%{role: "teacher", organization_id: nil}))
      course = course_fixture(scope: orphan_scope)
      student = student_in(organization_fixture())

      assert {:error, :different_organization} = Courses.enroll_student(course.id, student.id)
    end

    test "refuses a teacher or admin id, not just a foreign student", %{course: course} do
      teacher = user_fixture(%{role: "teacher"})

      assert {:error, :different_organization} = Courses.enroll_student(course.id, teacher.id)
    end
  end

  describe "Courses.list_unenrolled_students/2" do
    test "lists only students of the owner's organization" do
      organization = organization_fixture()
      scope = teacher_in(organization)
      course = course_fixture(scope: scope)

      mine = student_in(organization)
      foreign = student_in(organization_fixture())
      classless = user_fixture(%{role: "student", class_id: nil})

      ids = Enum.map(Courses.list_unenrolled_students(course.id), & &1.id)

      assert mine.id in ids
      refute foreign.id in ids
      refute classless.id in ids
    end

    test "narrows to one class without leaving the organization" do
      organization = organization_fixture()
      scope = teacher_in(organization)
      course = course_fixture(scope: scope)

      class = class_fixture(%{organization_id: organization.id})
      inside = user_fixture(%{role: "student", class_id: class.id})
      other_class_student = student_in(organization)

      ids = Enum.map(Courses.list_unenrolled_students(course.id, class.id), & &1.id)

      assert ids == [inside.id]
      refute other_class_student.id in ids
    end

    test "is empty when the owner has no organization" do
      orphan_scope = user_scope_fixture(user_fixture(%{role: "teacher", organization_id: nil}))
      course = course_fixture(scope: orphan_scope)
      student_in(organization_fixture())

      assert Courses.list_unenrolled_students(course.id) == []
    end
  end

  describe "Exams.assign_student/3" do
    setup do
      organization = organization_fixture()
      scope = teacher_in(organization)

      exam =
        exam_fixture(scope: scope, status: "open", participation_mode: "assigned")

      %{organization: organization, scope: scope, exam: exam}
    end

    test "assigns a student of the owner's organization", %{
      organization: organization,
      scope: scope,
      exam: exam
    } do
      student = student_in(organization)

      assert {:ok, _submission} = Exams.assign_student(scope, exam, student.id)
    end

    test "refuses a student of another organization", %{scope: scope, exam: exam} do
      foreign = student_in(organization_fixture())

      assert {:error, :different_organization} = Exams.assign_student(scope, exam, foreign.id)
    end

    test "refuses a student without a class", %{scope: scope, exam: exam} do
      classless = user_fixture(%{role: "student", class_id: nil})

      assert {:error, :different_organization} = Exams.assign_student(scope, exam, classless.id)
    end

    test "still refuses a non-student outright", %{scope: scope, exam: exam} do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :not_a_student} = Exams.assign_student(scope, exam, admin.id)
    end
  end

  describe "Exams.list_assignable_students/2" do
    test "lists only students of the owner's organization" do
      organization = organization_fixture()
      scope = teacher_in(organization)
      exam = exam_fixture(scope: scope, status: "open", participation_mode: "assigned")

      mine = student_in(organization)
      foreign = student_in(organization_fixture())
      classless = user_fixture(%{role: "student", class_id: nil})

      ids = Enum.map(Exams.list_assignable_students(exam), & &1.id)

      assert mine.id in ids
      refute foreign.id in ids
      refute classless.id in ids
    end

    test "assign_students_from_class assigns nobody from a foreign class" do
      organization = organization_fixture()
      scope = teacher_in(organization)
      exam = exam_fixture(scope: scope, status: "open", participation_mode: "assigned")

      foreign_org = organization_fixture()
      foreign_class = class_fixture(%{organization_id: foreign_org.id})
      user_fixture(%{role: "student", class_id: foreign_class.id})

      assert {:ok, %{assigned: 0, skipped: 0}} =
               Exams.assign_students_from_class(scope, exam, foreign_class.id)
    end
  end
end
