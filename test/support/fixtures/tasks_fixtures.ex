defmodule Tasky.TasksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Tasky.Tasks` context.
  """

  alias Tasky.Accounts.Scope

  @doc """
  Generate a task.

  Accepts either a `%Tasky.Accounts.Scope{}` or a `%Tasky.Accounts.User{}`
  as the first argument. When a User is given it is automatically wrapped
  in a Scope so that tests can pass either type without ceremony.
  """
  def task_fixture(scope_or_user, attrs \\ %{})

  def task_fixture(%Scope{} = scope, attrs) do
    attrs =
      Enum.into(attrs, %{
        link: "some link",
        name: "some name",
        position: 42,
        status: "some status"
      })

    {:ok, task} = Tasky.Tasks.create_task(scope, attrs)
    task
  end

  def task_fixture(%Tasky.Accounts.User{} = user, attrs) do
    task_fixture(Scope.for_user(user), attrs)
  end
end
