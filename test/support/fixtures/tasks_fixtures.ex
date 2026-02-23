defmodule Tasky.TasksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Tasky.Tasks` context.
  """

  @doc """
  Generate a task.
  """
  def task_fixture(scope, attrs \\ %{}) do
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
end
