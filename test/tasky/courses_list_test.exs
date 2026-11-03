defmodule Tasky.CoursesListTest do
  @moduledoc """
  The course lists count their units in SQL instead of loading every unit's
  document; the counts must still say the same as before.
  """
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Courses
  alias Tasky.Tasks

  defp add_unit(scope, course, name, status) do
    {:ok, task} =
      Tasks.create_task(scope, %{name: name, position: 0, status: status, course_id: course.id})

    task
  end

  setup do
    teacher = user_fixture(%{role: "teacher"})
    scope = Scope.for_user(teacher)
    %{scope: scope}
  end

  test "list_courses/1 counts every unit, an empty course as zero", %{scope: scope} do
    full = course_fixture(scope: scope, attrs: %{name: "Voll"})
    empty = course_fixture(scope: scope, attrs: %{name: "Leer"})
    add_unit(scope, full, "Eins", "open")
    add_unit(scope, full, "Zwei", "draft")

    counts = Map.new(Courses.list_courses(scope), &{&1.id, &1.unit_count})

    assert counts == %{full.id => 2, empty.id => 0}
  end

  test "list_enrolled_courses/1 counts only the units a student can see", %{scope: scope} do
    course = course_fixture(scope: scope)
    add_unit(scope, course, "Offen", "open")
    add_unit(scope, course, "Gesperrt", "locked")
    add_unit(scope, course, "Entwurf", "draft")

    student = user_fixture(%{role: "student"})
    {:ok, _} = Courses.enroll_student(course.id, student.id)

    assert [%{unit_count: 2}] = Courses.list_enrolled_courses(Scope.for_user(student))
  end

  test "list_copy_targets/3 offers the other own courses and flags a name clash",
       %{scope: scope} do
    source = course_fixture(scope: scope, attrs: %{name: "Quelle"})
    clash = course_fixture(scope: scope, attrs: %{name: "Mit Konflikt"})
    free = course_fixture(scope: scope, attrs: %{name: "Ohne Konflikt"})
    _foreign = course_fixture(attrs: %{name: "Fremd"})
    add_unit(scope, clash, "Einheit 1", "open")
    add_unit(scope, clash, "Einheit 2", "open")
    add_unit(scope, free, "Etwas anderes", "open")

    targets =
      Map.new(Courses.list_copy_targets(scope, source, "Einheit 1"), fn t ->
        {t.course.id, {t.course.unit_count, t.conflict}}
      end)

    assert targets == %{clash.id => {2, true}, free.id => {1, false}}
  end
end
