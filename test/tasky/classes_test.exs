defmodule Tasky.ClassesTest do
  use Tasky.DataCase, async: true

  alias Tasky.Classes
  alias Tasky.Organizations

  import Tasky.AccountsFixtures
  import Tasky.ClassesFixtures
  import Tasky.OrganizationsFixtures

  defp org_scope do
    organization = organization_fixture()
    teacher = user_fixture(%{role: "teacher", organization_id: organization.id})
    {organization, user_scope_fixture(teacher)}
  end

  describe "list_classes/1 — organization isolation" do
    test "teachers of one organization share its classes" do
      {organization, scope_a} = org_scope()

      teacher_b = user_fixture(%{role: "teacher", organization_id: organization.id})
      scope_b = user_scope_fixture(teacher_b)

      mpa = class_fixture(%{name: "MPA", organization_id: organization.id})
      da = class_fixture(%{name: "DA", organization_id: organization.id})

      for scope <- [scope_a, scope_b] do
        assert Enum.map(Classes.list_classes(scope), & &1.id) |> Enum.sort() ==
                 Enum.sort([mpa.id, da.id])
      end
    end

    test "a teacher of another organization sees none of them" do
      {organization, _scope} = org_scope()
      class_fixture(%{name: "MPA", organization_id: organization.id})

      {_other_org, other_scope} = org_scope()

      assert Classes.list_classes(other_scope) == []
    end

    test "a teacher without an organization sees nothing" do
      {organization, _scope} = org_scope()
      class_fixture(%{organization_id: organization.id})

      orphan = user_fixture(%{role: "teacher", organization_id: nil})

      assert Classes.list_classes(user_scope_fixture(orphan)) == []
    end

    test "an unfiled class is invisible to every teacher" do
      {_organization, scope} = org_scope()
      class_fixture(%{organization_id: nil})

      assert Classes.list_classes(scope) == []
    end

    test "admins see every organization's classes" do
      {org_a, _scope_a} = org_scope()
      {org_b, _scope_b} = org_scope()

      a = class_fixture(%{organization_id: org_a.id})
      b = class_fixture(%{organization_id: org_b.id})

      admin_scope = user_scope_fixture(user_fixture(%{role: "admin"}))
      ids = Enum.map(Classes.list_classes(admin_scope), & &1.id)

      assert a.id in ids
      assert b.id in ids
    end
  end

  describe "get_class!/2" do
    test "returns a class of the scope's organization" do
      {organization, scope} = org_scope()
      class = class_fixture(%{organization_id: organization.id})

      assert Classes.get_class!(scope, class.id).id == class.id
    end

    test "raises for a class of another organization — a foreign class must look missing" do
      {organization, _scope} = org_scope()
      class = class_fixture(%{organization_id: organization.id})

      {_other_org, other_scope} = org_scope()

      assert_raise Ecto.NoResultsError, fn -> Classes.get_class!(other_scope, class.id) end
    end

    test "raises for a teacher without an organization" do
      {organization, _scope} = org_scope()
      class = class_fixture(%{organization_id: organization.id})

      orphan_scope = user_scope_fixture(user_fixture(%{role: "teacher", organization_id: nil}))

      assert_raise Ecto.NoResultsError, fn -> Classes.get_class!(orphan_scope, class.id) end
    end
  end

  describe "create_class/2" do
    test "files the class under the teacher's organization without it being castable" do
      {organization, scope} = org_scope()
      {_other_org, _} = org_scope()

      assert {:ok, class} = Classes.create_class(scope, %{name: "MPA", organization_id: 999_999})
      assert class.organization_id == organization.id
    end

    test "refuses a teacher who has no organization" do
      orphan_scope = user_scope_fixture(user_fixture(%{role: "teacher", organization_id: nil}))

      assert {:error, :no_organization} = Classes.create_class(orphan_scope, %{name: "MPA"})
    end

    test "an admin names the organization explicitly" do
      organization = organization_fixture()
      admin_scope = user_scope_fixture(user_fixture(%{role: "admin"}))

      assert {:ok, class} =
               Classes.create_class(admin_scope, %{
                 name: "MPA",
                 organization_id: organization.id
               })

      assert class.organization_id == organization.id
    end
  end

  describe "update_class/3 and delete_class/2" do
    test "a teacher may rename a class of their own organization" do
      {organization, scope} = org_scope()
      class = class_fixture(%{organization_id: organization.id})

      assert {:ok, updated} = Classes.update_class(scope, class, %{name: "MPA 2"})
      assert updated.name == "MPA 2"
    end

    test "a teacher cannot move a class to another organization" do
      {organization, scope} = org_scope()
      other = organization_fixture()
      class = class_fixture(%{organization_id: organization.id})

      assert {:ok, updated} =
               Classes.update_class(scope, class, %{name: "MPA", organization_id: other.id})

      assert updated.organization_id == organization.id
    end

    test "a foreign class can be neither renamed nor deleted" do
      {organization, _scope} = org_scope()
      class = class_fixture(%{organization_id: organization.id})

      {_other_org, other_scope} = org_scope()

      assert {:error, :unauthorized} = Classes.update_class(other_scope, class, %{name: "X"})
      assert {:error, :unauthorized} = Classes.delete_class(other_scope, class)
    end

    test "deleting a class of one's own organization works" do
      {organization, scope} = org_scope()
      class = class_fixture(%{organization_id: organization.id})

      assert {:ok, _} = Classes.delete_class(scope, class)
    end
  end

  describe "count_students_per_class/1" do
    test "counts only the scope's own classes" do
      {organization, scope} = org_scope()
      class = class_fixture(%{organization_id: organization.id})
      user_fixture(%{role: "student", class_id: class.id})
      user_fixture(%{role: "student", class_id: class.id})

      {other_org, other_scope} = org_scope()
      other_class = class_fixture(%{organization_id: other_org.id})
      user_fixture(%{role: "student", class_id: other_class.id})

      assert Classes.count_students_per_class(scope) == %{class.id => 2}
      assert Classes.count_students_per_class(other_scope) == %{other_class.id => 1}
    end
  end

  describe "get_class_by_slug/1" do
    test "is deliberately unscoped — the slug is the registration credential" do
      {organization, _scope} = org_scope()
      class = class_fixture(%{name: "MPA", organization_id: organization.id})

      assert Classes.get_class_by_slug(class.slug).id == class.id
    end
  end

  describe "Organizations — student membership is derived from the class" do
    test "a student in a class belongs to that class's organization" do
      organization = organization_fixture()
      class = class_fixture(%{organization_id: organization.id})
      student = user_fixture(%{role: "student", class_id: class.id})

      assert Organizations.student_member?(student.id, organization.id)

      assert Enum.map(Repo.all(Organizations.students_query(organization.id)), & &1.id) == [
               student.id
             ]
    end

    test "a student without a class belongs to no organization" do
      organization = organization_fixture()
      student = user_fixture(%{role: "student", class_id: nil})

      refute Organizations.student_member?(student.id, organization.id)
    end

    test "a student in an unfiled class belongs to no organization" do
      organization = organization_fixture()
      class = class_fixture(%{organization_id: nil})
      student = user_fixture(%{role: "student", class_id: class.id})

      refute Organizations.student_member?(student.id, organization.id)
      assert Repo.all(Organizations.students_query(organization.id)) == []
    end

    test "a nil organization matches nobody" do
      class = class_fixture()
      student = user_fixture(%{role: "student", class_id: class.id})

      refute Organizations.student_member?(student.id, nil)
      assert Repo.all(Organizations.students_query(nil)) == []
    end

    test "teachers of another organization are not members" do
      organization = organization_fixture()
      other = organization_fixture()
      class = class_fixture(%{organization_id: other.id})
      student = user_fixture(%{role: "student", class_id: class.id})

      refute Organizations.student_member?(student.id, organization.id)
    end
  end

  describe "Organizations administration" do
    test "an admin can create, rename and delete" do
      admin_scope = user_scope_fixture(user_fixture(%{role: "admin"}))

      assert {:ok, organization} =
               Organizations.create_organization(admin_scope, %{name: "Schule Bern"})

      assert organization.slug == "schule-bern"
      assert is_binary(organization.invite_token)

      assert {:ok, renamed} =
               Organizations.update_organization(admin_scope, organization, %{name: "Schule Thun"})

      assert renamed.name == "Schule Thun"
      assert renamed.invite_token == organization.invite_token

      assert {:ok, _} = Organizations.delete_organization(admin_scope, renamed)
    end

    test "teachers and students cannot administer organizations" do
      organization = organization_fixture()

      for scope <- [
            user_scope_fixture(user_fixture(%{role: "teacher"})),
            user_scope_fixture(user_fixture(%{role: "student"}))
          ] do
        assert Organizations.list_organizations(scope) == []
        assert Organizations.count_members_per_organization(scope) == %{}
        assert Organizations.count_classes_per_organization(scope) == %{}
        assert {:error, :unauthorized} = Organizations.create_organization(scope, %{name: "X"})
        assert {:error, :unauthorized} = Organizations.delete_organization(scope, organization)
        assert {:error, :unauthorized} = Organizations.rotate_invite_token(scope, organization)

        assert_raise Ecto.NoResultsError, fn ->
          Organizations.get_organization!(scope, organization.id)
        end
      end
    end

    test "deleting an organization unfiles its members and classes rather than deleting them" do
      admin_scope = user_scope_fixture(user_fixture(%{role: "admin"}))
      organization = organization_fixture()
      teacher = user_fixture(%{role: "teacher", organization_id: organization.id})
      class = class_fixture(%{organization_id: organization.id})

      assert {:ok, _} = Organizations.delete_organization(admin_scope, organization)

      assert Repo.get!(Tasky.Accounts.User, teacher.id).organization_id == nil
      assert Repo.get!(Tasky.Classes.Class, class.id).organization_id == nil
    end

    test "counts are grouped per organization" do
      admin_scope = user_scope_fixture(user_fixture(%{role: "admin"}))
      organization = organization_fixture()
      user_fixture(%{role: "teacher", organization_id: organization.id})
      class_fixture(%{organization_id: organization.id})
      class_fixture(%{organization_id: organization.id})

      assert Organizations.count_members_per_organization(admin_scope)[organization.id] == 1
      assert Organizations.count_classes_per_organization(admin_scope)[organization.id] == 2
    end
  end

  describe "invite token" do
    test "resolves an organization, and rotating it invalidates the old link" do
      admin_scope = user_scope_fixture(user_fixture(%{role: "admin"}))
      organization = organization_fixture()
      old_token = organization.invite_token

      assert Organizations.get_organization_by_invite_token(old_token).id == organization.id

      assert {:ok, rotated} = Organizations.rotate_invite_token(admin_scope, organization)
      refute rotated.invite_token == old_token

      assert Organizations.get_organization_by_invite_token(old_token) == nil

      assert Organizations.get_organization_by_invite_token(rotated.invite_token).id ==
               organization.id
    end

    test "an unknown or blank token resolves to nothing" do
      assert Organizations.get_organization_by_invite_token("nope") == nil
      assert Organizations.get_organization_by_invite_token("") == nil
      assert Organizations.get_organization_by_invite_token(nil) == nil
    end
  end
end
