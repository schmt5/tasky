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

    test "create_task/2 defaults to a mandatory (non-extended) unit" do
      scope = user_scope_fixture()
      refute task_fixture(scope).extended
    end

    test "create_task/2 and update_task/3 round-trip the extended flag" do
      scope = user_scope_fixture()

      task = task_fixture(scope, %{extended: true})
      assert task.extended

      assert {:ok, %Task{extended: false}} = Tasks.update_task(scope, task, %{extended: false})
    end

    test "change_new_task/2 builds a changeset for a unit that has no owner yet" do
      scope = user_scope_fixture()

      changeset = Tasks.change_new_task(scope, %{"name" => "Kapitel 1", "extended" => "true"})

      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :extended)
    end
  end

  describe "course_progress/1" do
    import Tasky.AccountsFixtures, only: [user_fixture: 1, user_scope_fixture: 1]
    import Tasky.CoursesFixtures
    import Tasky.TasksFixtures

    # Only `task.extended` and `status` matter here — no DB round-trip needed.
    defp submission(status, extended \\ false) do
      %Tasky.Tasks.TaskSubmission{
        status: status,
        task: %Tasky.Tasks.Task{extended: extended}
      }
    end

    test "counts mandatory units only" do
      progress =
        Tasks.course_progress([
          submission("completed"),
          submission("in_progress"),
          submission("not_started"),
          submission("completed", true)
        ])

      assert progress.total == 3
      assert progress.completed == 1
      assert progress.percent == 33
      refute progress.no_mandatory?
    end

    test "reports completed and open extensions separately" do
      progress =
        Tasks.course_progress([
          submission("completed"),
          submission("review_approved", true),
          submission("not_started", true),
          submission("in_progress", true)
        ])

      assert progress.extended_total == 3
      assert progress.extended_completed == 1
      # The extensions never dilute the bar.
      assert progress.percent == 100
    end

    test "an eingereichte unit counts before the teacher approves it" do
      progress = Tasks.course_progress([submission("completed"), submission("review_approved")])

      assert progress.percent == 100
      assert progress.graded == 1
    end

    test "a course of nothing but extensions reports 100 % instead of dividing by zero" do
      progress = Tasks.course_progress([submission("not_started", true)])

      assert progress.total == 0
      assert progress.percent == 100
      assert progress.no_mandatory?
    end

    test "mandatory work done while extensions stay open" do
      progress =
        Tasks.course_progress([
          submission("completed"),
          submission("completed"),
          submission("not_started", true)
        ])

      assert progress.percent == 100
      assert progress.completed == progress.total
      assert progress.extended_total == 1
      assert progress.extended_completed == 0
    end

    test "reads the flag off the real submissions of a course" do
      scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
      course = course_fixture(scope: scope)

      task_fixture(scope, %{
        name: "Pflicht",
        position: 0,
        status: "published",
        course_id: course.id
      })

      task_fixture(scope, %{
        name: "Vertiefung",
        position: 1,
        status: "published",
        course_id: course.id,
        extended: true
      })

      student = user_fixture(%{role: "student"})
      Tasky.Courses.enroll_student(course.id, student.id)
      student_scope = user_scope_fixture(student)

      progress =
        student_scope
        |> Tasks.list_course_submissions(course.id)
        |> Tasks.course_progress()

      assert progress.total == 1
      assert progress.extended_total == 1
      assert progress.percent == 0
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
