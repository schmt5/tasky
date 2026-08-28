defmodule Tasky.StudentDirectoryTest do
  @moduledoc """
  The organization boundary of the teacher-facing student directory
  (`Tasky.Accounts.list_students/2` and friends).
  """
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.ClassesFixtures
  import Tasky.OrganizationsFixtures

  alias Tasky.Accounts
  alias Tasky.Accounts.Scope

  defp scope_for(user), do: Scope.for_user(user)

  describe "list_students/2" do
    test "a teacher sees only the students of their own organization" do
      own_org = organization_fixture()
      other_org = organization_fixture()

      own_class = class_fixture(%{organization_id: own_org.id})
      other_class = class_fixture(%{organization_id: other_org.id})

      teacher = user_fixture(%{role: "teacher", organization_id: own_org.id})
      mine = user_fixture(%{role: "student", class_id: own_class.id})
      theirs = user_fixture(%{role: "student", class_id: other_class.id})

      ids = teacher |> scope_for() |> Accounts.list_students() |> Enum.map(& &1.id)

      assert mine.id in ids
      refute theirs.id in ids
    end

    test "teachers and admins are never listed, only students" do
      org = organization_fixture()
      class = class_fixture(%{organization_id: org.id})

      teacher = user_fixture(%{role: "teacher", organization_id: org.id})
      colleague = user_fixture(%{role: "teacher", organization_id: org.id})
      student = user_fixture(%{role: "student", class_id: class.id})

      ids = teacher |> scope_for() |> Accounts.list_students() |> Enum.map(& &1.id)

      assert ids == [student.id]
      refute colleague.id in ids
    end

    test "a teacher without an organization sees nobody" do
      class = class_fixture()
      user_fixture(%{role: "student", class_id: class.id})
      teacher = user_fixture(%{role: "teacher", organization_id: nil})

      assert teacher |> scope_for() |> Accounts.list_students() == []
    end

    test "an admin sees students across organizations" do
      class_a = class_fixture(%{organization_id: organization_fixture().id})
      class_b = class_fixture(%{organization_id: organization_fixture().id})

      a = user_fixture(%{role: "student", class_id: class_a.id})
      b = user_fixture(%{role: "student", class_id: class_b.id})
      admin = user_fixture(%{role: "admin"})

      ids = admin |> scope_for() |> Accounts.list_students() |> Enum.map(& &1.id)

      assert a.id in ids
      assert b.id in ids
    end

    test "the class filter narrows within the organization" do
      org = organization_fixture()
      class_one = class_fixture(%{organization_id: org.id})
      class_two = class_fixture(%{organization_id: org.id})

      teacher = user_fixture(%{role: "teacher", organization_id: org.id})
      in_one = user_fixture(%{role: "student", class_id: class_one.id})
      in_two = user_fixture(%{role: "student", class_id: class_two.id})

      ids =
        teacher
        |> scope_for()
        |> Accounts.list_students(class_id: class_one.id)
        |> Enum.map(& &1.id)

      assert ids == [in_one.id]
      refute in_two.id in ids
    end

    test "the search filter matches name and email" do
      org = organization_fixture()
      class = class_fixture(%{organization_id: org.id})
      teacher = user_fixture(%{role: "teacher", organization_id: org.id})

      hit = user_fixture(%{role: "student", class_id: class.id, firstname: "Zoraida"})
      miss = user_fixture(%{role: "student", class_id: class.id, firstname: "Bruno"})

      ids =
        teacher |> scope_for() |> Accounts.list_students(search: "Zorai") |> Enum.map(& &1.id)

      assert ids == [hit.id]
      refute miss.id in ids
    end
  end

  describe "get_student!/2" do
    test "a foreign student raises, so it looks like a missing one" do
      teacher = user_fixture(%{role: "teacher", organization_id: organization_fixture().id})
      other_class = class_fixture(%{organization_id: organization_fixture().id})
      foreign = user_fixture(%{role: "student", class_id: other_class.id})

      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_student!(scope_for(teacher), foreign.id)
      end
    end

    test "a teacher may not reach a colleague through this path" do
      org = organization_fixture()
      teacher = user_fixture(%{role: "teacher", organization_id: org.id})
      colleague = user_fixture(%{role: "teacher", organization_id: org.id})

      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_student!(scope_for(teacher), colleague.id)
      end
    end
  end

  describe "update_student/3" do
    test "a teacher edits a student of their own organization" do
      org = organization_fixture()
      class = class_fixture(%{organization_id: org.id})
      teacher = user_fixture(%{role: "teacher", organization_id: org.id})
      student = user_fixture(%{role: "student", class_id: class.id})

      assert {:ok, updated} =
               Accounts.update_student(scope_for(teacher), student, %{
                 "firstname" => "Neu",
                 "lastname" => "Name"
               })

      assert updated.firstname == "Neu"
      assert updated.lastname == "Name"
    end

    test "a teacher may move a student between classes of their own organization" do
      org = organization_fixture()
      from = class_fixture(%{organization_id: org.id})
      to = class_fixture(%{organization_id: org.id})
      teacher = user_fixture(%{role: "teacher", organization_id: org.id})
      student = user_fixture(%{role: "student", class_id: from.id})

      assert {:ok, updated} =
               Accounts.update_student(scope_for(teacher), student, %{
                 "class_id" => Integer.to_string(to.id)
               })

      assert updated.class_id == to.id
    end

    test "a teacher may not move a student into another organization's class" do
      org = organization_fixture()
      class = class_fixture(%{organization_id: org.id})
      foreign_class = class_fixture(%{organization_id: organization_fixture().id})

      teacher = user_fixture(%{role: "teacher", organization_id: org.id})
      student = user_fixture(%{role: "student", class_id: class.id})

      assert {:error, :unauthorized} =
               Accounts.update_student(scope_for(teacher), student, %{
                 "class_id" => Integer.to_string(foreign_class.id)
               })

      assert Tasky.Repo.get!(Tasky.Accounts.User, student.id).class_id == class.id
    end

    test "a teacher may not edit a student of another organization" do
      teacher = user_fixture(%{role: "teacher", organization_id: organization_fixture().id})
      foreign_class = class_fixture(%{organization_id: organization_fixture().id})
      foreign = user_fixture(%{role: "student", class_id: foreign_class.id})

      assert {:error, :unauthorized} =
               Accounts.update_student(scope_for(teacher), foreign, %{"firstname" => "Gekapert"})
    end

    test "a teacher may not edit a colleague through this path" do
      org = organization_fixture()
      teacher = user_fixture(%{role: "teacher", organization_id: org.id})
      colleague = user_fixture(%{role: "teacher", organization_id: org.id})

      assert {:error, :unauthorized} =
               Accounts.update_student(scope_for(teacher), colleague, %{"firstname" => "Nope"})
    end

    test "an organization_id in the params is ignored, not honoured" do
      org = organization_fixture()
      other_org = organization_fixture()
      class = class_fixture(%{organization_id: org.id})
      teacher = user_fixture(%{role: "teacher", organization_id: org.id})
      student = user_fixture(%{role: "student", class_id: class.id})

      assert {:ok, updated} =
               Accounts.update_student(scope_for(teacher), student, %{
                 "firstname" => "Egal",
                 "organization_id" => Integer.to_string(other_org.id)
               })

      assert updated.organization_id == nil
    end
  end

  describe "reset_student_password/3" do
    test "a teacher resets the password of their own student and kills its sessions" do
      org = organization_fixture()
      class = class_fixture(%{organization_id: org.id})
      teacher = user_fixture(%{role: "teacher", organization_id: org.id})
      student = user_fixture(%{role: "student", class_id: class.id})

      _token = Accounts.generate_user_session_token(student)

      assert {:ok, {updated, expired_tokens}} =
               Accounts.reset_student_password(
                 scope_for(teacher),
                 student,
                 "ein-neues-passwort-123"
               )

      assert Accounts.get_user_by_email_and_password(updated.email, "ein-neues-passwort-123")
      assert expired_tokens != []
    end

    test "a teacher may not reset the password of a foreign student" do
      teacher = user_fixture(%{role: "teacher", organization_id: organization_fixture().id})
      foreign_class = class_fixture(%{organization_id: organization_fixture().id})
      foreign = user_fixture(%{role: "student", class_id: foreign_class.id})

      assert {:error, :unauthorized} =
               Accounts.reset_student_password(scope_for(teacher), foreign, "egal-egal-1234")
    end
  end
end
