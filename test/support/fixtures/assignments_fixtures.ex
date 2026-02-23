defmodule Tasky.AssignmentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Tasky.Assignments` context.
  """

  @doc """
  Generate a assignment.
  """
  def assignment_fixture(attrs \\ %{}) do
    {:ok, assignment} =
      attrs
      |> Enum.into(%{
        link: "some link",
        name: "some name",
        status: "some status"
      })
      |> Tasky.Assignments.create_assignment()

    assignment
  end
end
