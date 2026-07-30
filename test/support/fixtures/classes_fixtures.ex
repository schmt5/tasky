defmodule Tasky.ClassesFixtures do
  @moduledoc """
  Test helpers for creating classes via `Tasky.Classes`.
  """

  alias Tasky.Classes

  def class_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: "Klasse #{System.unique_integer([:positive])}"})

    {:ok, class} = Classes.create_class(attrs)
    class
  end
end
