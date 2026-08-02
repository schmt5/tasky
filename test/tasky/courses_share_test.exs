defmodule Tasky.CoursesShareTest do
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures

  alias Tasky.Courses

  setup do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    %{scope: scope, course: course_fixture(scope: scope)}
  end

  describe "ensure_share_slug/2" do
    test "generates an unguessable slug on first use", %{scope: scope, course: course} do
      refute course.share_slug

      assert {:ok, shared} = Courses.ensure_share_slug(scope, course)
      assert is_binary(shared.share_slug)
      assert byte_size(shared.share_slug) >= 22
    end

    test "is idempotent so a shared link stays valid", %{scope: scope, course: course} do
      {:ok, first} = Courses.ensure_share_slug(scope, course)
      {:ok, second} = Courses.ensure_share_slug(scope, first)

      assert second.share_slug == first.share_slug
    end

    test "gives different courses different slugs", %{scope: scope, course: course} do
      {:ok, first} = Courses.ensure_share_slug(scope, course)
      {:ok, second} = Courses.ensure_share_slug(scope, course_fixture(scope: scope))

      refute first.share_slug == second.share_slug
    end

    test "refuses a course owned by someone else", %{course: course} do
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} = Courses.ensure_share_slug(other, course)
      refute Repo.reload(course).share_slug
    end

    test "an admin may share any course", %{course: course} do
      admin = user_scope_fixture(user_fixture(%{role: "admin"}))

      assert {:ok, shared} = Courses.ensure_share_slug(admin, course)
      assert shared.share_slug
    end
  end

  describe "get_course_by_share_slug/1" do
    test "finds the course behind a slug", %{scope: scope, course: course} do
      {:ok, shared} = Courses.ensure_share_slug(scope, course)

      found = Courses.get_course_by_share_slug(shared.share_slug)

      assert found.id == course.id
      assert found.teacher.id == scope.user.id
    end

    test "returns nil for unknown, empty and non-string slugs" do
      assert Courses.get_course_by_share_slug("does-not-exist") == nil
      assert Courses.get_course_by_share_slug("") == nil
      assert Courses.get_course_by_share_slug(nil) == nil
    end
  end
end
