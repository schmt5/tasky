defmodule Tasky.TasksTest do
  use Tasky.DataCase

  alias Tasky.Tasks

  describe "tasks" do
    alias Tasky.Tasks.Task

    import Tasky.AccountsFixtures, only: [user_scope_fixture: 0]
    import Tasky.TasksFixtures

    @invalid_attrs %{name: nil, position: nil, status: nil}

    test "list_tasks/1 returns all scoped tasks" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      task = task_fixture(scope)
      other_task = task_fixture(other_scope)
      assert Tasks.list_tasks(scope) == [task]
      assert Tasks.list_tasks(other_scope) == [other_task]
    end

    test "get_task!/2 returns the task with given id" do
      scope = user_scope_fixture()
      task = task_fixture(scope)
      other_scope = user_scope_fixture()
      assert Tasks.get_task!(scope, task.id) == task
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(other_scope, task.id) end
    end

    test "create_task/2 with valid data creates a task" do
      valid_attrs = %{name: "some name", position: 42, status: "draft"}
      scope = user_scope_fixture()

      assert {:ok, %Task{} = task} = Tasks.create_task(scope, valid_attrs)
      assert task.name == "some name"
      assert task.position == 42
      assert task.status == "draft"
      assert task.user_id == scope.user.id
    end

    test "create_task/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Tasks.create_task(scope, @invalid_attrs)
    end

    test "update_task/3 with valid data updates the task" do
      scope = user_scope_fixture()
      task = task_fixture(scope)

      update_attrs = %{
        name: "some updated name",
        position: 43,
        status: "published"
      }

      assert {:ok, %Task{} = task} = Tasks.update_task(scope, task, update_attrs)
      assert task.name == "some updated name"
      assert task.position == 43
      assert task.status == "published"
    end

    test "update_task/3 with invalid scope returns unauthorized" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      task = task_fixture(scope)

      assert {:error, :unauthorized} = Tasks.update_task(other_scope, task, %{})
    end

    test "update_task/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      task = task_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Tasks.update_task(scope, task, @invalid_attrs)
      assert task == Tasks.get_task!(scope, task.id)
    end

    test "delete_task/2 deletes the task" do
      scope = user_scope_fixture()
      task = task_fixture(scope)
      assert {:ok, %Task{}} = Tasks.delete_task(scope, task)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(scope, task.id) end
    end

    test "delete_task/2 with invalid scope returns unauthorized" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      task = task_fixture(scope)
      assert {:error, :unauthorized} = Tasks.delete_task(other_scope, task)
    end

    test "change_task/2 returns a task changeset" do
      scope = user_scope_fixture()
      task = task_fixture(scope)
      assert %Ecto.Changeset{} = Tasks.change_task(scope, task)
    end
  end

  describe "reorder_tasks/3" do
    import Tasky.AccountsFixtures,
      only: [user_fixture: 1, user_scope_fixture: 0, user_scope_fixture: 1]

    import Tasky.CoursesFixtures
    import Tasky.TasksFixtures

    defp course_with_tasks(count, opts \\ []) do
      scope =
        Keyword.get_lazy(opts, :scope, fn ->
          user_scope_fixture(user_fixture(%{role: "teacher"}))
        end)

      course = course_fixture(scope: scope)

      tasks =
        for i <- 1..count do
          task_fixture(scope, %{name: "Einheit #{i}", position: i - 1, course_id: course.id})
        end

      {scope, course, tasks}
    end

    defp positions(course_id) do
      course_id |> Tasks.list_tasks_by_course() |> Enum.map(&{&1.id, &1.position})
    end

    test "writes dense positions in the given order" do
      {scope, course, [a, b, c]} = course_with_tasks(3)

      assert {:ok, :reordered} = Tasks.reorder_tasks(scope, course.id, [c.id, a.id, b.id])
      assert positions(course.id) == [{c.id, 0}, {a.id, 1}, {b.id, 2}]
    end

    test "normalizes pre-existing nil and duplicate positions" do
      {scope, course, [a, b, c]} = course_with_tasks(3)

      Tasky.Repo.update_all(Tasky.Tasks.Task, set: [position: nil])

      assert {:ok, :reordered} = Tasks.reorder_tasks(scope, course.id, [a.id, b.id, c.id])
      assert positions(course.id) == [{a.id, 0}, {b.id, 1}, {c.id, 2}]
    end

    test "rejects a partial list" do
      {scope, course, [a, b, _c]} = course_with_tasks(3)

      assert {:error, :invalid_order} = Tasks.reorder_tasks(scope, course.id, [a.id, b.id])
    end

    test "rejects duplicate ids" do
      {scope, course, [a, b, _c]} = course_with_tasks(3)

      assert {:error, :invalid_order} = Tasks.reorder_tasks(scope, course.id, [a.id, a.id, b.id])
    end

    test "rejects an id belonging to another course" do
      {scope, course, [a, b, _c]} = course_with_tasks(3)
      {_other_scope, _other_course, [foreign]} = course_with_tasks(1)

      assert {:error, :invalid_order} =
               Tasks.reorder_tasks(scope, course.id, [a.id, b.id, foreign.id])
    end

    test "leaves positions untouched when the order is rejected" do
      {scope, course, [a, b, c]} = course_with_tasks(3)
      before = positions(course.id)

      assert {:error, :invalid_order} = Tasks.reorder_tasks(scope, course.id, [c.id, a.id])
      assert positions(course.id) == before
      assert before == [{a.id, 0}, {b.id, 1}, {c.id, 2}]
    end

    test "returns unauthorized for a foreign scope" do
      {_scope, course, [a, b, c]} = course_with_tasks(3)
      other_scope = user_scope_fixture()

      assert {:error, :unauthorized} =
               Tasks.reorder_tasks(other_scope, course.id, [c.id, b.id, a.id])

      assert positions(course.id) == [{a.id, 0}, {b.id, 1}, {c.id, 2}]
    end

    test "admins may reorder another teacher's course" do
      {_scope, course, [a, b, c]} = course_with_tasks(3)
      admin_scope = user_scope_fixture(user_fixture(%{role: "admin"}))

      assert {:ok, :reordered} = Tasks.reorder_tasks(admin_scope, course.id, [c.id, b.id, a.id])
      assert positions(course.id) == [{c.id, 0}, {b.id, 1}, {a.id, 2}]
    end
  end
end
