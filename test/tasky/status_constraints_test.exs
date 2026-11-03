defmodule Tasky.StatusConstraintsTest do
  @moduledoc """
  The database refuses a role or status outside the known values even when a
  write goes around the changesets (see the AddStatusAndRoleChecks migration).
  """
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures
  import Tasky.TasksFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Tasks

  defp write(struct, changes), do: struct |> Ecto.Changeset.change(changes) |> Repo.update()

  test "users.role" do
    assert_raise Ecto.ConstraintError, ~r/users_role_check/, fn ->
      write(user_fixture(), role: "superuser")
    end
  end

  test "tasks.status" do
    task = task_fixture(user_scope_fixture())

    assert_raise Ecto.ConstraintError, ~r/tasks_status_check/, fn ->
      write(task, status: "archived")
    end
  end

  test "task_submissions.status" do
    teacher_scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
    task = task_fixture(teacher_scope, %{status: "open"})
    student = user_fixture(%{role: "student"})
    {:ok, submission} = Tasks.get_or_create_submission(Scope.for_user(student), task.id)

    assert_raise Ecto.ConstraintError, ~r/task_submissions_status_check/, fn ->
      write(submission, status: "graded")
    end
  end

  test "exams.status" do
    assert_raise Ecto.ConstraintError, ~r/exams_status_check/, fn ->
      write(exam_fixture(), status: "archived")
    end
  end
end
