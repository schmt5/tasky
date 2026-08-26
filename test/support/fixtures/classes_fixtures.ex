defmodule Tasky.ClassesFixtures do
  @moduledoc """
  Test helpers for creating classes via `Tasky.Classes`.
  """

  alias Tasky.Classes

  import Tasky.OrganizationsFixtures, only: [default_organization: 0]

  @doc """
  Creates a class, by default in the shared test organization so it lines up
  with the teachers and students `user_fixture/1` produces.

  Pass `organization_id: nil` for an unfiled class (only reachable for rows that
  predate organizations, or after their organization was deleted).
  """
  def class_fixture(attrs \\ %{}) do
    {organization_id, attrs} = Map.pop(attrs, :organization_id, :default)

    attrs =
      attrs
      |> Enum.into(%{name: "Klasse #{System.unique_integer([:positive])}"})
      |> Map.put(:organization_id, resolve_organization_id(organization_id))

    # `:system` resolves to `:all`, so the admin path applies and may name the
    # organization explicitly.
    {:ok, class} = Classes.create_class(:system, attrs)
    class
  end

  defp resolve_organization_id(:default), do: default_organization().id
  defp resolve_organization_id(other), do: other
end
